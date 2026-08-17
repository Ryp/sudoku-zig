const std = @import("std");

const board = @import("sudoku/board.zig");
const solver = @import("sudoku/solver.zig");
const known_boards = @import("sudoku/known_boards.zig");

pub fn main() !void {
    inline for (known_boards.TestDancingLinksSolver) |known_board| {
        std.debug.print("Testing solver on known board: rules = {}, start = {s}\n", .{ known_board.rules, known_board.start_string });

        var board_state: board.Board = .init(known_board.rules);
        try board_state.fill_board_from_string(known_board.start_string);

        try std.testing.expect(solver.solve(&board_state, .{ .dancing_links = .{} }));

        var solution_board: board.Board = .init(known_board.rules);
        try solution_board.fill_board_from_string(known_board.solution_string);

        try std.testing.expect(std.mem.eql(?board.NumberType, board_state.numbers(), solution_board.numbers()));
    }
}
