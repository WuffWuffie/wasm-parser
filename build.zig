const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("wasm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // const lib = b.addLibrary(.{
    //     .name = "wasmparser",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("src/root.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //     }),
    // });

    // const install = b.addInstallFile(lib.getEmittedAsm(), "wasmparser.s");
    // b.default_step.dependOn(&install.step);

    const testlib = b.addExecutable(.{
        .name = "testlib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/testlib.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
                .cpu_model = .baseline,
            }),
            .optimize = .ReleaseSmall,
        }),
    });

    testlib.export_memory = true;
    testlib.stack_size = 65536;
    testlib.rdynamic = true;
    testlib.entry = .disabled;

    b.installArtifact(testlib);

    const exe = b.addExecutable(.{
        .name = "tmp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/dump.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wasm", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
