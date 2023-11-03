const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const brute_solver = @import("brute_solver.zig");
const boards = @import("boards.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var game = try sudoku.create_game_state(allocator, sudoku.GameType{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } }, boards.special_17_clues.board);
    defer sudoku.destroy_game_state(allocator, &game);

    assert(brute_solver.solve(&game, .{}));
}
