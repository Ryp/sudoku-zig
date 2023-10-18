const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const GameState = sudoku.GameState;
const UnsetNumber = sudoku.UnsetNumber;

const CellInfo = struct {
    index: u8,
    col: u4,
    row: u4,
};

const Options = struct {
    recursive: bool = false,
};

pub fn solve(game: *GameState, options: Options) bool {
    if (options.recursive) {
        return solve_recursive(game);
    } else {
        return solve_iterative(game);
    }
}

fn solve_recursive(game: *GameState) bool {
    var free_cell: CellInfo = undefined;

    // Look for a free cell
    for (game.board, 0..) |cell_number, cell_index| {
        if (cell_number == UnsetNumber) {
            const cell_coord = sudoku.cell_coord_from_index(game.extent, cell_index);

            free_cell = CellInfo{
                .index = @intCast(cell_index),
                .col = @intCast(cell_coord[0]),
                .row = @intCast(cell_coord[1]),
            };
            break;
        }
    } else {
        // If we didn't our job is done!
        return true;
    }

    // List all possible candidates for this cell
    var valid_candidates_full: [sudoku.MaxSudokuExtent]bool = undefined;
    var valid_candidates = valid_candidates_full[0..game.extent];

    populate_valid_candidates(game, free_cell, valid_candidates);

    // Now let's place a number from the list of candidates and see if it sticks
    var cell_number = &game.board[free_cell.index];

    for (valid_candidates, 0..) |is_valid, number| {
        if (is_valid) {
            cell_number.* = @intCast(number);

            if (solve_recursive(game)) {
                return true;
            }
        }
    }

    cell_number.* = UnsetNumber;
    return false;
}

fn solve_iterative(game: *GameState) bool {
    var free_list_indices_full: [sudoku.MaxSudokuExtent * sudoku.MaxSudokuExtent]CellInfo = undefined;
    var free_list_indices = populate_free_list(game, &free_list_indices_full);

    var current_guess_full = std.mem.zeroes([sudoku.MaxSudokuExtent * sudoku.MaxSudokuExtent]u4);
    var current_guess = current_guess_full[0..free_list_indices.len];

    var valid_candidates_full: [sudoku.MaxSudokuExtent]bool = undefined;
    var valid_candidates = valid_candidates_full[0..game.extent];

    var list_index: u32 = 0;

    while (list_index < free_list_indices.len) main: {
        const free_cell = free_list_indices[list_index];

        populate_valid_candidates(game, free_cell, valid_candidates);

        var cell_number = &game.board[free_cell.index];
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

fn populate_valid_candidates(game: *GameState, cell_info: CellInfo, valid_candidates: []bool) void {
    assert(valid_candidates.len == game.extent);

    const box = game.box_indices[cell_info.index];

    // Clear
    for (valid_candidates) |*candidate| {
        candidate.* = true;
    }

    // Remove possible solutions based on visible regions
    for (game.col_regions[cell_info.col]) |cell_index| {
        const cell_number = game.board[cell_index];
        if (cell_number != UnsetNumber) {
            valid_candidates[cell_number] = false;
        }
    }

    for (game.row_regions[cell_info.row]) |cell_index| {
        const cell_number = game.board[cell_index];
        if (cell_number != UnsetNumber) {
            valid_candidates[cell_number] = false;
        }
    }

    for (game.box_regions[box]) |cell_index| {
        const cell_number = game.board[cell_index];
        if (cell_number != UnsetNumber) {
            valid_candidates[cell_number] = false;
        }
    }
}

fn populate_free_list(game: *GameState, free_list_indices_full: []CellInfo) []CellInfo {
    var list_index: u8 = 0;

    for (game.board, 0..) |cell_number, cell_index| {
        if (cell_number == UnsetNumber) {
            const cell_coord = sudoku.cell_coord_from_index(game.extent, cell_index);

            free_list_indices_full[list_index] = CellInfo{
                .index = @intCast(cell_index),
                .col = @intCast(cell_coord[0]),
                .row = @intCast(cell_coord[1]),
            };
            list_index += 1;
        }
    }

    return free_list_indices_full[0..list_index];
}
