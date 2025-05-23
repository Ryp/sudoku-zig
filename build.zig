const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize_mode = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "sudoku",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize_mode,
    });

    b.installArtifact(exe);

    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_ttf");

    exe.root_module.addAnonymousImport("font_regular", .{ .root_source_file = b.path("res/FreeSans.ttf") });
    exe.root_module.addAnonymousImport("font_bold", .{ .root_source_file = b.path("res/FreeSansBold.ttf") });

    const enable_tracy = b.option(bool, "tracy", "Enable Tracy support") orelse false;

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_tracy", enable_tracy);
    exe.root_module.addOptions("build_options", exe_options);

    if (enable_tracy) {
        const tracy_path = "external/tracy";
        const client_cpp = "external/tracy/public/TracyClient.cpp";
        const tracy_c_flags: []const []const u8 = &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

        exe.root_module.addIncludePath(b.path(tracy_path));
        exe.root_module.addCSourceFile(.{ .file = b.path(client_cpp), .flags = tracy_c_flags });

        exe.linkLibC();
        exe.linkLibCpp();
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);

    // Test
    const test_a = b.addTest(.{
        .name = "test",
        .root_source_file = b.path("src/sudoku/test.zig"),
        .target = target,
        .optimize = optimize_mode,
    });

    b.installArtifact(test_a);

    const test_cmd = b.addRunArtifact(test_a);
    test_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_cmd.step);

    // Bench
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = optimize_mode,
    });

    b.installArtifact(bench_exe);

    const bench_cmd = b.addRunArtifact(bench_exe);
    bench_cmd.step.dependOn(b.getInstallStep());

    const bench_step = b.step("bench", "Run bench");
    bench_step.dependOn(&bench_cmd.step);
}
