const std = @import("std");
const wasm = @import("root.zig");
const Io = std.Io;

fn opc(comptime opcode: wasm.Opcode) comptime_int {
    return @intFromEnum(opcode);
}

const StringFormatter = struct {
    reader: *Io.Reader,
    size: usize,

    pub fn format(self: StringFormatter, writer: *Io.Writer) Io.Writer.Error!void {
        var remaining = self.size;
        while (remaining != 0) {
            const slice = self.reader.take(@min(self.reader.buffer.len, remaining)) catch {
                return error.WriteFailed;
            };
            remaining -= slice.len;
            for (slice) |c| {
                switch (c) {
                    '\t' => try writer.print("\\t", .{}),
                    '\r' => try writer.print("\\r", .{}),
                    '\n' => try writer.print("\\n", .{}),
                    '"' => try writer.print("\\\"", .{}),
                    '\\' => try writer.print("\\\\", .{}),
                    0x20...0x21, 0x23...0x5B, 0x5D...0x7E => try writer.print("{c}", .{c}),
                    else => try writer.print("\\{X:02}", .{c}),
                }
            }
        }
    }
};

fn formatString(reader: *Io.Reader) !StringFormatter {
    const size = try reader.takeLeb128(u32);
    return .{ .reader = reader, .size = size };
}

fn formatMemory(memory: wasm.Memory, out: *Io.Writer) !void {
    if (memory.limits.flags.has_max) {
        try out.print("(memory {} {})", .{
            memory.limits.min,
            memory.limits.max,
        });
    } else {
        try out.print("(memory {})", .{
            memory.limits.min,
        });
    }
}

fn formatTable(table: wasm.Table, out: *Io.Writer) !void {
    if (table.limits.flags.has_max) {
        try out.print("(table {} {} {t})", .{
            table.limits.min,
            table.limits.max,
            table.ref_type,
        });
    } else {
        try out.print("(table {} {t})", .{
            table.limits.min,
            table.ref_type,
        });
    }
}

fn formatGlobalType(ty: wasm.GlobalType, out: *Io.Writer) !void {
    if (ty.mut != .@"const") {
        try out.print(" (mut {t})", .{ty.type});
    } else {
        try out.print(" {t}", .{ty.type});
    }
}

fn formatConstExpr(reader: *Io.Reader, out: *Io.Writer) !void {
    var count: usize = 0;
    while (true) {
        const op = try wasm.opcode(reader);
        if (op == .end) break;
        if (count > 0) try out.print(" ", .{});
        count += 1;
        try out.print("{s}", .{op.name()});
        switch (op) {
            .i32_const => {
                const val = try reader.takeLeb128(i32);
                try out.print(" {}", .{val});
            },
            .i64_const => {
                const val = try reader.takeLeb128(i64);
                try out.print(" {}", .{val});
            },
            .f32_const => {
                const val = try reader.takeInt(i32, .little);
                try out.print(" {}", .{@as(f32, @bitCast(val))});
            },
            .f64_const => {
                const val = try reader.takeInt(i64, .little);
                try out.print(" {}", .{@as(f64, @bitCast(val))});
            },
            else => return error.ParseError,
        }
    }
}

