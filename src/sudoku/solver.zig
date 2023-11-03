const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const event = @import("event.zig");
const BoardState = sudoku.BoardState;
const UnsetNumber = sudoku.UnsetNumber;
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

pub fn solve_trivial_candidates_at(board: *BoardState, candidate_masks: []u16, cell_index: u32, number: u4) void {
    const cell_coord = sudoku.cell_coord_from_index(board.extent, cell_index);
    const box_index = board.box_indices[cell_index];

    const col_region = board.col_regions[cell_coord[0]];
    const row_region = board.row_regions[cell_coord[1]];
    const box_region = board.box_regions[box_index];

    const mask = sudoku.mask_for_number(number);

    for (col_region, row_region, box_region) |col_cell, row_cell, box_cell| {
        candidate_masks[col_cell] &= ~mask;
        candidate_masks[row_cell] &= ~mask;
        candidate_masks[box_cell] &= ~mask;
    }
}

pub fn solve_trivial_candidates(board: *BoardState, candidate_masks: []u16) void {
    for (board.all_regions) |region| {
        solve_eliminate_candidate_region(board, candidate_masks, region);
    }
}

fn solve_eliminate_candidate_region(board: *BoardState, candidate_masks: []u16, region: []u32) void {
    assert(region.len == board.extent);
    var used_mask: u16 = 0;

    for (region) |cell_index| {
        const cell_number = board.numbers[cell_index];

        if (cell_number != UnsetNumber) {
            used_mask |= sudoku.mask_for_number(@intCast(cell_number));
        }
    }

    for (region) |cell_index| {
        const cell_number = board.numbers[cell_index];

        if (cell_number == UnsetNumber) {
            candidate_masks[cell_index] &= ~used_mask;
        }
    }
}

// If there's a cell with a single possibility left, put it down
pub fn solve_naked_singles(board: *BoardState, candidate_masks: []u16) void {
    for (board.numbers, candidate_masks, 0..) |cell_number, candidate_mask, cell_index| {
        if (cell_number == UnsetNumber and @popCount(candidate_mask) == 1) {
            const number = first_bit_index_u16(candidate_mask);

            // FIXME event should also add the candidates we removed here
            sudoku.place_number_remove_trivial_candidates(board, candidate_masks, @intCast(cell_index), number);
        }
    }
}

pub fn solve_hidden_singles(board: *BoardState, candidate_masks: []u16) void {
    for (board.all_regions) |region| {
        solve_hidden_singles_region(board, candidate_masks, region);
    }
}

pub fn solve_hidden_pairs(board: *BoardState, candidate_masks: []u16) void {
    for (board.all_regions) |region| {
        solve_hidden_pairs_region(board, candidate_masks, region);
    }
}

// If there's a region (col/row/box) where a possibility appears only once, put it down
fn solve_hidden_singles_region(board: *BoardState, candidate_masks: []u16, region: []u32) void {
    assert(region.len == board.extent);

    var counts_full = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);
    var counts = counts_full[0..board.extent];

    var last_cell_indices_full: [sudoku.MaxSudokuExtent]u32 = undefined;
    var last_cell_indices = last_cell_indices_full[0..board.extent];

    for (region) |cell_index| {
        var mask = candidate_masks[cell_index];

        for (counts, last_cell_indices) |*count, *last_cell_index| {
            if ((mask & 1) != 0) {
                count.* += 1;
                last_cell_index.* = cell_index;
            }
            mask >>= 1;
        }
    }

    for (counts, 0..) |count, number_usize| {
        if (count == 1) {
            const number: u4 = @intCast(number_usize);
            const cell_index = last_cell_indices[number];
            const cell_number = board.numbers[cell_index];
            //const cell_candidate_mask = candidate_masks[cell_index];

            if (cell_number == UnsetNumber) {
                // FIXME
                //event.allocate_hidden_single_event(board).* = event.HiddenSingleEvent{
                //    .cell_index = cell_index,
                //    .deletion_mask = cell_candidate_mask & ~sudoku.mask_for_number(number),
                //    .number = number,
                //};

                // FIXME event should also add the candidates we removed here
                sudoku.place_number_remove_trivial_candidates(board, candidate_masks, cell_index, number);
            }
        }
    }
}

