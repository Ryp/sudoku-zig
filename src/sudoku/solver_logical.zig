const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const BoardState = sudoku.BoardState;
const UnsetNumber = sudoku.UnsetNumber;
const u32_2 = sudoku.u32_2;
const all = sudoku.all;

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

pub fn place_number_remove_trivial_candidates(board: *BoardState, candidate_masks: []u16, cell_index: u32, number: u4) void {
    board.numbers[cell_index] = number;
    candidate_masks[cell_index] = 0;

    remove_trivial_candidates_at(board, candidate_masks, cell_index, number);
}

pub fn remove_trivial_candidates_at(board: *BoardState, candidate_masks: []u16, cell_index: u32, number: u4) void {
    const cell_coord = board.cell_coord_from_index(cell_index);
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

// Removes trivial candidates from basic sudoku rules
pub fn solve_trivial_candidates(board: *BoardState, candidate_masks: []u16) void {
    for (board.all_regions) |region| {
        solve_trivial_candidates_region(board, candidate_masks, region);
    }
}

// FIXME could use fill_candidate_mask_regions() as a base
fn solve_trivial_candidates_region(board: *BoardState, candidate_masks: []u16, region: []u32) void {
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

pub const NakedSingle = struct {
    cell_index: u32,
    number: u4,
};

pub fn apply_naked_single(board: *BoardState, candidate_masks: []u16, naked_single: NakedSingle) void {
    place_number_remove_trivial_candidates(board, candidate_masks, naked_single.cell_index, naked_single.number);
}

// If there's a cell with a single possibility left, put it down
pub fn find_naked_single(board: BoardState, candidate_masks: []const u16) ?NakedSingle {
    for (board.numbers, candidate_masks, 0..) |cell_number, candidate_mask, cell_index| {
        if (cell_number == UnsetNumber and @popCount(candidate_mask) == 1) {
            const number = first_bit_index_u16(candidate_mask);

            return NakedSingle{
                .cell_index = @intCast(cell_index),
                .number = number,
            };
        }
    }

    return null;
}

pub const NakedPair = struct {
    number_a: u4,
    number_b: u4,
    deletion_mask_a: u16,
    deletion_mask_b: u16,
    cell_index_u: u32,
    cell_index_v: u32,
    region: []u32,
};

pub fn apply_naked_pair(candidate_masks: []u16, naked_pair: NakedPair) void {
    for (naked_pair.region, 0..) |cell_index, region_cell_index| {
        candidate_masks[cell_index] &= ~(((naked_pair.deletion_mask_a >> @as(u4, @intCast(region_cell_index))) & 0b1) << naked_pair.number_a);
        candidate_masks[cell_index] &= ~(((naked_pair.deletion_mask_b >> @as(u4, @intCast(region_cell_index))) & 0b1) << naked_pair.number_b);
    }
}

pub fn find_naked_pair(board: BoardState, candidate_masks: []const u16) ?NakedPair {
    for (board.all_regions) |region| {
        if (find_naked_pair_region(candidate_masks, region)) |naked_pair| {
            return naked_pair;
        }
    }

    return null;
}

// This function works once per region, meaning that if candidates to remove are found in overlapping regions,
// like in a line as well as in a box, then we're only counting one of them.
pub fn find_naked_pair_region(candidate_masks: []const u16, region: []u32) ?NakedPair {
    for (region, 0..) |cell_index_a, region_cell_index_a| {
        const candidate_mask_a = candidate_masks[cell_index_a];
        const candidate_count_a = @popCount(candidate_mask_a);

        if (candidate_count_a == 2) {
            for (region[region_cell_index_a + 1 ..]) |cell_index_b| {
                const candidate_mask_b = candidate_masks[cell_index_b];

                if (candidate_mask_a == candidate_mask_b) {
                    const number_a = first_bit_index_u16(candidate_mask_a);
                    const number_b = first_bit_index_u16(candidate_mask_a - sudoku.mask_for_number(@intCast(number_a)));

                    // Regional mask
                    var deletion_mask_a: u16 = 0;
                    var deletion_mask_b: u16 = 0;

                    for (region, 0..) |cell_index, region_cell_index| {
                        // Avoid checking the pair itself
                        if (cell_index == cell_index_a or cell_index == cell_index_b) {
                            continue;
                        }

                        deletion_mask_a |= ((candidate_masks[cell_index] >> number_a) & 0b1) << @as(u4, @intCast(region_cell_index));
                        deletion_mask_b |= ((candidate_masks[cell_index] >> number_b) & 0b1) << @as(u4, @intCast(region_cell_index));
                    }

                    if (deletion_mask_a != 0 or deletion_mask_b != 0) {
                        return NakedPair{
                            .number_a = number_a,
                            .number_b = number_b,
                            .deletion_mask_a = deletion_mask_a,
                            .deletion_mask_b = deletion_mask_b,
                            .cell_index_u = cell_index_a,
                            .cell_index_v = cell_index_b,
                            .region = region,
                        };
                    }
                }
            }
        }
    }

    return null;
}

test "Naked pair" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Create game board
    const board = try sudoku.BoardState.create(allocator, .{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } });
    defer board.destroy(allocator);

    // Start with an empty board
    sudoku.fill_empty_board(board.numbers);

    const candidate_masks = try allocator.alloc(u16, board.numbers.len);
    defer allocator.free(candidate_masks);

    // Fill candidate masks fully
    for (candidate_masks) |*cell_candidate_mask| {
        cell_candidate_mask.* = 0;
    }

    // Make sure that there's no hit for the initial board
    try std.testing.expect(find_naked_pair(board, candidate_masks) == null);

    const number_a: u4 = 0;
    const number_b: u4 = 8;
    const pair_mask = sudoku.mask_for_number(number_a) | sudoku.mask_for_number(number_b);

    // Setup a naked pair
    candidate_masks[0] = pair_mask;
    candidate_masks[1] = pair_mask;

    // There shouldn't be any hit if there's no candidates to remove
    try std.testing.expect(find_naked_pair(board, candidate_masks) == null);

    candidate_masks[2] = sudoku.mask_for_number(number_a);
    candidate_masks[3] = sudoku.mask_for_number(number_b);

    // Make sure we get a hit
    if (find_naked_pair(board, candidate_masks)) |naked_pair| {
        try std.testing.expectEqual(number_a, naked_pair.number_a);
        try std.testing.expectEqual(number_b, naked_pair.number_b);
        try std.testing.expectEqual(0b0100, naked_pair.deletion_mask_a);
        try std.testing.expectEqual(0b1000, naked_pair.deletion_mask_b);

        // Apply the solver event
        apply_naked_pair(candidate_masks, naked_pair);

        // Make sure we don't hit again after applying the solver event
        try std.testing.expect(find_naked_pair(board, candidate_masks) == null);
    } else {
        try std.testing.expect(false);
    }
}