pub fn formatModule(
    module_reader: *Io.Reader,
    allocator: std.mem.Allocator,
    out: *Io.Writer,
) !void {
    try wasm.module(module_reader);

    try out.print("(module\n", .{});

    var funcs: ?[]u32 = null;
    defer if (funcs) |slice| allocator.free(slice);

    var last_section: ?wasm.Section = null;

    while (true) {
        const section, const section_size = try wasm.section(module_reader) orelse break;
        var section_buffer: [4096]u8 = undefined;
        var section_reader = module_reader.limited(.limited(section_size), &section_buffer);
        const reader = &section_reader.interface;
        switch (section) {
            .type => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    try wasm.funcType(reader);

                    try out.print("  (type (func (param", .{});
                    const param_count = try reader.takeLeb128(u32);
                    for (0..param_count) |_| {
                        const ty = try wasm.valType(reader);
                        try out.print(" {t}", .{ty});
                    }

                    try out.print(") (result", .{});
                    const res_count = try reader.takeLeb128(u32);
                    for (0..res_count) |_| {
                        const ty = try wasm.valType(reader);
                        try out.print(" {t}", .{ty});
                    }

                    try out.print(")))\n", .{});
                }
            },
            .import => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    try out.print("  (import \"{f}\"", .{try formatString(reader)});
                    try out.print(" \"{f}\" ", .{try formatString(reader)});
                    const kind = try wasm.externKind(reader);
                    switch (kind) {
                        .func => {
                            const id = try reader.takeLeb128(u32);
                            try out.print("(func (type {}))", .{id});
                        },
                        .table => {
                            const table = try wasm.table(reader);
                            try formatTable(table, out);
                        },
                        .memory => {
                            const memory = try wasm.memory(reader);
                            try formatMemory(memory, out);
                        },
                        .global => {
                            const ty = try wasm.globalType(reader);
                            try out.print("(global", .{});
                            try formatGlobalType(ty, out);
                            try out.print(")", .{});
                        },
                    }
                    try out.print(")\n", .{});
                }
            },
            .function => {
                const count = try reader.takeLeb128(u32);
                funcs = try allocator.alloc(u32, count);
                for (funcs.?) |*id| id.* = try reader.takeLeb128(u32);
            },
            .table => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    const table = try wasm.table(reader);
                    try out.print("  ", .{});
                    try formatTable(table, out);
                    try out.print("\n", .{});
                }
            },
            .memory => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    const memory = try wasm.memory(reader);
                    try out.print("  ", .{});
                    try formatMemory(memory, out);
                    try out.print("\n", .{});
                }
            },
            .global => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    const ty = try wasm.globalType(reader);
                    try out.print("  (global", .{});
                    try formatGlobalType(ty, out);
                    try out.print(" ", .{});
                    try formatConstExpr(reader, out);
                    try out.print(")\n", .{});
                }
            },
            .@"export" => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    try out.print("  (export \"{f}\" ", .{try formatString(reader)});
                    const ty = try wasm.externKind(reader);
                    const id = try reader.takeLeb128(u32);
                    try out.print("({t} {}))\n", .{ ty, id });
                }
            },
            .element => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    const variant = try wasm.elemVariant(reader);
                    switch (variant) {
                        .active_zero => {
                            try out.print("  (elem (", .{});
                            try formatConstExpr(reader, out);
                            try out.print(") func", .{});
                        },
                        .passive => {
                            const kind = try wasm.elemKind(reader);
                            try out.print("  (elem {t} func", .{kind});
                        },
                        .active => {
                            const table_idx = try reader.takeLeb128(u32);
                            try out.print("  (elem (table {}) (", .{table_idx});
                            try formatConstExpr(reader, out);
                            const kind = try wasm.elemKind(reader);
                            try out.print(") {t} func", .{kind});
                        },
                        .declarative => {
                            const kind = try wasm.elemKind(reader);
                            try out.print("  (elem declare {t} func", .{kind});
                        },
                    }
                    const elems = try reader.takeLeb128(u32);
                    for (0..elems) |_| {
                        const idx = try reader.takeLeb128(u32);
                        try out.print(" {}", .{idx});
                    }
                    try out.print(")\n", .{});
                }
            },
            .start => {
                const func_idx = try reader.takeLeb128(u32);
                try out.print("  (start {})\n", .{func_idx});
            },
            .data => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    const variant = try wasm.dataVariant(reader);
                    switch (variant) {
                        .active_zero => {
                            try out.print("  (data (", .{});
                            try formatConstExpr(reader, out);
                            try out.print(")", .{});
                        },
                        .passive => {
                            try out.print("  (data", .{});
                        },
                        .active => {
                            const mem_idx = try reader.takeLeb128(u32);
                            try out.print("  (data (memory {}) (offset", .{mem_idx});
                            try formatConstExpr(reader, out);
                            try out.print(")", .{});
                        },
                    }
                    try out.print(" \"{f}\")\n", .{try formatString(reader)});
                }
            },
            .custom => {
                try out.print("  (@custom \"{f}\" ", .{try formatString(reader)});
                if (last_section) |s| {
                    try out.print("(after {t})", .{s});
                } else {
                    try out.print("(before first)", .{});
                }
                const remaining = section_reader.remaining.toInt().? + reader.bufferedLen();
                const str = StringFormatter{ .reader = reader, .size = remaining };
                try out.print(" \"{f}\")\n", .{str});
            },
            .code => {
                const count = try reader.takeLeb128(u32);
                if (funcs == null or count != funcs.?.len) {
                    return error.ParseError;
                }
                for (funcs.?) |id| {
                    const code_size = try reader.takeLeb128(u32);
                    const remaining = section_reader.remaining.toInt().? + reader.bufferedLen();
                    if (code_size > remaining) return error.ParseError;
                    const remainig_end = remaining - code_size;

                    try out.print("  (func (type {}) (local", .{id});
                    const local_groups = try reader.takeLeb128(u32);
                    for (0..local_groups) |_| {
                        const group_size = try reader.takeLeb128(u32);
                        const ty = try wasm.valType(reader);
                        for (0..group_size) |_| {
                            try out.print(" {t}", .{ty});
                        }
                    }
                    try out.print(")", .{});

                    var insts: usize = 0;
                    var scopes: usize = 0;
                    while (true) {
                        const op = try wasm.opcode(reader);
                        if (op == .end) {
                            if (scopes == 0) break;
                            scopes -= 1;
                        }
                        insts += 1;
                        try out.print("\n", .{});
                        try out.splatByteAll(' ', 4 + 2 * scopes);
                        try out.print("{s}", .{op.name()});

                        switch (@intFromEnum(op)) {
                            opc(.@"unreachable")...opc(.nop),
                            opc(.end),
                            opc(.@"return"),
                            opc(.drop)...opc(.select),
                            opc(.i32_eqz)...opc(.i64_extend32_s),
                            => {},
                            opc(.i32_load)...opc(.i64_store32) => {
                                const memop = try wasm.memOp(reader);
                                const alignment = @as(u32, 1) << @truncate(memop.flags.alignment);
                                try out.print(
                                    " (memory {}) (offset {}) (align {})",
                                    .{ memop.memory, memop.offset, alignment },
                                );
                            },
                            opc(.block)...opc(.@"if") => {
                                const typ = try wasm.blockType(reader);
                                switch (typ) {
                                    .empty => {},
                                    .i32, .i64, .f32, .f64, .v128 => {
                                        try out.print(" (result {t})", .{typ});
                                    },
                                    else => {
                                        try out.print(" (type {})", .{typ.id()});
                                    },
                                }
                                scopes += 1;
                            },
                            opc(.br_table) => {
                                const branches = try reader.takeLeb128(u32);
                                for (0..branches + 1) |_| {
                                    const idx = try reader.takeLeb128(u32);
                                    try out.print(" {}", .{idx});
                                }
                            },
                            opc(.br)...opc(.br_if),
                            opc(.call),
                            opc(.return_call),
                            opc(.local_get)...opc(.global_set),
                            => {
                                const idx = try reader.takeLeb128(u32);
                                try out.print(" {}", .{idx});
                            },
                            opc(.call_indirect),
                            opc(.return_call_indirect),
                            => {
                                const type_id = try reader.takeLeb128(u32);
                                const table_id = try reader.takeLeb128(u32);
                                try out.print(" (table {}) (type {})", .{ table_id, type_id });
                            },
                            opc(.select_t) => {
                                const res_count = try reader.takeLeb128(u32);
                                for (0..res_count) |_| {
                                    const ty = try wasm.valType(reader);
                                    try out.print(" {t}", .{ty});
                                }
                            },
                            opc(.memory_size)...opc(.memory_grow) => {
                                const idx = try reader.takeLeb128(u32);
                                try out.print(" (memory {})", .{idx});
                            },
                            opc(.i32_const) => {
                                const val = try reader.takeLeb128(i32);
                                try out.print(" {}", .{val});
                            },
                            opc(.i64_const) => {
                                const val = try reader.takeLeb128(i64);
                                try out.print(" {}", .{val});
                            },
                            opc(.f32_const) => {
                                const val = try reader.takeInt(i32, .little);
                                try out.print(" {}", .{@as(f32, @bitCast(val))});
                            },
                            opc(.f64_const) => {
                                const val = try reader.takeInt(i64, .little);
                                try out.print(" {}", .{@as(f64, @bitCast(val))});
                            },
                            else => {
                                std.debug.print("unsupported instruction: {s}\n", .{op.name()});
                                return error.InvalidInstruction;
                            },
                        }
                    }

                    try out.print("{s}", .{if (insts > 0) "\n  )\n" else ")\n"});

                    const remaining_after = section_reader.remaining.toInt().? + reader.bufferedLen();
                    if (remaining_after != remainig_end) return error.ParseError;
                }
            },
            else => {
                try out.print("skipped section: {t}\n", .{section});
                _ = try reader.discardRemaining();
            },
        }

        if (section != .custom) last_section = section;
    }
    try out.print(")", .{});
}

pub const ModuleFormatter = struct {
    reader: *Io.Reader,
    allocator: std.mem.Allocator,

    pub fn format(self: ModuleFormatter, writer: *Io.Writer) Io.Writer.Error!void {
        formatModule(self.reader, self.allocator, writer) catch {
            return error.WriteFailed;
        };
    }
};

pub fn fmtModule(allocator: std.mem.Allocator, reader: *Io.Reader) ModuleFormatter {
    return .{ .reader = reader, .allocator = allocator };
}
