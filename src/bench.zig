const std = @import("std");

const board_generic = @import("sudoku/board_generic.zig");
const solver = @import("sudoku/solver.zig");
const known_boards = @import("sudoku/known_boards.zig");

pub fn main() !void {
    const board_type = board_generic.BoardType{ .regular = .{
        .box_extent = .{ 3, 3 },
    } };
    const board_extent = comptime board_type.extent();

    var board = board_generic.State(board_extent).init(board_type);

    board.fill_board_from_string(known_boards.special_dancing_links.board);

    std.debug.assert(solver.solve(board_extent, &board, .{ .dancing_links = .{} }));
}
