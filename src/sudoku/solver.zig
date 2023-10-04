const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const event = @import("event.zig");
const GameState = sudoku.GameState;
const UnsetNumber = sudoku.UnsetNumber;
const cell_at = sudoku.cell_at;
const u32_2 = sudoku.u32_2;
const all = sudoku.all;

const AABB_u32_2 = struct {
    min: u32_2,
    max: u32_2,
};

fn first_bit_index_u16(mask_ro: u16) u4 {
    var mask = mask_ro;

    for (0..16) |bit_index| {
        if ((mask & 1) != 0)
            return @intCast(bit_index);
        mask = mask >> 1;
    }

    assert(false);
    return 0;
}

pub fn solve_trivial_candidates_at(game: *GameState, cell_coord: u32_2, number: u4) void {
    const box_index = sudoku.box_index_from_cell(game, cell_coord);

    const col_region = game.col_regions[cell_coord[0]];
    const row_region = game.row_regions[cell_coord[1]];
    const box_region = game.box_regions[box_index];

    const mask = sudoku.mask_for_number(number);

    for (col_region, row_region, box_region) |col_cell, row_cell, box_cell| {
        cell_at(game, col_cell).hint_mask &= ~mask;
        cell_at(game, row_cell).hint_mask &= ~mask;
        cell_at(game, box_cell).hint_mask &= ~mask;
    }
}

pub fn solve_trivial_candidates(game: *GameState) void {
    for (game.all_regions) |region| {
        solve_eliminate_candidate_region(game, region);
    }
}

fn solve_eliminate_candidate_region(game: *GameState, region: []u32_2) void {
    assert(region.len == game.extent);
    var used_mask: u16 = 0;

    for (region) |cell_coord| {
        const cell = cell_at(game, cell_coord);

        if (cell.number != UnsetNumber) {
            used_mask |= sudoku.mask_for_number(@intCast(cell.number));
        }
    }

    for (region) |cell_coord| {
        const cell = cell_at(game, cell_coord);

        if (cell.number == UnsetNumber) {
            cell.hint_mask &= ~used_mask;
        }
    }
}

// If there's a cell with a single possibility left, put it down
pub fn solve_naked_singles(game: *GameState) void {
    for (game.board, 0..) |cell, flat_index| {
        const index = sudoku.flat_index_to_2d(game.extent, flat_index);

        if (cell.number == UnsetNumber and @popCount(cell.hint_mask) == 1) {
            const number = first_bit_index_u16(cell.hint_mask);

            // FIXME event should also add the candidates we removed here
            sudoku.place_number_remove_trivial_candidates(game, index, number);
        }
    }
}

pub fn solve_hidden_singles(game: *GameState) void {
    for (game.all_regions) |region| {
        solve_hidden_singles_region(game, region);
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

        for (0..game.extent) |number| {
            if ((mask & 1) != 0) {
                counts[number] += 1;
                last_occurences[number] = cell_coord;
            }
            mask >>= 1;
        }
    }

    for (counts[0..game.extent], 0..) |count, number_usize| {
        if (count == 1) {
            const number: u4 = @intCast(number_usize);
            const coords = last_occurences[number];
            var cell = sudoku.cell_at(game, coords);

            if (cell.number == UnsetNumber) {
                event.allocate_hidden_single_event(game).* = event.HiddenSingleEvent{
                    .coords = coords,
                    .deletion_mask = cell.hint_mask & ~sudoku.mask_for_number(number),
                    .number = number,
                };

                // FIXME event should also add the candidates we removed here
                sudoku.place_number_remove_trivial_candidates(game, coords, number);
            }
        }
    }
}

pub fn solve_hidden_pairs(game: *GameState) void {
    for (game.all_regions) |region| {
        solve_hidden_pairs_region(game, region);
    }
}

