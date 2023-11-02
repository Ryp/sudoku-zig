const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const brute_solver = @import("brute_solver.zig");

// NOTE: See https://stackoverflow.com/questions/24682039/whats-the-worst-case-valid-sudoku-puzzle-for-simple-backtracking-brute-force-al
const naive_backtracking_killer = "..............3.85..1.2.......5.7.....4...1...9.......5......73..2.1........4...9";
const naive_backtracking_killer_2 = "9..8...........5............2..1...3.1.....6....4...7.7.86.........3.1..4.....2..";
const easy_17_clues = "...8.1..........435............7.8........1...2..3....6......75..34........2..6..";

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var game = try sudoku.create_game_state(allocator, sudoku.GameType{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } }, easy_17_clues);
    defer sudoku.destroy_game_state(allocator, &game);

    assert(brute_solver.solve(&game, .{}));
}
