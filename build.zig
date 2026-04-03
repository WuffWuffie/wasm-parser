const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("wasm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const testlib = b.addExecutable(.{
        .name = "testlib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/testlib.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
                .cpu_model = .baseline,
            }),
            // .optimize = .ReleaseSmall,
        }),
    });

    testlib.export_memory = true;
    testlib.stack_size = 65536;
    testlib.rdynamic = true;
    testlib.entry = .disabled;

    const options = b.addOptions();
    options.addOptionPath("wasm_source", testlib.getEmittedBin());
    const options_mod = options.createModule();

    const exe = b.addExecutable(.{
        .name = "dumper",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/dumper.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wasm", .module = mod },
                .{ .name = "options", .module = options_mod },
            },
        }),
    });

    if (optimize != .Debug and optimize != .ReleaseSafe) {
        exe.lto = .full;
        exe.root_module.strip = true;
        exe.root_module.omit_frame_pointer = true;
    }

    const run_step = b.step("dump", "Dump WebAssembly");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