fn solve_hidden_pairs_region(game: *GameState, region: []u32_2) void {
    assert(region.len == game.extent);

    // Use worst case size to allow allocating on the stack
    var counts = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);
    var position_mask = std.mem.zeroes([sudoku.MaxSudokuExtent]u16);

    for (region, 0..) |cell_coord, cell_index| {
        const cell = cell_at(game, cell_coord);
        var mask = cell.hint_mask;

        for (0..game.extent) |number| {
            if ((mask & 1) != 0) {
                counts[number] += 1;
                position_mask[number] |= sudoku.mask_for_number(@intCast(cell_index));
            }
            mask >>= 1;
        }
    }

    for (0..game.extent - 1) |first_number| {
        if (counts[first_number] != 2)
            continue;

        for (0..game.extent - first_number - 1) |second_index| {
            const second_number = second_index + first_number + 1;
            assert(second_number < game.extent);

            if (counts[second_number] != 2)
                continue;

            if (position_mask[first_number] != position_mask[second_number])
                continue;

            const pair_mask = sudoku.mask_for_number(@intCast(first_number)) | sudoku.mask_for_number(@intCast(second_number));

            for (region, 0..) |cell_coord, i| {
                var cell = cell_at(game, cell_coord);

                if (((position_mask[first_number] >> @intCast(i)) & 1) != 0) {
                    cell.hint_mask = pair_mask;
                } else {
                    cell.hint_mask &= ~pair_mask;
                }
            }
        }
    }
}

// If candidates in a box are arranged in a line, remove them from other boxes on that line.
// Also called pointing pairs or triples in 9x9 sudoku.
pub fn solve_pointing_lines(game: *GameState) void {
    for (0..game.extent) |box_index| {
        const box_region = game.box_regions[box_index];

        var box_aabbs: [sudoku.MaxSudokuExtent]AABB_u32_2 = undefined;
        var candidate_counts = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);

        // Compute AABB of candidates for each number
        // FIXME cache remaining candidates per box and only iterate on this?
        for (0..game.extent) |number_usize| {
            const number: u4 = @intCast(number_usize);
            const number_mask = sudoku.mask_for_number(number);

            var aabb = &box_aabbs[number];
            aabb.max = u32_2{ 0, 0 };
            aabb.min = u32_2{ game.extent, game.extent };

            for (box_region) |cell_coord| {
                const cell = cell_at(game, cell_coord);

                if ((cell.hint_mask & number_mask) != 0) {
                    aabb.min = @min(aabb.min, cell_coord);
                    aabb.max = @max(aabb.max, cell_coord);
                    candidate_counts[number] += 1;
                }
            }

            // Test if we have a valid AABB
            // We don't care about single candidates, they should be found with simpler solving method already
            if (candidate_counts[number] >= 2) {
                const aabb_extent = aabb.max - aabb.min;
                assert(!all(aabb_extent == u32_2{ 0, 0 })); // This should be handled by naked singles

                if (aabb_extent[0] == 0) {
                    remove_candidates_from_pointing_colum(game, number, @intCast(box_index), aabb.min[0]);
                } else if (aabb_extent[1] == 0) {
                    remove_candidates_from_pointing_row(game, number, @intCast(box_index), aabb.min[1]);
                }
            }
        }
    }
}

fn remove_candidates_from_pointing_colum(game: *GameState, number: u4, box_flat_index: u32, col_index: u32) void {
    const col_region = game.col_regions[col_index];

    const box_count = u32_2{ game.box_h, game.box_w };
    const box_row_to_exclude = box_flat_index / box_count[0];
    const number_mask = sudoku.mask_for_number(number);

    for (col_region, 0..game.extent) |cell_coord, row_index| {
        const box_row = row_index / box_count[0];

        if (box_row == box_row_to_exclude)
            continue;

        var cell = cell_at(game, cell_coord);
        cell.hint_mask &= ~number_mask;
    }
}

fn remove_candidates_from_pointing_row(game: *GameState, number: u4, box_flat_index: u32, row_index: u32) void {
    const row_region = game.row_regions[row_index];

    const box_count = u32_2{ game.box_h, game.box_w };
    const box_col_to_exclude = box_flat_index % box_count[0];
    const number_mask = sudoku.mask_for_number(number);

    for (row_region, 0..game.extent) |cell_coord, col_index| {
        const box_col = col_index / box_count[1];

        if (box_col == box_col_to_exclude)
            continue;

        var cell = cell_at(game, cell_coord);
        cell.hint_mask &= ~number_mask;
    }
}