pub const HiddenSingle = struct {
    number: u4,
    cell_index: u32,
    deletion_mask: u16, // Mask of candidates that can be removed
    region: []u32,
};

pub fn apply_hidden_single(board: *BoardState, candidate_masks: []u16, hidden_single: HiddenSingle) void {
    place_number_remove_trivial_candidates(board, candidate_masks, hidden_single.cell_index, hidden_single.number);
}

pub fn find_hidden_single(board: BoardState, candidate_masks: []const u16) ?HiddenSingle {
    for (board.all_regions) |region| {
        if (find_hidden_single_region(board, candidate_masks, region)) |solver_event| {
            return solver_event;
        }
    }

    return null;
}

pub const HiddenPair = struct {
    a: HiddenSingle,
    b: HiddenSingle,
};

pub fn apply_hidden_pair(candidate_masks: []u16, hidden_pair: HiddenPair) void {
    candidate_masks[hidden_pair.a.cell_index] &= ~hidden_pair.a.deletion_mask;
    candidate_masks[hidden_pair.b.cell_index] &= ~hidden_pair.b.deletion_mask;
}

pub fn find_hidden_pair(board: BoardState, candidate_masks: []const u16) ?HiddenPair {
    for (board.all_regions) |region| {
        if (find_hidden_pair_region(board, candidate_masks, region)) |hidden_pair| {
            return hidden_pair;
        }
    }

    return null;
}

