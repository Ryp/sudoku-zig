const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const sudoku = @import("game.zig");
const brute_solver = @import("brute_solver.zig");
const boards = @import("boards.zig");

test "Critical path" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Create game board
    var board = try sudoku.create_board_state(allocator, sudoku.GameType{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } });
    defer sudoku.destroy_board_state(allocator, board);

    sudoku.fill_board_from_string(board.numbers, boards.easy_000.board, board.extent);

    try expectEqual(board.extent, 9);

    const solved = brute_solver.solve(&board, .{});
    try expect(solved);

    // Compare with solution
    const solution_board = try allocator.alloc(u5, board.extent * board.extent);
    defer allocator.free(solution_board);

    sudoku.fill_board_from_string(solution_board, boards.easy_000.solution, board.extent);

    try expect(std.mem.eql(u5, board.numbers, solution_board));
}
