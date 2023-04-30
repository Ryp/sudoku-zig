const std = @import("std");
const assert = std.debug.assert;

const sdl2 = @import("sdl2/sdl2_backend.zig");
const game = @import("sudoku/game.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Parse arguments
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    assert(args.len == 1);

    // Using the method from the docs to get a reasonably random seed
    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(buf[0..]);
    const seed = std.mem.readIntSliceLittle(u64, buf[0..8]);

    // Create game state
    var game_state = try game.create_game_state(gpa.allocator(), .{ 9, 9 }, seed);
    defer game.destroy_game_state(gpa.allocator(), &game_state);

    game.start_game(&game_state);

    try sdl2.execute_main_loop(gpa.allocator(), &game_state);
}
