const std = @import("std");

const psp = @import("frontend/psp.zig");

const sdk = @import("pspsdk");

pub const panic = sdk.extra.debug.panic; // Import panic handler

pub const std_options_debug_threaded_io: ?*std.Io.Threaded = null;
pub const std_options_debug_io: std.Io = sdk.extra.Io.psp_io;

pub fn std_options_cwd() std.Io.Dir {
    return .{ .handle = -1 };
}

comptime {
    asm (sdk.extra.module.module_info("Sudoku", .{ .mode = .User }, 1, 0));
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    try psp.execute_main_loop(init.io, allocator);
}