// If there's a region (col/row/box) where a possibility appears only once, put it down
fn find_hidden_single_region(board: BoardState, candidate_masks: []const u16, region: []u32) ?HiddenSingle {
    assert(region.len == board.extent);

    var counts_full = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);
    const counts = counts_full[0..board.extent];

    var last_cell_indices_full: [sudoku.MaxSudokuExtent]u32 = undefined;
    const last_cell_indices = last_cell_indices_full[0..board.extent];

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
            const deletion_mask = candidate_masks[cell_index] & ~sudoku.mask_for_number(number);

            if (cell_number == UnsetNumber and deletion_mask != 0) {
                return HiddenSingle{
                    .number = number,
                    .cell_index = cell_index,
                    .deletion_mask = deletion_mask,
                    .region = region,
                };
            }
        }
    }

    return null;
}

fn find_hidden_pair_region(board: BoardState, candidate_masks: []const u16, region: []u32) ?HiddenPair {
    assert(region.len == board.extent);

    var counts_full = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);
    var counts = counts_full[0..board.extent];

    // Contains first and last position
    const min_max_initial_value = u32_2{ board.extent, 0 };
    var region_min_max_cell_indices_full = [_]u32_2{min_max_initial_value} ** sudoku.MaxSudokuExtent;
    const region_min_max_cell_indices = region_min_max_cell_indices_full[0..board.extent];

    for (region, 0..) |cell_index, region_cell_index| {
        var mask = candidate_masks[cell_index];

        for (counts, region_min_max_cell_indices) |*count, *region_min_max_cell_index| {
            if ((mask & 1) != 0) {
                count.* += 1;
                region_min_max_cell_index.* = u32_2{
                    @min(region_min_max_cell_index[0], @as(u32, @intCast(region_cell_index))),
                    @max(region_min_max_cell_index[1], @as(u32, @intCast(region_cell_index))),
                };
            }
            mask >>= 1;
        }
    }

    for (counts[0 .. board.extent - 1], 0..) |first_number_count, first_number| {
        if (first_number_count == 2) {
            const second_number_start = first_number + 1;

            for (counts[second_number_start..], second_number_start..) |second_number_count, second_number| {
                assert(second_number < board.extent);

                if (second_number_count == 2 and all(region_min_max_cell_indices[first_number] == region_min_max_cell_indices[second_number])) {
                    const mask = sudoku.mask_for_number(@intCast(first_number)) | sudoku.mask_for_number(@intCast(second_number));
                    const region_cell_index_a = region_min_max_cell_indices[first_number][0];
                    const region_cell_index_b = region_min_max_cell_indices[first_number][1];
                    const cell_index_a = region[region_cell_index_a];
                    const cell_index_b = region[region_cell_index_b];
                    const deletion_mask_a = candidate_masks[cell_index_a] & ~mask;
                    const deletion_mask_b = candidate_masks[cell_index_b] & ~mask;

                    // FIXME assert(cell_number == UnsetNumber);
                    if (deletion_mask_a != 0 or deletion_mask_b != 0) {
                        return HiddenPair{
                            .a = HiddenSingle{
                                .number = @intCast(first_number),
                                .cell_index = cell_index_a,
                                .deletion_mask = deletion_mask_a,
                                .region = region,
                            },
                            .b = HiddenSingle{
                                .number = @intCast(second_number),
                                .cell_index = cell_index_b,
                                .deletion_mask = deletion_mask_b,
                                .region = region,
                            },
                        };
                    }
                }
            }
        }
    }

    return null;
}

pub const PointingLine = struct {
    number: u4,
    line_region: []u32,
    line_region_deletion_mask: u16,
    box_region: []u32,
    box_region_mask: u16,
};

pub fn apply_pointing_line(candidate_masks: []u16, pointing_line: PointingLine) void {
    const number_mask = sudoku.mask_for_number(pointing_line.number);
    for (pointing_line.line_region, 0..) |cell_index, region_cell_index| {
        // FIXME super confusing
        if (sudoku.mask_for_number(@intCast(region_cell_index)) & pointing_line.line_region_deletion_mask != 0) {
            candidate_masks[cell_index] &= ~number_mask;
        }
    }
}