fn solve_hidden_pairs_region(board: *BoardState, candidate_masks: []u16, region: []u32) void {
    assert(region.len == board.extent);

    var counts_full = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);
    var counts = counts_full[0..board.extent];

    var position_masks_full = std.mem.zeroes([sudoku.MaxSudokuExtent]u16);
    var position_masks = position_masks_full[0..board.extent];

    for (region, 0..) |cell_index, region_cell_index| {
        var mask = candidate_masks[cell_index];

        for (counts, position_masks) |*count, *position_mask| {
            if ((mask & 1) != 0) {
                count.* += 1;
                position_mask.* |= sudoku.mask_for_number(@intCast(region_cell_index));
            }
            mask >>= 1;
        }
    }

    for (counts[0 .. board.extent - 1], 0..) |first_number_count, first_number| {
        if (first_number_count == 2) {
            const second_number_start = first_number + 1;

            for (counts[second_number_start..], second_number_start..) |second_number_count, second_number| {
                assert(second_number < board.extent);

                if (second_number_count == 2 and position_masks[first_number] == position_masks[second_number]) {
                    const pair_mask = sudoku.mask_for_number(@intCast(first_number)) | sudoku.mask_for_number(@intCast(second_number));

                    for (region, 0..) |cell_index, region_cell_index| {
                        if (((position_masks[first_number] >> @intCast(region_cell_index)) & 1) != 0) {
                            candidate_masks[cell_index] = pair_mask;
                        }
                    }
                }
            }
        }
    }
}

// If candidates in a box are arranged in a line, remove them from other boxes on that line.
// Also called pointing pairs or triples in 9x9 sudoku.
pub fn solve_pointing_lines(board: *BoardState, candidate_masks: []u16) void {
    for (0..board.extent) |box_index| {
        const box_region = board.box_regions[box_index];

        var box_aabbs_full: [sudoku.MaxSudokuExtent]AABB_u32_2 = undefined;
        var box_aabbs = box_aabbs_full[0..board.extent];

        var candidate_counts_full = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);
        var candidate_counts = candidate_counts_full[0..board.extent];

        // Compute AABB of candidates for each number
        // FIXME cache remaining candidates per box and only iterate on this?
        for (box_aabbs, candidate_counts, 0..) |*aabb, *candidate_count, number_usize| {
            const number: u4 = @intCast(number_usize);
            const number_mask = sudoku.mask_for_number(number);

            aabb.max = u32_2{ 0, 0 };
            aabb.min = u32_2{ board.extent, board.extent };

            for (box_region) |cell_index| {
                const cell_candidate_mask = candidate_masks[cell_index];
                const cell_coord = sudoku.cell_coord_from_index(board.extent, cell_index);

                if ((cell_candidate_mask & number_mask) != 0) {
                    aabb.min = @min(aabb.min, cell_coord);
                    aabb.max = @max(aabb.max, cell_coord);
                    candidate_count.* += 1;
                }
            }

            // Test if we have a valid AABB
            // We don't care about single candidates, they should be found with simpler solving method already
            if (candidate_count.* >= 2) {
                const aabb_extent = aabb.max - aabb.min;
                assert(!all(aabb_extent == u32_2{ 0, 0 })); // This should be handled by naked singles

                if (aabb_extent[0] == 0) {
                    const col_region = board.col_regions[aabb.min[0]];
                    remove_candidates_from_pointing_line(board, candidate_masks, number, @intCast(box_index), col_region);
                } else if (aabb_extent[1] == 0) {
                    const row_region = board.row_regions[aabb.min[1]];
                    remove_candidates_from_pointing_line(board, candidate_masks, number, @intCast(box_index), row_region);
                }
            }
        }
    }
}

fn remove_candidates_from_pointing_line(board: *BoardState, candidate_masks: []u16, number: u4, box_index_to_exclude: u32, line_region: []u32) void {
    const number_mask = sudoku.mask_for_number(number);

    for (line_region) |cell_index| {
        const box_index = board.box_indices[cell_index];

        if (box_index != box_index_to_exclude) {
            candidate_masks[cell_index] &= ~number_mask;
        }
    }
}
