const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const sudoku = @import("game.zig");
const brute_solver = @import("brute_solver.zig");

test "Critical path" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const gpa_allocator = gpa.allocator();
    // const allocator = std.heap.page_allocator;

    const box_w = 3;
    const box_h = 3;
    const sudoku_string = "58.1....7...5...26..27.4..3.....1..41..........42...........6.87.1..3.....54..9..";

    // Create game state
    var game = try sudoku.create_game_state(gpa_allocator, box_w, box_h, "");
    defer sudoku.destroy_game_state(gpa_allocator, &game);

    sudoku.fill_from_string(&game, sudoku_string);

    sudoku.start_game(&game);

    try expectEqual(game.box_w, 3);
    try expectEqual(game.box_h, 3);
    try expectEqual(game.extent, 9);

    const solved = brute_solver.solve(&game);
    try expect(solved);
}
