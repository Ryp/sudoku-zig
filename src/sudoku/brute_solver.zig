const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const GameState = sudoku.GameState;
const UnsetNumber = sudoku.UnsetNumber;
const cell_at = sudoku.cell_at;
const u32_2 = sudoku.u32_2;
const all = sudoku.all;

pub fn solve(game: *GameState) bool {
    return solve_iterative(game);
}

fn find_free_cell(game: *GameState) u32_2 {
    for (game.board, 0..) |cell, flat_index| {
        if (cell.number == UnsetNumber) {
            return sudoku.flat_index_to_2d(game.extent, flat_index);
        }
    }

    return .{ game.extent, game.extent };
}

fn solve_recursive(game: *GameState) bool {
    const free_cell = find_free_cell(game);

    // If there's no free cell here, we're done
    if (all(free_cell == u32_2{ game.extent, game.extent })) {
        return true;
    }

    // List all possible candidates for this cell
    var valid_candidates_full: [sudoku.MaxSudokuExtent]bool = undefined;
    var valid_candidates = valid_candidates_full[0..game.extent];

    populate_valid_candidates_1(game, free_cell, valid_candidates);

    // Now let's place a number from the list of candidates and see if it sticks
    var cell = cell_at(game, free_cell);

    for (valid_candidates, 0..) |is_valid, number| {
        if (!is_valid)
            continue;

        cell.number = @intCast(number);

        if (solve(game)) {
            return true;
        }
    }

    cell.number = UnsetNumber;
    return false;
}

fn populate_valid_candidates_1(game: *GameState, cell_coord: u32_2, valid_candidates: []bool) void {
    const col = cell_coord[0];
    const row = cell_coord[1];
    const box = sudoku.box_index_from_cell(game, cell_coord);

    populate_valid_candidates(game, col, row, box, valid_candidates);
}

fn populate_valid_candidates_2(game: *GameState, index_flat: u32, valid_candidates: []bool) void {
    const cell_coord = sudoku.flat_index_to_2d(game.extent, index_flat);
    const col = cell_coord[0];
    const row = cell_coord[1];
    const box = game.box_indices[index_flat];

    populate_valid_candidates(game, col, row, box, valid_candidates);
}

fn populate_valid_candidates(game: *GameState, col: u32, row: u32, box: u32, valid_candidates: []bool) void {
    assert(valid_candidates.len == game.extent);

    // Clear
    for (valid_candidates) |*candidate| {
        candidate.* = true;
    }

    // Remove possible solutions based on visible regions
    for (game.col_regions[col]) |cell_coord| {
        const cell = cell_at(game, cell_coord);
        if (cell.number != UnsetNumber) {
            valid_candidates[cell.number] = false;
        }
    }

    for (game.row_regions[row]) |cell_coord| {
        const cell = cell_at(game, cell_coord);
        if (cell.number != UnsetNumber) {
            valid_candidates[cell.number] = false;
        }
    }

    for (game.box_regions[box]) |cell_coord| {
        const cell = cell_at(game, cell_coord);
        if (cell.number != UnsetNumber) {
            valid_candidates[cell.number] = false;
        }
    }
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
        const free_cell_flat_index = free_list_indices[list_index];

        populate_valid_candidates_2(game, free_cell_flat_index, valid_candidates);

        var cell = &game.board[free_cell_flat_index];
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
