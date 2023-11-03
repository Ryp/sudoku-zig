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

    // Create game state
    var game = try sudoku.create_game_state(allocator, sudoku.GameType{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } }, boards.easy_000.board);
    defer sudoku.destroy_game_state(allocator, &game);

    try expectEqual(game.extent, 9);

    const solved = brute_solver.solve(&game, .{});
    try expect(solved);

    const solution_board = try allocator.alloc(u5, game.extent * game.extent);
    defer allocator.free(solution_board);

    sudoku.fill_board_from_string(solution_board, boards.easy_000.solution, game.extent);

    try expect(std.mem.eql(u5, game.board, solution_board));
}
