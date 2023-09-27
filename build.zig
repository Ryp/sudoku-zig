const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "sudoku",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
    });

    b.installArtifact(exe);

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_ttf");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    const a_test = b.addTest(.{
        .name = "test",
        .root_source_file = .{ .path = "src/sudoku/test.zig" },
        .optimize = optimize,
    });

    test_step.dependOn(&a_test.step);
}