// If candidates in a box are arranged in a line, remove them from other boxes on that line.
// Also called pointing pairs or triples in 9x9 sudoku.
pub fn find_pointing_line(board: BoardState, candidate_masks: []const u16) ?PointingLine {
    const AABB_u32 = struct {
        min: u32_2,
        max: u32_2,
    };

    for (0..board.extent) |box_index| {
        const box_region = board.box_regions[box_index];

        var box_aabbs_full: [sudoku.MaxSudokuExtent]AABB_u32 = undefined;
        const box_aabbs = box_aabbs_full[0..board.extent];

        var candidate_counts_full = std.mem.zeroes([sudoku.MaxSudokuExtent]u32);
        const candidate_counts = candidate_counts_full[0..board.extent];

        // Compute AABB of candidates for each number
        // FIXME cache remaining candidates per box and only iterate on this?
        for (box_aabbs, candidate_counts, 0..) |*aabb, *candidate_count, number_usize| {
            const number: u4 = @intCast(number_usize);
            const number_mask = sudoku.mask_for_number(number);

            aabb.max = u32_2{ 0, 0 };
            aabb.min = u32_2{ board.extent, board.extent };

            var box_region_mask: u16 = 0;

            for (box_region, 0..) |cell_index, region_cell_index| {
                const cell_candidate_mask = candidate_masks[cell_index];
                const cell_coord = board.cell_coord_from_index(cell_index);

                if ((cell_candidate_mask & number_mask) != 0) {
                    aabb.min = @min(aabb.min, cell_coord);
                    aabb.max = @max(aabb.max, cell_coord);
                    candidate_count.* += 1;
                    box_region_mask |= sudoku.mask_for_number(@intCast(region_cell_index));
                }
            }

            // Test if we have a valid AABB
            // We don't care about single candidates, they should be found with simpler solving method already
            if (candidate_count.* >= 2) {
                const aabb_extent = aabb.max - aabb.min;
                assert(!all(aabb_extent == u32_2{ 0, 0 })); // This should be handled by naked singles already

                if (aabb_extent[0] == 0 or aabb_extent[1] == 0) {
                    const line_region = if (aabb_extent[0] == 0) board.col_regions[aabb.min[0]] else board.row_regions[aabb.min[1]];

                    var deletion_mask: u16 = 0;
                    for (line_region, 0..) |cell_index, region_cell_index_usize| {
                        const region_cell_index: u4 = @intCast(region_cell_index_usize);
                        const line_cell_box_index = board.box_indices[cell_index];

                        if (line_cell_box_index != box_index) {
                            if (candidate_masks[cell_index] & number_mask != 0) {
                                deletion_mask |= @as(u16, 1) << region_cell_index;
                            }
                        }
                    }

                    if (deletion_mask != 0) {
                        return PointingLine{
                            .number = number,
                            .line_region = line_region,
                            .line_region_deletion_mask = deletion_mask,
                            .box_region = box_region,
                            .box_region_mask = box_region_mask,
                        };
                    }
                }
            }
        }
    }

    return null;
}

pub const BoxLineReduction = struct {
    number: u4,
    box_region: []u32,
    box_region_deletion_mask: u16,
    line_region: []u32,
    line_region_mask: u16,
};

pub fn apply_box_line_reduction(candidate_masks: []u16, box_line_reduction: BoxLineReduction) void {
    const number_mask = sudoku.mask_for_number(box_line_reduction.number);
    for (box_line_reduction.box_region, 0..) |cell_index, region_cell_index| {
        // FIXME super confusing
        if (sudoku.mask_for_number(@intCast(region_cell_index)) & box_line_reduction.box_region_deletion_mask != 0) {
            candidate_masks[cell_index] &= ~number_mask;
        }
    }
}

