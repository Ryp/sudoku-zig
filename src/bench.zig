const std = @import("std");

const board = @import("sudoku/board.zig");
const solver = @import("sudoku/solver.zig");
const known_boards = @import("sudoku/known_boards.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    inline for (known_boards.TestBacktrackingSolver) |known_board| {
        std.debug.print("Testing solver on known board: rules = {}, start = {s}\n", .{ known_board.rules, known_board.start_string });

        var board_state: board.Board = try .init(known_board.rules);
        try board_state.fill_board_from_string(known_board.start_string);

        try std.testing.expect(try solver.solve(allocator, &board_state, .{}) > 0);

        var solution_board: board.Board = try .init(known_board.rules);
        try solution_board.fill_board_from_string(known_board.solution_string);

        try std.testing.expect(std.mem.eql(?board.NumberType, board_state.numbers(), solution_board.numbers()));
    }
}
