const sudoku = @import("game.zig");
const GameState = sudoku.GameState;
const UnsetNumber = sudoku.UnsetNumber;
const cell_at = sudoku.cell_at;
const u32_2 = sudoku.u32_2;
const all = sudoku.all;

pub fn find_free_cell(game: *GameState) u32_2 {
    for (game.board, 0..) |cell, flat_index| {
        if (cell.number == UnsetNumber) {
            return sudoku.flat_index_to_2d(game.extent, flat_index);
        }
    }

    return .{ game.extent, game.extent };
}

pub fn solve(game: *GameState) bool {
    const free_cell = find_free_cell(game);

    // If there's no free cell here, we're done
    if (all(free_cell == u32_2{ game.extent, game.extent })) {
        return true;
    }

    // List all possible candidates for this cell
    var full_canditates: [sudoku.MaxSudokuExtent]bool = undefined;
    var valid_candidates = full_canditates[0..game.extent];

    for (valid_candidates) |*candidate| {
        candidate.* = true;
    }

    const box_index = sudoku.box_index_from_cell(game, free_cell);

    // Remove possible solutions based on visible regions
    for (game.col_regions[free_cell[0]]) |cell_coord| {
        const cell = cell_at(game, cell_coord);
        if (cell.number != UnsetNumber) {
            valid_candidates[cell.number] = false;
        }
    }

    for (game.row_regions[free_cell[1]]) |cell_coord| {
        const cell = cell_at(game, cell_coord);
        if (cell.number != UnsetNumber) {
            valid_candidates[cell.number] = false;
        }
    }

    for (game.box_regions[box_index]) |cell_coord| {
        const cell = cell_at(game, cell_coord);
        if (cell.number != UnsetNumber) {
            valid_candidates[cell.number] = false;
        }
    }

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
