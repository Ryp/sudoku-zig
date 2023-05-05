const std = @import("std");
const assert = std.debug.assert;

const sdl2 = @import("sdl2/sdl2_backend.zig");
const sudoku = @import("sudoku/game.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Parse arguments
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    assert(args.len >= 3);
    const box_w = try std.fmt.parseUnsigned(u32, args[1], 0);
    const box_h = try std.fmt.parseUnsigned(u32, args[2], 0);

    // Create game state
    var game_state = try sudoku.create_game_state(gpa.allocator(), box_w, box_h);
    defer sudoku.destroy_game_state(gpa.allocator(), &game_state);

    if (args.len >= 4) {
        sudoku.fill_from_string(&game_state, args[3]);
    }

    sudoku.start_game(&game_state);

    try sdl2.execute_main_loop(gpa.allocator(), &game_state);
}
