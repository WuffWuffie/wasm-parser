const std = @import("std");
const wasm = @import("wasm");
const options = @import("options");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const cwd = Io.Dir.cwd();
    const file = try cwd.openFile(init.io, options.wasm_source, .{});

    var stdout_file = Io.File.stdout();
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(init.io, &read_buffer);

    try wasm.dump.formatModule(&file_reader.interface, allocator, stdout);

    try stdout.print("\n", .{});
    try stdout.flush();

    // var discarding_buffer: [4096]u8 = undefined;
    // var discarding_writer = Io.Writer.Discarding.init(&discarding_buffer);
    // const writer = &discarding_writer.writer;

    // const start = Io.Timestamp.now(init.io, .awake);

    // for (0..128) |_| {
    //     var read_buffer: [4096]u8 = undefined;
    //     var file_reader = file.reader(init.io, &read_buffer);

    //     try wasm.dump.formatModule(&file_reader.interface, allocator, writer);

    //     try writer.flush();
    // }

    // const elapsed = start.untilNow(init.io, .awake);
    // std.debug.print("{f}\n", .{elapsed});
}
