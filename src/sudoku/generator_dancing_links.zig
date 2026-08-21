const std = @import("std");

const rules = @import("rules.zig");
const board = @import("board.zig");
const known_boards = @import("known_boards.zig");
const validator = @import("validator.zig");

const dancing_links_solver = @import("solver_dancing_links.zig");
const Matrix = dancing_links_solver.Matrix;

pub fn generate(allocator: std.mem.Allocator, board_rules: rules.Rules, seed: u64, difficulty: u32) !board.Board {
    if (board_rules.chess_anti_king or board_rules.chess_anti_knight) {
        std.debug.print("error: generating puzzles with chess constraints isn't supported yet, please provide a sudoku string instead\n", .{});
        return error.UnsupportedDLXGeneratorChessRules;
    }

    const extent_sqr = board_rules.type.extent() * board_rules.type.extent();

    var board_state: board.Board = try .init(board_rules);

    var rng = std.Random.Xoshiro256.init(seed);

    // Fill the board with a random full solution. Scoped so we're not holding onto the
    // matrix while the uniqueness loop below builds its own.
    {
        var matrix: Matrix = try .init(allocator, &board_state);
        defer matrix.deinit(allocator);

        cover_choices_for_random_clues(&matrix, &rng.random());

        if (matrix.solve_recursive(1, true) == 0) {
            std.debug.print("error: failed to find solution for the generated sudoku, most likely that comes from an invalid set of rules\n", .{});
            return error.InvalidSudokuGeneratorRulesOrInternalError;
        }
    }

    // Remove random clues as long as the board has a unique solution
    var is_unique = true;
    var try_harder_count = difficulty;

    while (is_unique) {
        const random_index = rng.random().uintLessThan(u32, extent_sqr);
        const number_at_random_index = board_state.numbers()[random_index];

        if (number_at_random_index == null) {
            continue;
        }

        board_state.numbers()[random_index] = null;

        // FIXME reuse matrix
        is_unique = try dancing_links_solver.solve(allocator, &board_state, .{ .solution_count_max = 2, .fill_solution = false }) == 1;

        if (!is_unique) {
            // Whoops, we've gone one step too far - restore the number
            board_state.numbers()[random_index] = number_at_random_index;

            if (try_harder_count > 0) {
                try_harder_count -= 1;
                is_unique = true;
                continue;
            } else {
                break;
            }
        }
    }

    return board_state;
}

// Seed the matrix with a random permutation on the first row. Any full solution reachable
// from there is as good as any other, and it's much cheaper than shuffling the search.
// NOTE: this works for our current set of rules, but this can rot once we add more rules
// ex: when using thermometers, choosing a random number at a random place might be invalid
fn cover_choices_for_random_clues(matrix: *Matrix, random: *const std.Random) void {
    const board_state = matrix.board_state;
    const extent = board_state.extent;

    var taken_numbers_max = std.mem.zeroes([board.MaxExtent]bool);
    const taken_numbers = taken_numbers_max[0..extent];

    const line_region = board_state.regions.row(0);

    for (line_region) |cell_index| {
        var number: u4 = undefined;
        var is_taken = true;

        while (is_taken) {
            number = @intCast(random.uintLessThan(usize, extent));
            is_taken = taken_numbers[number];
        }

        taken_numbers[number] = true;

        board_state.numbers()[cell_index] = number;

        matrix.cover_choice(dancing_links_solver.get_choice_index(cell_index, number, extent));
    }
}

test "solve all" {
    const Seed: u64 = 0xDEAD_BEEF_CAFE_BABE;
    const Difficulty: u32 = 50;

    inline for (.{
        rules.Regular3x3,
        rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 4, 3 } } } },
        rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 4, 4 } } } },
        known_boards.jigsaw9.rules,
    }) |board_rules| {
        var generated_board = try generate(std.testing.allocator, board_rules, Seed, Difficulty);

        try std.testing.expectEqual(null, validator.check_board_for_errors(&generated_board, null));
        try std.testing.expectEqual(1, try dancing_links_solver.solve(std.testing.allocator, &generated_board, .{ .solution_count_max = 2, .fill_solution = false }));
    }
}
