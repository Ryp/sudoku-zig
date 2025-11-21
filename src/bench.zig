const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("sudoku/game.zig");
const solver = @import("sudoku/solver.zig");
const boards = @import("sudoku/boards.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var board = try sudoku.BoardState.create(allocator, .{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } });
    defer board.destroy(allocator);

    sudoku.fill_board_from_string(board.numbers, boards.special_dancing_links.board, board.extent);

    assert(solver.solve(&board, .{ .dancing_links = .{} }));
}
