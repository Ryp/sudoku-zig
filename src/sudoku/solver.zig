const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const GameState = sudoku.GameState;
const cell_at = sudoku.cell_at;
const u32_2 = sudoku.u32_2;

// Soon to be deprecated in zig 0.11 for 0..x style ranges
fn range(len: usize) []const void {
    return @as([*]void, undefined)[0..len];
}

fn first_bit_index(mask_ro: u32) u32 {
    var mask = mask_ro;

    for (range(32)) |_, index| {
        if ((mask & 1) != 0)
            return @intCast(u32, index);
        mask = mask >> 1;
    }

    return 32;
}

pub fn solve_trivial_candidates_at(game: *GameState, cell_coord: u32_2, number_index: u5) void {
    const box_index = sudoku.box_index_from_cell(game, cell_coord);

    const col_start = game.extent * cell_coord[0];
    const row_start = game.extent * cell_coord[1];
    const box_start = game.extent * (box_index[0] + box_index[1] * game.box_h);

    const col_region = game.col_regions[col_start .. col_start + game.extent];
    const row_region = game.row_regions[row_start .. row_start + game.extent];
    const box_region = game.box_regions[box_start .. box_start + game.extent];

    const mask = sudoku.mask_for_number_index(number_index);

    for (range(game.extent)) |_, i| {
        cell_at(game, col_region[i]).hint_mask &= ~mask;
        cell_at(game, row_region[i]).hint_mask &= ~mask;
        cell_at(game, box_region[i]).hint_mask &= ~mask;
    }
}

pub fn solve_trivial_candidates(game: *GameState) void {
    for (range(game.extent)) |_, region_index_usize| {
        const slice_start = region_index_usize * game.extent;
        const slice_end = slice_start + game.extent;

        const col_region = game.col_regions[slice_start..slice_end];
        const row_region = game.row_regions[slice_start..slice_end];
        const box_region = game.box_regions[slice_start..slice_end];

        solve_eliminate_candidate_region(game, col_region);
        solve_eliminate_candidate_region(game, row_region);
        solve_eliminate_candidate_region(game, box_region);
    }
}

fn solve_eliminate_candidate_region(game: *GameState, region: []u32_2) void {
    assert(region.len == game.extent);
    var used_mask: u16 = 0;

    for (region) |cell_coord| {
        const cell = cell_at(game, cell_coord);

        if (cell.set_number != 0) {
            used_mask |= sudoku.mask_for_number_index(cell.set_number - 1);
        }
    }

    for (region) |cell_coord| {
        const cell = cell_at(game, cell_coord);

        if (cell.set_number == 0) {
            cell.hint_mask &= ~used_mask;
        }
    }
}

// If there's a cell with a single possibility left, put it down
pub fn solve_naked_singles(game: *GameState) void {
    for (game.board) |cell, flat_index| {
        const index = sudoku.flat_index_to_2d(game.extent, flat_index);

        if (cell.set_number == 0 and @popCount(cell.hint_mask) == 1) {
            sudoku.place_number_remove_trivial_candidates(game, index, @intCast(u5, first_bit_index(cell.hint_mask)));
        }
    }
}

pub fn solve_hidden_singles(game: *GameState) void {
    for (range(game.extent)) |_, region_index_usize| {
        const slice_start = region_index_usize * game.extent;
        const slice_end = slice_start + game.extent;

        const col_region = game.col_regions[slice_start..slice_end];
        const row_region = game.row_regions[slice_start..slice_end];
        const box_region = game.box_regions[slice_start..slice_end];

        solve_hidden_singles_region(game, col_region);
        solve_hidden_singles_region(game, row_region);
        solve_hidden_singles_region(game, box_region);
    }
}

// If there's a region (col/row/box) where a possibility appears only once, put it down
fn solve_hidden_singles_region(game: *GameState, region: []u32_2) void {
    assert(region.len == game.extent);

    // Use worst case size to allow allocating on the stack
    var counts = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);
    var last_occurences: [sudoku.MaxSudokuExtent]u32_2 = undefined;

    for (region) |cell_coord| {
        const cell = cell_at(game, cell_coord);

        var mask = cell.hint_mask;

        for (range(game.extent)) |_, number_index| {
            if ((mask & 1) != 0) {
                counts[number_index] += 1;
                last_occurences[number_index] = cell_coord;
            }
            mask >>= 1;
        }
    }

    for (counts[0..game.extent]) |count, number_index| {
        if (count == 1) {
            const coords = last_occurences[number_index];
            var cell = sudoku.cell_at(game, coords);

            if (cell.set_number == 0) {
                sudoku.place_number_remove_trivial_candidates(game, coords, @intCast(u5, number_index));
            }
        }
    }
}

pub fn solve_hidden_pairs(game: *GameState) void {
    for (range(game.extent)) |_, region_index_usize| {
        const slice_start = region_index_usize * game.extent;
        const slice_end = slice_start + game.extent;

        const col_region = game.col_regions[slice_start..slice_end];
        const row_region = game.row_regions[slice_start..slice_end];
        const box_region = game.box_regions[slice_start..slice_end];

        solve_hidden_pairs_region(game, col_region);
        solve_hidden_pairs_region(game, row_region);
        solve_hidden_pairs_region(game, box_region);
    }
}

fn solve_hidden_pairs_region(game: *GameState, region: []u32_2) void {
    assert(region.len == game.extent);

    // Use worst case size to allow allocating on the stack
    var counts = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);
    var position_mask = std.mem.zeroes([sudoku.MaxSudokuExtent]u16);

    for (region) |cell_coord, cell_index| {
        const cell = cell_at(game, cell_coord);
        var mask = cell.hint_mask;

        for (range(game.extent)) |_, number_index| {
            if ((mask & 1) != 0) {
                counts[number_index] += 1;
                position_mask[number_index] |= sudoku.mask_for_number_index(@intCast(u32, cell_index));
            }
            mask >>= 1;
        }
    }

    for (range(game.extent - 1)) |_, first_number| {
        if (counts[first_number] != 2)
            continue;

        for (range(game.extent - first_number - 1)) |_, second_index| {
            const second_number = second_index + first_number + 1;
            assert(second_number < game.extent);

            if (counts[second_number] != 2)
                continue;

            if (position_mask[first_number] != position_mask[second_number])
                continue;

            const pair_mask = sudoku.mask_for_number_index(@intCast(u32, first_number)) | sudoku.mask_for_number_index(@intCast(u32, second_number));

            for (region) |cell_coord, i| {
                var cell = cell_at(game, cell_coord);

                if (((position_mask[first_number] >> @intCast(u4, i)) & 1) != 0) {
                    cell.hint_mask = pair_mask;
                } else {
                    cell.hint_mask &= ~pair_mask;
                }
            }
        }
    }
}
