const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const BoardState = sudoku.BoardState;
const UnsetNumber = sudoku.UnsetNumber;

pub fn solve(board: *BoardState, recursive: bool) bool {
    var free_cell_list_full: [sudoku.MaxSudokuExtent * sudoku.MaxSudokuExtent]CellInfo = undefined;
    var free_cell_list = populate_free_list(board, &free_cell_list_full);

    sort_free_cell_list(board, free_cell_list);

    if (recursive) {
        return solve_backtracking_recursive(board, free_cell_list, 0);
    } else {
        return solve_backtracking_iterative(board, free_cell_list);
    }
}

const CellInfo = struct {
    index: u8,
    col: u4,
    row: u4,
};

fn solve_backtracking_recursive(board: *BoardState, free_cell_list: []CellInfo, list_index: u32) bool {
    if (list_index >= free_cell_list.len) {
        return true;
    }

    const free_cell: CellInfo = free_cell_list[list_index];

    // List all possible candidates for this cell
    var valid_candidates_full: [sudoku.MaxSudokuExtent]bool = undefined;
    var valid_candidates = valid_candidates_full[0..board.extent];

    populate_valid_candidates(board, free_cell, valid_candidates);

    // Now let's place a number from the list of candidates and see if it sticks
    var cell_number = &board.numbers[free_cell.index];

    for (valid_candidates, 0..) |is_valid, number| {
        if (is_valid) {
            cell_number.* = @intCast(number);

            if (solve_backtracking_recursive(board, free_cell_list, list_index + 1)) {
                return true;
            }
        }
    }

    cell_number.* = UnsetNumber;
    return false;
}

fn solve_backtracking_iterative(board: *BoardState, free_cell_list: []CellInfo) bool {
    var current_guess_full = std.mem.zeroes([sudoku.MaxSudokuExtent * sudoku.MaxSudokuExtent]u4);
    var current_guess = current_guess_full[0..free_cell_list.len];

    var valid_candidates_full: [sudoku.MaxSudokuExtent]bool = undefined;
    var valid_candidates = valid_candidates_full[0..board.extent];

    var list_index: u32 = 0;

    while (list_index < free_cell_list.len) main: {
        const free_cell = free_cell_list[list_index];

        populate_valid_candidates(board, free_cell, valid_candidates);

        var cell_number = &board.numbers[free_cell.index];
        var start: u32 = current_guess[list_index];

        for (valid_candidates[start..], start..) |is_valid, number| {
            if (is_valid) {
                cell_number.* = @intCast(number);
                current_guess[list_index] = @intCast(number + 1);

                list_index += 1;

                break :main;
            }
        } else {
            cell_number.* = UnsetNumber;
            current_guess[list_index] = 0;

            // Backtracking at index zero means we didn't find a solution
            if (list_index == 0) {
                return false;
            } else {
                list_index -= 1;
            }
        }
    }

    return true;
}

fn populate_valid_candidates(board: *BoardState, cell_info: CellInfo, valid_candidates: []bool) void {
    assert(valid_candidates.len == board.extent);

    const box = board.box_indices[cell_info.index];

    // Clear
    for (valid_candidates) |*candidate| {
        candidate.* = true;
    }

    // Remove possible solutions based on visible regions
    for (board.col_regions[cell_info.col]) |cell_index| {
        const cell_number = board.numbers[cell_index];
        if (cell_number != UnsetNumber) {
            valid_candidates[cell_number] = false;
        }
    }

    for (board.row_regions[cell_info.row]) |cell_index| {
        const cell_number = board.numbers[cell_index];
        if (cell_number != UnsetNumber) {
            valid_candidates[cell_number] = false;
        }
    }

    for (board.box_regions[box]) |cell_index| {
        const cell_number = board.numbers[cell_index];
        if (cell_number != UnsetNumber) {
            valid_candidates[cell_number] = false;
        }
    }
}

fn populate_free_list(board: *BoardState, free_cell_list_full: []CellInfo) []CellInfo {
    var list_index: u8 = 0;

    for (board.numbers, 0..) |cell_number, cell_index| {
        if (cell_number == UnsetNumber) {
            const cell_coord = sudoku.cell_coord_from_index(board.extent, cell_index);

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

fn sort_free_cell_list(board: *BoardState, free_cell_list: []CellInfo) void {
    const full_mask = sudoku.full_candidate_mask(board.extent);

    var col_region_masks_full: [sudoku.MaxSudokuExtent]u16 = undefined;
    var col_region_masks = col_region_masks_full[0..board.extent];

    for (board.col_regions, col_region_masks) |region, *region_mask| {
        region_mask.* = full_mask;

        for (region) |cell_index| {
            const cell_number = board.numbers[cell_index];
            if (cell_number != UnsetNumber) {
                region_mask.* &= ~sudoku.mask_for_number(@intCast(cell_number));
            }
        }
    }

    var row_region_masks_full: [sudoku.MaxSudokuExtent]u16 = undefined;
    var row_region_masks = row_region_masks_full[0..board.extent];

    for (board.row_regions, row_region_masks) |region, *region_mask| {
        region_mask.* = full_mask;

        for (region) |cell_index| {
            const cell_number = board.numbers[cell_index];
            if (cell_number != UnsetNumber) {
                region_mask.* &= ~sudoku.mask_for_number(@intCast(cell_number));
            }
        }
    }

    var box_region_masks_full: [sudoku.MaxSudokuExtent]u16 = undefined;
    var box_region_masks = box_region_masks_full[0..board.extent];

    for (board.box_regions, box_region_masks) |region, *region_mask| {
        region_mask.* = full_mask;

        for (region) |cell_index| {
            const cell_number = board.numbers[cell_index];
            if (cell_number != UnsetNumber) {
                region_mask.* &= ~sudoku.mask_for_number(@intCast(cell_number));
            }
        }
    }

    var candidate_counts_full = std.mem.zeroes([sudoku.MaxSudokuExtent * sudoku.MaxSudokuExtent]u8);
    var candidate_counts = candidate_counts_full[0..board.numbers.len];

    for (candidate_counts, 0..) |*candidate_count, cell_index| {
        const cell_coord = sudoku.cell_coord_from_index(board.extent, cell_index);
        const col = cell_coord[0];
        const row = cell_coord[1];
        const box = board.box_indices[cell_index];

        const mask = col_region_masks[col] & row_region_masks[row] & box_region_masks[box];
        candidate_count.* = @popCount(mask);
    }

    std.sort.pdq(CellInfo, free_cell_list, candidate_counts, cell_info_candidate_count_compare_less);
}

fn cell_info_candidate_count_compare_less(candidate_counts: []u8, lhs: CellInfo, rhs: CellInfo) bool {
    return candidate_counts[lhs.index] < candidate_counts[rhs.index];
}
