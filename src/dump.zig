const std = @import("std");
const wasm = @import("wasm");
const Io = std.Io;

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
    while (true) {
        const op = try wasm.opcode(reader);
        if (op == .end) break;
        try out.print(" {s}", .{op.name()});
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
    while (true) {
        var section_buffer: [4096]u8 = undefined;
        const section, var section_reader =
            try wasm.section(module_reader, &section_buffer) orelse break;
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

                    try out.print("))\n", .{});
                }
            },
            .import => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    const lib_name = try wasm.string(reader, allocator);
                    const name = try wasm.string(reader, allocator);
                    const kind = try wasm.externKind(reader);
                    try out.print("  (import \"{f}\" \"{f}\" ", .{
                        std.zig.fmtString(lib_name),
                        std.zig.fmtString(name),
                    });
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
                    try formatConstExpr(reader, out);
                    try out.print(")\n", .{});
                }
            },
            .@"export" => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    const name = try wasm.string(reader, allocator);
                    const ty = try wasm.externKind(reader);
                    const id = try reader.takeLeb128(u32);
                    try out.print(
                        "  (export \"{f}\" ({t} {}))\n",
                        .{ std.zig.fmtString(name), ty, id },
                    );
                }
            },
            .element => {
                const count = try reader.takeLeb128(u32);
                for (0..count) |_| {
                    const variant = try wasm.elemVariant(reader);
                    switch (variant) {
                        .active_zero => {
                            try out.print("  (elem (table 0) (offset", .{});
                            try formatConstExpr(reader, out);
                            try out.print(") func", .{});
                        },
                        .passive => {
                            const kind = try wasm.elemKind(reader);
                            try out.print("  (elem {t} func", .{kind});
                        },
                        .active => {
                            const table_idx = try reader.takeLeb128(u32);
                            try out.print("  (elem (table {}) (offset", .{table_idx});
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
                            try out.print("  (data (offset", .{});
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
                    const bytes = try wasm.string(reader, allocator);
                    defer allocator.free(bytes);
                    try out.print(" \"{f}\")\n", .{std.zig.fmtString(bytes)});
                }
            },
            .custom => {
                const name = try wasm.string(reader, allocator);
                try out.print("  (; custom \"{f}\" ;)\n", .{std.zig.fmtString(name)});
                _ = try reader.discardRemaining();
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
                        const ty = try wasm.valType(reader);
                        const group_size = try reader.takeLeb128(u32);
                        for (0..group_size) |_| {
                            try out.print(" {}", .{ty});
                        }
                    }
                    try out.print(")", .{});

                    var insts: usize = 0;
                    var depth: usize = 0;
                    while (true) {
                        const op = try wasm.opcode(reader);
                        if (op == .end) {
                            if (depth == 0) break;
                            depth -= 1;
                        }
                        insts += 1;
                        try out.print("\n", .{});
                        try out.splatByteAll(' ', 4 + 2 * depth);
                        try out.print("{s}", .{op.name()});
                        switch (op) {
                            .local_get, .local_set, .local_tee, .global_get, .global_set => {
                                const idx = try reader.takeLeb128(u32);
                                try out.print(" {}", .{idx});
                            },
                            else => {},
                        }
                    }

                    try out.print("{s}", .{if (insts > 0) "\n  )\n" else ")\n"});

                    const remaining_after = section_reader.remaining.toInt().? + reader.bufferedLen();
                    if (remaining_after != remainig_end) return error.ParseError;
                }
            },
            else => {
                try out.print("section: {t}\n", .{section});
                _ = try reader.discardRemaining();
            },
        }
    }
    try out.print(")", .{});
}

pub const ModuleFormatter = struct {
    reader: *Io.Reader,
    allocator: std.mem.Allocator,

    pub fn format(self: ModuleFormatter, writer: *Io.Writer) Io.Writer.Error!void {
        self.tryFormat(writer) catch {
            return error.WriteFailed;
        };
    }
};

pub fn fmtModule(allocator: std.mem.Allocator, reader: *Io.Reader) ModuleFormatter {
    return .{ .reader = reader, .allocator = allocator };
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const cwd = Io.Dir.cwd();
    const file = try cwd.openFile(init.io, "zig-out/bin/testlib.wasm", .{});

    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(init.io, &read_buffer);

    var stdout_file = Io.File.stdout();
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try formatModule(&file_reader.interface, allocator, stdout);

    try stdout.flush();

    // std.debug.print("{f}\n", .{fmtModule(allocator, &file_reader.interface)});
}
