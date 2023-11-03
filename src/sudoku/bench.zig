const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const brute_solver = @import("brute_solver.zig");
const boards = @import("boards.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var board = try sudoku.create_board_state(allocator, sudoku.GameType{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } });
    defer sudoku.destroy_board_state(allocator, board);

    sudoku.fill_board_from_string(board.numbers, boards.special_17_clues.board, board.extent);

    assert(brute_solver.solve(&board, .{}));
}
