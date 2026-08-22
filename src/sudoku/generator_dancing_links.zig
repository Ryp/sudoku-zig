const std = @import("std");

const rules = @import("rules.zig");
const board = @import("board.zig");
const known_boards = @import("known_boards.zig");
const validator = @import("validator.zig");

const dancing_links_solver = @import("solver_dancing_links.zig");

pub fn generate(allocator: std.mem.Allocator, board_rules: rules.Rules, seed: u64, difficulty: u32) !board.Board {
    if (board_rules.chess_anti_king or board_rules.chess_anti_knight) {
        std.debug.print("error: generating puzzles with chess constraints isn't supported yet, please provide a sudoku string instead\n", .{});
        return error.UnsupportedDLXGeneratorChessRules;
    }

    const extent = board_rules.type.extent();

    var board_state: board.Board = try .init(board_rules);

    var rng = std.Random.Xoshiro256.init(seed);

    var matrix: dancing_links_solver.Matrix = try .init(allocator, &board_state);
    defer matrix.deinit(allocator);

    // Fill the board with a full solution using a randomized solving walk
    // We started with an empty matrix (fully uncovered) and after the solve this state is restored
    if (!matrix.solve_recursive(&rng.random())) {
        std.debug.print("error: failed to find solution for the generated sudoku, most likely from an invalid set of rules\n", .{});
        return error.InvalidSudokuGeneratorRules;
    }

    var try_harder_count = difficulty;

    // Remove random clues as long as the board has a unique solution
    while (true) {
        const random_index = rng.random().uintLessThan(u32, extent * extent);
        const number_opt = board_state.numbers()[random_index];

        if (number_opt) |number| {
            board_state.numbers()[random_index] = null;

            matrix.cover_choices_for_given_clues();

            const solution_count = matrix.count_solutions_recursive(2);

            // Go back to a fully uncovered matrix
            matrix.uncover_choices_for_given_clues();

            if (solution_count != 1) {
                // Whoops, we've gone one step too far - restore the number
                board_state.numbers()[random_index] = number;

                if (try_harder_count > 0) {
                    try_harder_count -= 1;
                } else {
                    break;
                }
            }
        }
    }

    return board_state;
}

test "generate all" {
    const Seed: u64 = 0xDEAD_BEEF_CAFE_BABE;
    const Difficulty: u32 = 50;

    inline for (.{
        rules.Regular3x3,
        rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 4, 3 } } } },
        rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 4, 4 } } } },
        known_boards.jigsaw9.rules,
    }) |board_rules| {
        var generated_board = try generate(std.testing.allocator, board_rules, Seed, Difficulty);

        // A full grid is trivially valid and unique, so make sure clues were actually removed
        var empty_cell_count: u32 = 0;
        for (generated_board.numbers_const()) |number_opt| {
            if (number_opt == null) {
                empty_cell_count += 1;
            }
        }
        try std.testing.expect(empty_cell_count > 0);

        try std.testing.expectEqual(null, validator.check_board_for_errors(&generated_board, null));
        try std.testing.expectEqual(1, try dancing_links_solver.solve(std.testing.allocator, &generated_board, .{ .solution_count_max = 2, .fill_solution = false }));
    }
}
