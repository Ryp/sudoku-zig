const std = @import("std");
const assert = std.debug.assert;

const board_state = @import("board_legacy.zig");
const BoardState = board_state.BoardState;
const MaxSudokuExtent = board_state.MaxSudokuExtent;
const known_boards = @import("known_boards.zig");

pub fn solve(board: *BoardState, recursive: bool) bool {
    var free_cell_list_full: [MaxSudokuExtent * MaxSudokuExtent]CellInfo = undefined;
    const free_cell_list = populate_free_list(board, &free_cell_list_full);

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
    var valid_candidates_full: [MaxSudokuExtent]bool = undefined;
    const valid_candidates = valid_candidates_full[0..board.extent];

    populate_valid_candidates(board, free_cell, valid_candidates);

    // Now let's place a number from the list of candidates and see if it sticks
    const cell_number = &board.numbers[free_cell.index];

    for (valid_candidates, 0..) |is_valid, number| {
        if (is_valid) {
            cell_number.* = @intCast(number);

            if (solve_backtracking_recursive(board, free_cell_list, list_index + 1)) {
                return true;
            }
        }
    }

    cell_number.* = null;
    return false;
}

fn solve_backtracking_iterative(board: *BoardState, free_cell_list: []CellInfo) bool {
    var current_guess_full = std.mem.zeroes([MaxSudokuExtent * MaxSudokuExtent]u4);
    var current_guess = current_guess_full[0..free_cell_list.len];

    var valid_candidates_full: [MaxSudokuExtent]bool = undefined;
    var valid_candidates = valid_candidates_full[0..board.extent];

    var list_index: u32 = 0;

    while (list_index < free_cell_list.len) main: {
        const free_cell = free_cell_list[list_index];

        populate_valid_candidates(board, free_cell, valid_candidates);

        const cell_number = &board.numbers[free_cell.index];
        const start: u32 = current_guess[list_index];

        for (valid_candidates[start..], start..) |is_valid, number| {
            if (is_valid) {
                cell_number.* = @intCast(number);
                current_guess[list_index] = @intCast(number + 1);

                list_index += 1;

                break :main;
            }
        } else {
            cell_number.* = null;
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

    inline for (.{ board.col_regions[cell_info.col], board.row_regions[cell_info.row], board.box_regions[box] }) |region| {
        for (region) |cell_index| {
            if (board.numbers[cell_index]) |number| {
                valid_candidates[number] = false;
            }
        }
    }
}

fn populate_free_list(board: *BoardState, free_cell_list_full: []CellInfo) []CellInfo {
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

fn sort_free_cell_list(board: *BoardState, free_cell_list: []CellInfo) void {
    const full_mask = board.full_candidate_mask();

    // 3 for the three region types: cols, rows, boxes
    var region_type_masks_full: [3][MaxSudokuExtent]u16 = undefined;

    // Region type order must match the use below
    inline for (.{ board.col_regions, board.row_regions, board.box_regions }, 0..) |region_set, region_set_index| {
        const region_masks = region_type_masks_full[region_set_index][0..board.extent];

        for (region_set, region_masks) |region, *region_mask| {
            region_mask.* = full_mask;

            for (region) |cell_index| {
                if (board.numbers[cell_index]) |number| {
                    region_mask.* &= ~board.mask_for_number(number);
                }
            }
        }
    }

    var candidate_counts_full = std.mem.zeroes([MaxSudokuExtent * MaxSudokuExtent]u8);
    const candidate_counts = candidate_counts_full[0..board.numbers.len];

    for (candidate_counts, 0..) |*candidate_count, cell_index| {
        const cell_coord = board.cell_coord_from_index(cell_index);

        const col = cell_coord[0];
        const row = cell_coord[1];
        const box = board.box_indices[cell_index];

        const mask = region_type_masks_full[0][col] & region_type_masks_full[1][row] & region_type_masks_full[2][box];
        candidate_count.* = @popCount(mask);
    }

    std.sort.pdq(CellInfo, free_cell_list, candidate_counts, cell_info_candidate_count_compare_less);
}

fn cell_info_candidate_count_compare_less(candidate_counts: []u8, lhs: CellInfo, rhs: CellInfo) bool {
    return candidate_counts[lhs.index] < candidate_counts[rhs.index];
}

test "Basic iterative" {
    const allocator = std.testing.allocator;

    // Create game board
    var solver_board = try BoardState.create(allocator,.{ .regular = .{
        .box_extent = .{ 3, 3 },
    } });
    defer solver_board.destroy(allocator);

    const known_board = known_boards.easy_000;

    solver_board.fill_board_from_string(known_board.board);

    const solved = solve(&solver_board, false);
    try std.testing.expect(solved);

    var solution_board = try BoardState.create(allocator, solver_board.game_type);
    defer solution_board.destroy(allocator);

    solution_board.fill_board_from_string(known_board.solution);

    try std.testing.expect(std.mem.eql(?u4, solver_board.numbers, solution_board.numbers));
}
