const std = @import("std");

const board = @import("board.zig");
const solver_logical = @import("solver_logical.zig");
const known_boards = @import("known_boards.zig");
const validator = @import("validator.zig");
const rules = @import("rules.zig");

pub const Options = struct {
    solution_count_max: u32 = 1,
    fill_solution: bool = true,
    recursive: bool = true, // Fastest solver ATM
};

const BoardNumbers = [board.MaxExtentSqr]?board.NumberType;

// Returns the number of solutions found (capped by solution_count_max)
pub fn solve(board_state: *board.Board, options: Options) u32 {
    if (validator.check_board_for_errors(board_state, null) != null) {
        return 0;
    }

    var free_cell_list_max: [board.MaxExtentSqr]CellInfo = undefined;
    const free_cell_list = populate_free_list(board_state, &free_cell_list_max);

    sort_free_cell_list(board_state, free_cell_list);

    var first_solution: ?BoardNumbers = null;

    const solution_count = if (options.recursive)
        solve_backtracking_recursive(board_state, free_cell_list, options.solution_count_max, &first_solution, 0)
    else
        solve_backtracking_iterative(board_state, free_cell_list, options.solution_count_max, &first_solution);

    // The search stops wherever it ran out of budget, so the board can be left
    // holding a half-finished guess. Free cells were null on entry by
    // construction, so clearing them restores exactly what the caller passed in.
    for (free_cell_list) |free_cell| {
        board_state.numbers()[free_cell.index] = null;
    }

    if (options.fill_solution) {
        if (first_solution) |solution| {
            board_state.numbers_max = solution;
        }
    }

    return solution_count;
}

const CellInfo = struct {
    index: u8,
    col: u4,
    row: u4,
};

fn solve_backtracking_recursive(board_state: *board.Board, free_cell_list: []CellInfo, solution_count_max: u32, first_solution: *?BoardNumbers, list_index: u32) u32 {
    if (list_index >= free_cell_list.len) {
        if (first_solution.* == null) {
            first_solution.* = board_state.numbers_max;
        }

        return 1;
    }

    var solution_count: u32 = 0;

    const free_cell: CellInfo = free_cell_list[list_index];
    const valid_mask = valid_candidates_mask(board_state, free_cell);

    for (0..board_state.extent) |number| {
        if (board_state.mask_for_number(@intCast(number)) & valid_mask != 0) {
            board_state.numbers()[free_cell.index] = @intCast(number);

            solution_count += solve_backtracking_recursive(board_state, free_cell_list, solution_count_max - solution_count, first_solution, list_index + 1);

            if (solution_count >= solution_count_max) {
                return solution_count;
            }
        }
    }

    board_state.numbers()[free_cell.index] = null;
    return solution_count;
}

fn solve_backtracking_iterative(board_state: *board.Board, free_cell_list: []CellInfo, solution_count_max: u32, first_solution: *?BoardNumbers) u32 {
    // Special case already solved boards to not have to worry about underflowing list_index.
    if (free_cell_list.len == 0) {
        return 1;
    }

    var current_guess_max = std.mem.zeroes([board.MaxExtentSqr]u32);
    var current_guess = current_guess_max[0..free_cell_list.len];

    var list_index: u32 = 0;
    var solution_count: u32 = 0;

    outer_loop: while (true) {
        if (list_index == free_cell_list.len) {
            if (first_solution.* == null) {
                first_solution.* = board_state.numbers_max;
            }

            solution_count += 1;

            if (solution_count >= solution_count_max) {
                return solution_count;
            }

            // Force backtrack
            board_state.numbers()[free_cell_list[list_index - 1].index] = null;
            list_index -= 1;

            continue :outer_loop;
        }

        const free_cell = free_cell_list[list_index];
        const valid_mask = valid_candidates_mask(board_state, free_cell);

        const start: u32 = current_guess[list_index];

        for (start..board_state.extent) |number| {
            if (board_state.mask_for_number(@intCast(number)) & valid_mask != 0) {
                board_state.numbers()[free_cell.index] = @intCast(number); // Guess this number
                current_guess[list_index] = @intCast(number + 1); // If we backtrack, start after this number

                list_index += 1;

                continue :outer_loop;
            }
        } else {
            // Since we skipped the loop we shouldn't have any active guess
            // If we came here from backtracking, this should have been cleared for us
            // std.debug.assert(board_state.numbers()[free_cell.index] == null);

            // Invalidate all previous guesses for this cell
            current_guess[list_index] = 0;

            // Backtracking at index zero means we didn't find a solution
            if (list_index == 0) {
                return solution_count;
            } else {
                // Clear previous guess because it's wrong!
                board_state.numbers()[free_cell_list[list_index - 1].index] = null;
                list_index -= 1;
            }
        }
    }
}

fn valid_candidates_mask(board_state: *const board.Board, cell_info: CellInfo) board.MaskType {
    // NOTE: This is slow but needed for non-vanilla sudokus
    if (board_state.rules.chess_anti_king or board_state.rules.chess_anti_knight) {
        return solver_logical.trivial_candidate_masks_max(board_state)[cell_info.index];
    }

    const box = board_state.regions.box_indices()[cell_info.index];

    var valid_mask = board_state.full_candidate_mask();

    inline for (.{ board_state.regions.col(cell_info.col), board_state.regions.row(cell_info.row), board_state.regions.box(box) }) |region| {
        for (region) |cell_index| {
            if (board_state.numbers_const()[cell_index]) |number| {
                valid_mask &= ~board_state.mask_for_number(number);
            }
        }
    }

    return valid_mask;
}