pub fn find_box_line_reduction(board: BoardState, candidate_masks: []const u16) ?BoxLineReduction {
    for (board.col_regions, 0..) |col_region, col_index| {
        if (find_box_line_reduction_for_line(board, candidate_masks, col_region, u32_2{ @intCast(col_index), board.extent })) |event| {
            return event;
        }
    }

    for (board.row_regions, 0..) |row_region, row_index| {
        if (find_box_line_reduction_for_line(board, candidate_masks, row_region, u32_2{ board.extent, @intCast(row_index) })) |event| {
            return event;
        }
    }

    return null;
}

pub fn find_box_line_reduction_for_line(board: BoardState, candidate_masks: []const u16, line_region: []u32, line_coord: u32_2) ?BoxLineReduction {
    for (0..board.extent) |number_usize| {
        const number: u4 = @intCast(number_usize);
        const number_mask = sudoku.mask_for_number(number);

        var line_region_mask: u16 = 0;
        var box_index_mask: u16 = 0;

        for (line_region, 0..) |cell_index, region_cell_index_usize| {
            const region_cell_index: u4 = @intCast(region_cell_index_usize);

            if (candidate_masks[cell_index] & number_mask != 0) {
                line_region_mask |= @as(u16, 1) << region_cell_index;

                const box_index = board.box_indices[cell_index];
                box_index_mask |= sudoku.mask_for_number(@intCast(box_index));
            }
        }

        if (@popCount(box_index_mask) == 1) {
            const box_index = first_bit_index_u16(box_index_mask);
            const box_region = board.box_regions[box_index];

            var deletion_mask: u16 = 0;
            for (box_region, 0..) |cell_index, region_cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);

                if (all(cell_coord != line_coord)) {
                    if (candidate_masks[cell_index] & number_mask != 0) {
                        deletion_mask |= sudoku.mask_for_number(@intCast(region_cell_index));
                    }
                }
            }

            if (deletion_mask != 0) {
                return BoxLineReduction{
                    .number = number,
                    .box_region = box_region,
                    .box_region_deletion_mask = deletion_mask,
                    .line_region = line_region,
                    .line_region_mask = line_region_mask,
                };
            }
        }
    }

    return null;
}

pub const Technique = union(enum(u4)) {
    naked_single: NakedSingle,
    naked_pair: NakedPair,
    hidden_single: HiddenSingle,
    hidden_pair: HiddenPair,
    pointing_line: PointingLine,
    box_line_reduction: BoxLineReduction,
};

pub fn find_easiest_known_technique(board: BoardState, candidate_masks: []const u16) ?Technique {
    if (find_naked_single(board, candidate_masks)) |naked_single| {
        return .{ .naked_single = naked_single };
    } else if (find_hidden_single(board, candidate_masks)) |hidden_single| {
        return .{ .hidden_single = hidden_single };
    } else if (find_naked_pair(board, candidate_masks)) |naked_pair| {
        return .{ .naked_pair = naked_pair };
    } else if (find_hidden_pair(board, candidate_masks)) |hidden_pair| {
        return .{ .hidden_pair = hidden_pair };
    } else if (find_pointing_line(board, candidate_masks)) |pointing_line| {
        return .{ .pointing_line = pointing_line };
    } else if (find_box_line_reduction(board, candidate_masks)) |box_line_reduction| {
        return .{ .box_line_reduction = box_line_reduction };
    } else {
        return null;
    }
}

pub fn apply_technique(board: *BoardState, candidate_masks: []u16, solver_event: Technique) void {
    switch (solver_event) {
        .naked_single => |naked_single| {
            apply_naked_single(board, candidate_masks, naked_single);
        },
        .naked_pair => |naked_pair| {
            apply_naked_pair(candidate_masks, naked_pair);
        },
        .hidden_single => |hidden_single| {
            apply_hidden_single(board, candidate_masks, hidden_single);
        },
        .hidden_pair => |hidden_pair| {
            apply_hidden_pair(candidate_masks, hidden_pair);
        },
        .pointing_line => |pointing_line| {
            apply_pointing_line(candidate_masks, pointing_line);
        },
        .box_line_reduction => |box_line_reduction| {
            apply_box_line_reduction(candidate_masks, box_line_reduction);
        },
    }
}
