const std = @import("std");

const board_generic = @import("sudoku/board_generic.zig");
const solver = @import("sudoku/solver.zig");
const known_boards = @import("sudoku/known_boards.zig");

pub fn main() !void {
    inline for (known_boards.TestDancingLinksSolver) |known_board| {
        std.debug.print("Testing solver on known board: type = {}, start = {s}\n", .{ known_board.board_type, known_board.start_string });
        const board_extent = comptime known_board.board_type.extent();

        var board = board_generic.State(board_extent).init(known_board.board_type);
        board.fill_board_from_string(known_board.start_string);

        try std.testing.expect(solver.solve(board_extent, &board, .{ .dancing_links = .{} }));

        var solution_board = board_generic.State(board_extent).init(known_board.board_type);
        solution_board.fill_board_from_string(known_board.solution_string);

        std.debug.print("Solver: {s}\n", .{board.string_from_board()});
        std.debug.print("Actual: {s}\n", .{solution_board.string_from_board()});

        try std.testing.expectEqual(board.numbers, solution_board.numbers);
    }
}
