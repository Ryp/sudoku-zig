const std = @import("std");
const assert = std.debug.assert;

const board_legacy = @import("sudoku/board_legacy.zig");
const solver = @import("sudoku/solver.zig");
const known_boards = @import("sudoku/known_boards.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var board = try board_legacy.BoardState.create(allocator, .{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } });
    defer board.destroy(allocator);

    board.fill_board_from_string(known_boards.special_dancing_links.board);

    assert(solver.solve(&board, .{ .dancing_links = .{} }));
}
