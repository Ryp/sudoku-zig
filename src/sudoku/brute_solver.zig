const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const GameState = sudoku.GameState;
const UnsetNumber = sudoku.UnsetNumber;

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
    var free_cell_index: u32 = undefined;

    // Look for a free cell
    for (game.board, 0..) |cell, flat_index| {
        if (cell.number == UnsetNumber) {
            free_cell_index = @intCast(flat_index);
            break;
        }
    } else {
        // If we didn't our job is done!
        return true;
    }

    // List all possible candidates for this cell
    var valid_candidates_full: [sudoku.MaxSudokuExtent]bool = undefined;
    var valid_candidates = valid_candidates_full[0..game.extent];

    populate_valid_candidates(game, free_cell_index, valid_candidates);

    // Now let's place a number from the list of candidates and see if it sticks
    var cell = &game.board[free_cell_index];

    for (valid_candidates, 0..) |is_valid, number| {
        if (!is_valid)
            continue;

        cell.number = @intCast(number);

        if (solve_recursive(game)) {
            return true;
        }
    }

    cell.number = UnsetNumber;
    return false;
}

fn solve_iterative(game: *GameState) bool {
    var free_list_indices_full: [sudoku.MaxSudokuExtent * sudoku.MaxSudokuExtent]u32 = undefined;
    var free_list_indices = populate_free_list(game, &free_list_indices_full);

    var current_guess_full = std.mem.zeroes([sudoku.MaxSudokuExtent * sudoku.MaxSudokuExtent]u4);
    var current_guess = current_guess_full[0..free_list_indices.len];

    var valid_candidates_full: [sudoku.MaxSudokuExtent]bool = undefined;
    var valid_candidates = valid_candidates_full[0..game.extent];

    var list_index: u32 = 0;

    while (list_index < free_list_indices.len) main: {
        const free_cell_index = free_list_indices[list_index];

        populate_valid_candidates(game, free_cell_index, valid_candidates);

        var cell = &game.board[free_cell_index];
        var start: u32 = current_guess[list_index];

        for (valid_candidates[start..], start..) |is_valid, number| {
            if (!is_valid)
                continue;

            cell.number = @intCast(number);
            current_guess[list_index] = @intCast(number + 1);

            list_index += 1;

            break :main;
        } else {
            cell.number = UnsetNumber;
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

fn populate_valid_candidates(game: *GameState, index_flat: u32, valid_candidates: []bool) void {
    const target_cell_coord = sudoku.flat_index_to_2d(game.extent, index_flat);
    const col = target_cell_coord[0];
    const row = target_cell_coord[1];
    const box = game.box_indices[index_flat];

    assert(valid_candidates.len == game.extent);

    // Clear
    for (valid_candidates) |*candidate| {
        candidate.* = true;
    }

    // Remove possible solutions based on visible regions
    for (game.col_regions[col]) |cell_index| {
        const cell = game.board[cell_index];
        if (cell.number != UnsetNumber) {
            valid_candidates[cell.number] = false;
        }
    }

    for (game.row_regions[row]) |cell_index| {
        const cell = game.board[cell_index];
        if (cell.number != UnsetNumber) {
            valid_candidates[cell.number] = false;
        }
    }

    for (game.box_regions[box]) |cell_index| {
        const cell = game.board[cell_index];
        if (cell.number != UnsetNumber) {
            valid_candidates[cell.number] = false;
        }
    }
}

fn populate_free_list(game: *GameState, free_list_indices_full: []u32) []u32 {
    var list_index: u32 = 0;

    for (game.board, 0..) |cell, flat_index| {
        if (cell.number == UnsetNumber) {
            free_list_indices_full[list_index] = @intCast(flat_index);
            list_index += 1;
        }
    }

    return free_list_indices_full[0..list_index];
}