fn populate_free_list(board_state: *const board.Board, free_cell_list_full: []CellInfo) []CellInfo {
    var list_index: u32 = 0;

    for (board_state.numbers_const(), 0..) |cell_number, cell_index| {
        if (cell_number == null) {
            const cell_coord = board_state.cell_coord_from_index(cell_index);

            free_cell_list_full[list_index] = CellInfo{
                .index = @intCast(cell_index),
                .col = @intCast(cell_coord[0]),
                .row = @intCast(cell_coord[1]),
            };
            list_index += 1;
        }
    }

    return free_cell_list_full[0..list_index];
}

fn sort_free_cell_list(board_state: *const board.Board, free_cell_list: []CellInfo) void {
    const full_mask = board_state.full_candidate_mask();
    var region_type_masks: [3][board.MaxExtent]board.MaskType = undefined;

    for (0..board_state.extent) |sub_index| {
        region_type_masks[0][sub_index] = full_mask;
        for (board_state.regions.col(sub_index)) |cell_index| {
            if (board_state.numbers_const()[cell_index]) |number| {
                region_type_masks[0][sub_index] &= ~board_state.mask_for_number(number);
            }
        }
        region_type_masks[1][sub_index] = full_mask;
        for (board_state.regions.row(sub_index)) |cell_index| {
            if (board_state.numbers_const()[cell_index]) |number| {
                region_type_masks[1][sub_index] &= ~board_state.mask_for_number(number);
            }
        }
        region_type_masks[2][sub_index] = full_mask;
        for (board_state.regions.box(sub_index)) |cell_index| {
            if (board_state.numbers_const()[cell_index]) |number| {
                region_type_masks[2][sub_index] &= ~board_state.mask_for_number(number);
            }
        }
    }

    const extent_sqr = board_state.extent * board_state.extent;
    var candidate_counts_max = std.mem.zeroes([board.MaxExtentSqr]u8);
    const candidate_counts = candidate_counts_max[0..extent_sqr];

    for (candidate_counts, 0..) |*candidate_count, cell_index| {
        const cell_coord = board_state.cell_coord_from_index(cell_index);

        const col = cell_coord[0];
        const row = cell_coord[1];
        const box = board_state.regions.box_indices()[cell_index];

        const mask = region_type_masks[0][col] & region_type_masks[1][row] & region_type_masks[2][box];
        candidate_count.* = @popCount(mask);
    }

    // Hack to pass to comparator
    const candidate_counts_slice: []u8 = candidate_counts[0..];

    std.sort.pdq(CellInfo, free_cell_list, candidate_counts_slice, cell_info_candidate_count_compare_less);
}

fn cell_info_candidate_count_compare_less(candidate_counts: []u8, lhs: CellInfo, rhs: CellInfo) bool {
    return candidate_counts[lhs.index] < candidate_counts[rhs.index];
}

const Regular2x2 = rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 2, 2 } } } };
const Regular2x2Solutions = 288;

test "Iterative" {
    inline for (known_boards.TestBacktrackingSolver) |known_board| {
        var board_state: board.Board = try .init(known_board.rules);
        try board_state.fill_board_from_string(known_board.start_string);

        try std.testing.expectEqual(1, solve(&board_state, .{ .recursive = false }));

        var solution_board: board.Board = try .init(known_board.rules);
        try solution_board.fill_board_from_string(known_board.solution_string);

        try std.testing.expectEqualSlices(?board.NumberType, solution_board.numbers(), board_state.numbers());
    }
}

test "Iterative Count All" {
    var board_state: board.Board = try .init(Regular2x2);

    try std.testing.expectEqual(Regular2x2Solutions, solve(&board_state, .{ .recursive = false, .solution_count_max = 1000 }));
}

test "Iterative Count Some" {
    var board_state: board.Board = try .init(Regular2x2);

    try std.testing.expectEqual(100, solve(&board_state, .{ .recursive = false, .solution_count_max = 100 }));
}

test "Recursive" {
    inline for (known_boards.TestBacktrackingSolver) |known_board| {
        var board_state: board.Board = try .init(known_board.rules);
        try board_state.fill_board_from_string(known_board.start_string);

        try std.testing.expectEqual(1, solve(&board_state, .{ .recursive = true }));

        var solution_board: board.Board = try .init(known_board.rules);
        try solution_board.fill_board_from_string(known_board.solution_string);

        try std.testing.expectEqualSlices(?board.NumberType, solution_board.numbers(), board_state.numbers());
    }
}

test "Recursive Count All" {
    var board_state: board.Board = try .init(Regular2x2);

    try std.testing.expectEqual(Regular2x2Solutions, solve(&board_state, .{ .recursive = true, .solution_count_max = 1000 }));
}

test "Recursive Count Some" {
    var board_state: board.Board = try .init(Regular2x2);

    try std.testing.expectEqual(100, solve(&board_state, .{ .recursive = true, .solution_count_max = 100 }));
}
