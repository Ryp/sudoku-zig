const std = @import("std");

const board_generic = @import("board_generic.zig");
const RegionSet = board_generic.RegionSet;

const solver_logical = @import("solver_logical.zig");
const known_boards = @import("known_boards.zig");

pub const Options = struct {
    recursive: bool = false,
};

pub fn solve(extent: comptime_int, board: *board_generic.State(extent), options: Options) bool {
    var free_cell_list_full: [board.ExtentSqr]CellInfo = undefined;
    const free_cell_list = populate_free_list(extent, board, &free_cell_list_full);

    sort_free_cell_list(extent, board, free_cell_list);

    if (options.recursive) {
        return solve_backtracking_recursive(extent, board, free_cell_list, 0);
    } else {
        return solve_backtracking_iterative(extent, board, free_cell_list);
    }
}

const CellInfo = struct {
    index: u8,
    col: u4,
    row: u4,
};

fn solve_backtracking_recursive(extent: comptime_int, board: *board_generic.State(extent), free_cell_list: []CellInfo, list_index: u32) bool {
    if (list_index >= free_cell_list.len) {
        return true;
    }

    const free_cell: CellInfo = free_cell_list[list_index];
    const valid_mask = valid_candidates_mask(extent, board, free_cell);

    for (0..extent) |number| {
        if (board.mask_for_number(@intCast(number)) & valid_mask != 0) {
            board.numbers[free_cell.index] = @intCast(number);

            if (solve_backtracking_recursive(extent, board, free_cell_list, list_index + 1)) {
                return true;
            }
        }
    }

    board.numbers[free_cell.index] = null;
    return false;
}

fn solve_backtracking_iterative(extent: comptime_int, board: *board_generic.State(extent), free_cell_list: []CellInfo) bool {
    var current_guess_full = std.mem.zeroes([board.ExtentSqr]u32);
    var current_guess = current_guess_full[0..free_cell_list.len];

    var list_index: u32 = 0;

    outer_loop: while (list_index < free_cell_list.len) {
        const free_cell = free_cell_list[list_index];
        const valid_mask = valid_candidates_mask(extent, board, free_cell);

        const start: u32 = current_guess[list_index];

        for (start..extent) |number| {
            if (board.mask_for_number(@intCast(number)) & valid_mask != 0) {
                board.numbers[free_cell.index] = @intCast(number); // Guess this number
                current_guess[list_index] = @intCast(number + 1); // If we backtrack, start after this number

                list_index += 1;

                continue :outer_loop;
            }
        } else {
            // Since we skipped the loop we shouldn't have any active guess
            // If we came here from backtracking, this should have been cleared for us
            // std.debug.assert(board.numbers[free_cell.index] == null);

            // Invalidate all previous guesses for this cell
            current_guess[list_index] = 0;

            // Backtracking at index zero means we didn't find a solution
            if (list_index == 0) {
                return false;
            } else {
                // Clear previous guess because it's wrong!
                board.numbers[free_cell_list[list_index - 1].index] = null;
                list_index -= 1;
            }
        }
    }

    return true;
}

fn valid_candidates_mask(extent: comptime_int, board: *const board_generic.State(extent), cell_info: CellInfo) board.MaskType {
    // NOTE: This is slow but needed for non-vanilla sudokus
    if (board.rules.chess_anti_king or board.rules.chess_anti_knight) {
        return solver_logical.trivial_candidate_masks(extent, board)[cell_info.index];
    }

    const box = board.regions.box_indices[cell_info.index];

    var valid_mask = board.full_candidate_mask();

    inline for (.{ board.regions.col(cell_info.col), board.regions.row(cell_info.row), board.regions.box(box) }) |region| {
        for (region) |cell_index| {
            if (board.numbers[cell_index]) |number| {
                valid_mask &= ~board.mask_for_number(number);
            }
        }
    }

    return valid_mask;
}

fn populate_free_list(extent: comptime_int, board: *const board_generic.State(extent), free_cell_list_full: []CellInfo) []CellInfo {
    var list_index: u8 = 0;

    for (board.numbers, 0..) |cell_number, cell_index| {
        if (cell_number == null) {
            const cell_coord = board.cell_coord_from_index(cell_index);

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

fn sort_free_cell_list(extent: comptime_int, board: *const board_generic.State(extent), free_cell_list: []CellInfo) void {
    const full_mask = board.full_candidate_mask();
    var region_type_masks: [3][board.Extent]board.MaskType = undefined;

    inline for (.{ RegionSet.Col, RegionSet.Row, RegionSet.Box }) |set| {
        const set_index = @intFromEnum(set);
        for (board.regions.all[set_index], &region_type_masks[set_index]) |region, *region_mask| {
            region_mask.* = full_mask;

            for (region) |cell_index| {
                if (board.numbers[cell_index]) |number| {
                    region_mask.* &= ~board.mask_for_number(number);
                }
            }
        }
    }

    var candidate_counts: [board.ExtentSqr]u8 = .{0} ** board.ExtentSqr;

    for (&candidate_counts, 0..) |*candidate_count, cell_index| {
        const cell_coord = board.cell_coord_from_index(cell_index);

        const col = cell_coord[0];
        const row = cell_coord[1];
        const box = board.regions.box_indices[cell_index];

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

test "Iterative" {
    inline for (known_boards.TestBacktrackingSolver) |known_board| {
        const extent = comptime known_board.rules.type.extent();

        var board = board_generic.State(extent).init(known_board.rules);
        board.fill_board_from_string(known_board.start_string);

        try std.testing.expect(solve(extent, &board, .{ .recursive = false }));

        var solution_board = board_generic.State(extent).init(known_board.rules);
        solution_board.fill_board_from_string(known_board.solution_string);

        try std.testing.expectEqual(solution_board.numbers, board.numbers);
    }
}

test "Recursive" {
    inline for (known_boards.TestBacktrackingSolver) |known_board| {
        const extent = comptime known_board.rules.type.extent();

        var board = board_generic.State(extent).init(known_board.rules);
        board.fill_board_from_string(known_board.start_string);

        try std.testing.expect(solve(extent, &board, .{ .recursive = true }));

        var solution_board = board_generic.State(extent).init(known_board.rules);
        solution_board.fill_board_from_string(known_board.solution_string);

        try std.testing.expectEqual(solution_board.numbers, board.numbers);
    }
}
