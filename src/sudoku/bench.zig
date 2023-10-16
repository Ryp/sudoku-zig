const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const brute_solver = @import("brute_solver.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create game state
    var game = try sudoku.create_game_state(allocator, sudoku.GameType{ .regular = .{
        .box_w = 4,
        .box_h = 3,
    } }, "8.9....B.4C.C......3.B9...B5..A8.2...2.4..5........9........7...1B69...32...C47A...B........5........1..A.7...5.87..13...8A.3......2.14.5....8.C");
    defer sudoku.destroy_game_state(allocator, &game);

    assert(brute_solver.solve(&game, .{}));
}
