const std = @import("std");
const assert = std.debug.assert;

const board = @import("board.zig");
const rules = @import("rules.zig");
const RegionIndex = board.RegionIndex;
const RegionSet = board.RegionSet;

const known_boards = @import("known_boards.zig");

const common = @import("common.zig");
const u32_2 = common.u32_2;
const i32_2 = common.i32_2;
const all = common.all;

pub fn place_number_remove_trivial_candidates(board_state: *board.Board, candidate_masks: []u16, cell_index: u32, number: u4) void {
    board_state.numbers()[cell_index] = number;

    remove_trivial_candidates_for_number_at(board_state, candidate_masks, cell_index, number);
}

pub fn trivial_candidate_masks_max(board_state: *const board.Board) [board.MaxExtentSqr]board.MaskType {
    const extent_sqr = board_state.extent * board_state.extent;

    var candidate_masks_max: [board.MaxExtentSqr]board.MaskType = .{board_state.full_candidate_mask()} ** board.MaxExtentSqr;
    const candidate_masks = candidate_masks_max[0..extent_sqr];

    for (board_state.numbers_const(), 0..) |number_opt, cell_index| {
        if (number_opt) |number| {
            remove_trivial_candidates_for_number_at(board_state, candidate_masks, @intCast(cell_index), number);
        }
    }

    return candidate_masks_max;
}

fn remove_trivial_candidates_for_number_at(board_state: *const board.Board, candidate_masks: []u16, cell_index: u32, number: u4) void {
    candidate_masks[cell_index] = 0;

    // Remove candidates
    const cell_coord = board_state.cell_coord_from_index(cell_index);
    const box_index = board_state.regions.box_indices()[cell_index];

    const col_region = board_state.regions.col(cell_coord[0]);
    const row_region = board_state.regions.row(cell_coord[1]);
    const box_region = board_state.regions.box(box_index);

    const deletion_mask = ~board_state.mask_for_number(number);

    for (col_region, row_region, box_region) |col_cell, row_cell, box_cell| {
        candidate_masks[col_cell] &= deletion_mask;
        candidate_masks[row_cell] &= deletion_mask;
        candidate_masks[box_cell] &= deletion_mask;
    }

    const extent_signed: i32 = @intCast(board_state.extent);
    const cell_coord_signed: i32_2 = @intCast(cell_coord);

    if (board_state.rules.chess_anti_king) {
        for (rules.AntiKingOffsets) |offset| {
            const coord = cell_coord_signed + offset;

            if (all(coord >= i32_2{ 0, 0 }) and all(coord < i32_2{ extent_signed, extent_signed })) {
                const index = board_state.cell_index_from_coord(@intCast(coord));
                candidate_masks[index] &= deletion_mask;
            }
        }
    }

    if (board_state.rules.chess_anti_knight) {
        for (rules.AntiKnightOffsets) |offset| {
            const coord = cell_coord_signed + offset;

            if (all(coord >= i32_2{ 0, 0 }) and all(coord < i32_2{ extent_signed, extent_signed })) {
                const index = board_state.cell_index_from_coord(@intCast(coord));
                candidate_masks[index] &= deletion_mask;
            }
        }
    }
}

pub const NakedSingle = struct {
    cell_index: u32,
    number: u4,
};

pub fn apply_naked_single(board_state: *board.Board, candidate_masks: []u16, naked_single: NakedSingle) void {
    place_number_remove_trivial_candidates(board_state, candidate_masks, naked_single.cell_index, naked_single.number);
}

// If there's a cell with a single possibility left, put it down
pub fn find_naked_single(board_state: board.Board, candidate_masks: []const u16) ?NakedSingle {
    for (board_state.numbers_const(), candidate_masks, 0..) |number_opt, candidate_mask, cell_index| {
        if (number_opt == null and @popCount(candidate_mask) == 1) {
            const number: u4 = @intCast(@ctz(candidate_mask));

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
    region_index: RegionIndex,
};

pub fn apply_naked_pair(board_state: board.Board, candidate_masks: []u16, naked_pair: NakedPair) void {
    for (board_state.regions.get(naked_pair.region_index), 0..) |cell_index, region_cell_index| {
        candidate_masks[cell_index] &= ~(((naked_pair.deletion_mask_a >> @as(u4, @intCast(region_cell_index))) & 0b1) << naked_pair.number_a);
        candidate_masks[cell_index] &= ~(((naked_pair.deletion_mask_b >> @as(u4, @intCast(region_cell_index))) & 0b1) << naked_pair.number_b);
    }
}

pub fn find_naked_pair(board_state: board.Board, candidate_masks: []const u16) ?NakedPair {
    inline for (.{ RegionSet.Col, RegionSet.Row, RegionSet.Box }) |set| {
        for (0..board_state.extent) |sub_index| {
            if (find_naked_pair_region(board_state, candidate_masks, .{ .set = set, .sub_index = sub_index })) |naked_pair| {
                return naked_pair;
            }
        }
    }

    return null;
}

// This function works once per region, meaning that if candidates to remove are found in overlapping regions,
// like in a line as well as in a box, then we're only counting one of them.
pub fn find_naked_pair_region(board_state: board.Board, candidate_masks: []const u16, region_index: RegionIndex) ?NakedPair {
    const region = board_state.regions.get(region_index);

    for (region, 0..) |cell_index_a, region_cell_index_a| {
        const candidate_mask_a = candidate_masks[cell_index_a];
        const candidate_count_a = @popCount(candidate_mask_a);

        if (candidate_count_a == 2) {
            for (region[region_cell_index_a + 1 ..]) |cell_index_b| {
                const candidate_mask_b = candidate_masks[cell_index_b];

                if (candidate_mask_a == candidate_mask_b) {
                    const number_a: u4 = @intCast(@ctz(candidate_mask_a));
                    const number_b: u4 = @intCast(@ctz(candidate_mask_a - board_state.mask_for_number(@intCast(number_a))));

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
                            .region_index = region_index,
                        };
                    }
                }
            }
        }
    }

    return null;
}

test "Naked pair" {
    const regular_rules = rules.Regular3x3;

    var board_state: board.Board = .init(regular_rules);

    var candidate_masks = std.mem.zeroes([board.MaxExtentSqr]board.MaskType);

    // Make sure that there's no hit for the initial board
    try std.testing.expect(find_naked_pair(board_state, &candidate_masks) == null);

    const number_a: u4 = 0;
    const number_b: u4 = 8;
    const pair_mask = board_state.mask_for_number(number_a) | board_state.mask_for_number(number_b);

    // Setup a naked pair
    candidate_masks[0] = pair_mask;
    candidate_masks[1] = pair_mask;

    // There shouldn't be any hit if there's no candidates to remove
    try std.testing.expect(find_naked_pair(board_state, &candidate_masks) == null);

    candidate_masks[2] = board_state.mask_for_number(number_a);
    candidate_masks[3] = board_state.mask_for_number(number_b);

    // Make sure we get a hit
    if (find_naked_pair(board_state, &candidate_masks)) |naked_pair| {
        try std.testing.expectEqual(number_a, naked_pair.number_a);
        try std.testing.expectEqual(number_b, naked_pair.number_b);
        try std.testing.expectEqual(0b0100, naked_pair.deletion_mask_a);
        try std.testing.expectEqual(0b1000, naked_pair.deletion_mask_b);

        // Apply the solver event
        apply_naked_pair(board_state, &candidate_masks, naked_pair);

        // Make sure we don't hit again after applying the solver event
        try std.testing.expect(find_naked_pair(board_state, &candidate_masks) == null);
    } else {
        try std.testing.expect(false);
    }
}

pub const HiddenSingle = struct {
    number: u4,
    cell_index: u32,
    deletion_mask: u16, // Mask of candidates that can be removed
    region_index: RegionIndex,
};

pub fn apply_hidden_single(board_state: *board.Board, candidate_masks: []u16, hidden_single: HiddenSingle) void {
    place_number_remove_trivial_candidates(board_state, candidate_masks, hidden_single.cell_index, hidden_single.number);
}

pub fn find_hidden_single(board_state: board.Board, candidate_masks: []const u16) ?HiddenSingle {
    inline for (.{ RegionSet.Col, RegionSet.Row, RegionSet.Box }) |set| {
        for (0..board_state.extent) |sub_index| {
            if (find_hidden_single_region(board_state, candidate_masks, .{ .set = set, .sub_index = sub_index })) |solver_event| {
                return solver_event;
            }
        }
    }

    return null;
}

pub const HiddenPair = struct {
    a: HiddenSingle,
    b: HiddenSingle,
};

pub fn apply_hidden_pair(candidate_masks: []board.MaskType, hidden_pair: HiddenPair) void {
    candidate_masks[hidden_pair.a.cell_index] &= ~hidden_pair.a.deletion_mask;
    candidate_masks[hidden_pair.b.cell_index] &= ~hidden_pair.b.deletion_mask;
}

pub fn find_hidden_pair(board_state: board.Board, candidate_masks: []const board.MaskType) ?HiddenPair {
    inline for (.{ RegionSet.Col, RegionSet.Row, RegionSet.Box }) |set| {
        for (0..board_state.extent) |sub_index| {
            if (find_hidden_pair_region(board_state, candidate_masks, .{ .set = set, .sub_index = sub_index })) |hidden_pair| {
                return hidden_pair;
            }
        }
    }

    return null;
}

// If there's a region (col/row/box) where a possibility appears only once, put it down
fn find_hidden_single_region(board_state: board.Board, candidate_masks: []const u16, region_index: RegionIndex) ?HiddenSingle {
    var counts_max = std.mem.zeroes([board.MaxExtent]u32);
    const counts = counts_max[0..board_state.extent];
    var last_cell_indices_max: [board.MaxExtent]u32 = undefined;
    const last_cell_indices = last_cell_indices_max[0..board_state.extent];

    for (board_state.regions.get(region_index)) |cell_index| {
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
            const deletion_mask = candidate_masks[cell_index] & ~board_state.mask_for_number(number);

            if (board_state.numbers_const()[cell_index] == null and deletion_mask != 0) {
                return HiddenSingle{
                    .number = number,
                    .cell_index = cell_index,
                    .deletion_mask = deletion_mask,
                    .region_index = region_index,
                };
            }
        }
    }

    return null;
}

fn find_hidden_pair_region(board_state: board.Board, candidate_masks: []const u16, region_index: RegionIndex) ?HiddenPair {
    const region = board_state.regions.get(region_index);

    var counts_max = std.mem.zeroes([board.MaxExtent]u32);
    const counts = counts_max[0..board_state.extent];

    // Contains first and last position
    const min_max_initial_value = u32_2{ board_state.extent, 0 };
    var region_min_max_cell_indices_max: [board.MaxExtent]u32_2 = .{min_max_initial_value} ** board.MaxExtent;
    const region_min_max_cell_indices = region_min_max_cell_indices_max[0..board_state.extent];

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

    for (counts[0 .. board_state.extent - 1], 0..) |first_number_count, first_number| {
        if (first_number_count == 2) {
            const second_number_start = first_number + 1;

            for (counts[second_number_start..], second_number_start..) |second_number_count, second_number| {
                assert(second_number < board_state.extent);

                if (second_number_count == 2 and all(region_min_max_cell_indices[first_number] == region_min_max_cell_indices[second_number])) {
                    const mask = board_state.mask_for_number(@intCast(first_number)) | board_state.mask_for_number(@intCast(second_number));
                    const region_cell_index_a = region_min_max_cell_indices[first_number][0];
                    const region_cell_index_b = region_min_max_cell_indices[first_number][1];
                    const cell_index_a = region[region_cell_index_a];
                    const cell_index_b = region[region_cell_index_b];
                    const deletion_mask_a = candidate_masks[cell_index_a] & ~mask;
                    const deletion_mask_b = candidate_masks[cell_index_b] & ~mask;

                    if (deletion_mask_a != 0 or deletion_mask_b != 0) {
                        return HiddenPair{
                            .a = HiddenSingle{
                                .number = @intCast(first_number),
                                .cell_index = cell_index_a,
                                .deletion_mask = deletion_mask_a,
                                .region_index = region_index,
                            },
                            .b = HiddenSingle{
                                .number = @intCast(second_number),
                                .cell_index = cell_index_b,
                                .deletion_mask = deletion_mask_b,
                                .region_index = region_index,
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
    line_region_index: RegionIndex,
    line_region_deletion_mask: u16,
    box_region_index: RegionIndex,
    box_region_mask: u16,
};

pub fn apply_pointing_line(board_state: board.Board, candidate_masks: []u16, pointing_line: PointingLine) void {
    const line_region = board_state.regions.get(pointing_line.line_region_index);
    const number_mask = board_state.mask_for_number(pointing_line.number);

    for (line_region, 0..) |cell_index, region_cell_index| {
        if (board_state.mask_for_number(@intCast(region_cell_index)) & pointing_line.line_region_deletion_mask != 0) {
            candidate_masks[cell_index] &= ~number_mask;
        }
    }
}

// If candidates in a box are arranged in a line, remove them from other boxes on that line.
// Also called pointing pairs or triples in 9x9 sudoku.
pub fn find_pointing_line(board_state: board.Board, candidate_masks: []const u16) ?PointingLine {
    const AABB_u32 = struct {
        min: u32_2,
        max: u32_2,
    };

    for (0..board_state.extent) |box_index| {
        const box_region_index = board_state.regions.get_region_index(.Box, box_index);
        const box_region = board_state.regions.get(box_region_index);

        var box_aabbs_max: [board.MaxExtent]AABB_u32 = undefined;
        const box_aabbs = box_aabbs_max[0..board_state.extent];
        var candidate_counts_max = std.mem.zeroes([board.MaxExtent]u32);
        const candidate_counts = candidate_counts_max[0..board_state.extent];

        // Compute AABB of candidates for each number
        // FIXME cache remaining candidates per box and only iterate on this?
        for (box_aabbs, candidate_counts, 0..) |*aabb, *candidate_count, number_usize| {
            const number: u4 = @intCast(number_usize);
            const number_mask = board_state.mask_for_number(number);

            aabb.max = u32_2{ 0, 0 };
            aabb.min = u32_2{ board_state.extent, board_state.extent };

            var box_region_mask: u16 = 0;

            for (box_region, 0..) |cell_index, region_cell_index| {
                const cell_candidate_mask = candidate_masks[cell_index];
                const cell_coord = board_state.cell_coord_from_index(cell_index);

                if ((cell_candidate_mask & number_mask) != 0) {
                    aabb.min = @min(aabb.min, cell_coord);
                    aabb.max = @max(aabb.max, cell_coord);
                    candidate_count.* += 1;
                    box_region_mask |= board_state.mask_for_number(@intCast(region_cell_index));
                }
            }

            // Test if we have a valid AABB
            // We don't care about single candidates, they should be found with simpler solving method already
            if (candidate_count.* >= 2) {
                const aabb_extent = aabb.max - aabb.min;
                assert(!all(aabb_extent == u32_2{ 0, 0 })); // This should be handled by naked singles already

                if (aabb_extent[0] == 0 or aabb_extent[1] == 0) {
                    const line_region_index: RegionIndex = if (aabb_extent[0] == 0)
                        .{ .set = .Col, .sub_index = aabb.min[0] }
                    else
                        .{ .set = .Row, .sub_index = aabb.min[1] };

                    const line_region = board_state.regions.get(line_region_index);

                    var deletion_mask: u16 = 0;
                    for (line_region, 0..) |cell_index, region_cell_index_usize| {
                        const region_cell_index: u4 = @intCast(region_cell_index_usize);
                        const line_cell_box_index = board_state.regions.box_indices()[cell_index];

                        if (line_cell_box_index != box_index) {
                            if (candidate_masks[cell_index] & number_mask != 0) {
                                deletion_mask |= @as(u16, 1) << region_cell_index;
                            }
                        }
                    }

                    if (deletion_mask != 0) {
                        return PointingLine{
                            .number = number,
                            .line_region_index = line_region_index,
                            .line_region_deletion_mask = deletion_mask,
                            .box_region_index = box_region_index,
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
    box_region_index: RegionIndex,
    box_region_deletion_mask: u16,
    line_region_index: RegionIndex,
    line_region_mask: u16,
};

pub fn apply_box_line_reduction(board_state: board.Board, candidate_masks: []u16, box_line_reduction: BoxLineReduction) void {
    const box_region = board_state.regions.get(box_line_reduction.box_region_index);
    const number_mask = board_state.mask_for_number(box_line_reduction.number);

    for (box_region, 0..) |cell_index, region_cell_index| {
        if (board_state.mask_for_number(@intCast(region_cell_index)) & box_line_reduction.box_region_deletion_mask != 0) {
            candidate_masks[cell_index] &= ~number_mask;
        }
    }
}

pub fn find_box_line_reduction(board_state: board.Board, candidate_masks: []const u16) ?BoxLineReduction {
    for (0..board_state.extent) |region_index| {
        const col_region_index = board_state.regions.get_region_index(.Col, region_index);
        if (find_box_line_reduction_for_line(board_state, candidate_masks, col_region_index, u32_2{ @intCast(region_index), board_state.extent })) |event| {
            return event;
        }

        const row_region_index = board_state.regions.get_region_index(.Row, region_index);
        if (find_box_line_reduction_for_line(board_state, candidate_masks, row_region_index, u32_2{ board_state.extent, @intCast(region_index) })) |event| {
            return event;
        }
    }

    return null;
}

pub fn find_box_line_reduction_for_line(board_state: board.Board, candidate_masks: []const u16, line_region_index: RegionIndex, line_coord: u32_2) ?BoxLineReduction {
    for (0..board_state.extent) |number_usize| {
        const number: u4 = @intCast(number_usize);
        const number_mask = board_state.mask_for_number(number);

        var line_region_mask: u16 = 0;
        var box_index_mask: u16 = 0;

        for (board_state.regions.get(line_region_index), 0..) |cell_index, region_cell_index_usize| {
            const region_cell_index: u4 = @intCast(region_cell_index_usize);

            if (candidate_masks[cell_index] & number_mask != 0) {
                line_region_mask |= @as(u16, 1) << region_cell_index;

                const box_index = board_state.regions.box_indices()[cell_index];
                box_index_mask |= board_state.mask_for_number(@intCast(box_index));
            }
        }

        if (@popCount(box_index_mask) == 1) {
            const box_index = @ctz(box_index_mask);
            const box_region_index = board_state.regions.get_region_index(.Box, box_index);
            const box_region = board_state.regions.get(box_region_index);

            var deletion_mask: u16 = 0;
            for (box_region, 0..) |cell_index, region_cell_index| {
                const cell_coord = board_state.cell_coord_from_index(cell_index);

                if (all(cell_coord != line_coord)) {
                    if (candidate_masks[cell_index] & number_mask != 0) {
                        deletion_mask |= board_state.mask_for_number(@intCast(region_cell_index));
                    }
                }
            }

            if (deletion_mask != 0) {
                return BoxLineReduction{
                    .number = number,
                    .box_region_index = box_region_index,
                    .box_region_deletion_mask = deletion_mask,
                    .line_region_index = line_region_index,
                    .line_region_mask = line_region_mask,
                };
            }
        }
    }

    return null;
}

test "Box-line removal" {
    const regular_rules = rules.Regular3x3;

    var board_state: board.Board = .init(regular_rules);

    const extent = board_state.extent;
    const extent_sqr = extent * extent;
    const full_mask = board_state.full_candidate_mask();

    var candidate_masks_max: [board.MaxExtentSqr]board.MaskType = .{full_mask} ** board.MaxExtentSqr;
    const candidate_masks = candidate_masks_max[0..extent_sqr];

    // Make sure that there's no hit for the initial board
    try std.testing.expect(find_box_line_reduction(board_state, candidate_masks) == null);

    const number: u4 = 0;

    // Remove candidates until we can apply the box-line solver
    for (3..9) |row_index| {
        const mask = board_state.mask_for_number(number);
        const cell_index = board_state.cell_index_from_coord(.{ 0, @intCast(row_index) });
        candidate_masks[cell_index] &= ~mask;
    }

    // Make sure we get a hit
    if (find_box_line_reduction(board_state, candidate_masks)) |box_line_reduction| {
        try std.testing.expectEqual(number, box_line_reduction.number);

        // Apply the solver event
        apply_technique(&board_state, candidate_masks, .{ .box_line_reduction = box_line_reduction });

        // Make sure we don't hit again after applying the solver event
        try std.testing.expect(find_box_line_reduction(board_state, candidate_masks) == null);
    } else {
        try std.testing.expect(false);
    }

    // Re-Fill candidate masks fully
    @memset(candidate_masks, full_mask);

    // Remove candidates until we can apply the box-line solver
    for (3..9) |col_index| {
        const mask = board_state.mask_for_number(number);
        const cell_index = board_state.cell_index_from_coord(.{ @intCast(col_index), 0 });
        candidate_masks[cell_index] &= ~mask;
    }

    if (find_box_line_reduction(board_state, candidate_masks)) |box_line_reduction| {
        try std.testing.expectEqual(number, box_line_reduction.number);
    } else {
        try std.testing.expect(false);
    }
}

pub const Technique = union(enum(u4)) {
    naked_single: NakedSingle,
    naked_pair: NakedPair,
    hidden_single: HiddenSingle,
    hidden_pair: HiddenPair,
    pointing_line: PointingLine,
    box_line_reduction: BoxLineReduction,
};

pub fn find_easiest_known_technique(board_state: board.Board, candidate_masks: []const u16) ?Technique {
    if (find_naked_single(board_state, candidate_masks)) |naked_single| {
        return .{ .naked_single = naked_single };
    } else if (find_hidden_single(board_state, candidate_masks)) |hidden_single| {
        return .{ .hidden_single = hidden_single };
    } else if (find_naked_pair(board_state, candidate_masks)) |naked_pair| {
        return .{ .naked_pair = naked_pair };
    } else if (find_hidden_pair(board_state, candidate_masks)) |hidden_pair| {
        return .{ .hidden_pair = hidden_pair };
    } else if (find_pointing_line(board_state, candidate_masks)) |pointing_line| {
        return .{ .pointing_line = pointing_line };
    } else if (find_box_line_reduction(board_state, candidate_masks)) |box_line_reduction| {
        return .{ .box_line_reduction = box_line_reduction };
    } else {
        return null;
    }
}

pub fn apply_technique(board_state: *board.Board, candidate_masks: []u16, solver_event: Technique) void {
    switch (solver_event) {
        .naked_single => |naked_single| {
            apply_naked_single(board_state, candidate_masks, naked_single);
        },
        .naked_pair => |naked_pair| {
            apply_naked_pair(board_state.*, candidate_masks, naked_pair);
        },
        .hidden_single => |hidden_single| {
            apply_hidden_single(board_state, candidate_masks, hidden_single);
        },
        .hidden_pair => |hidden_pair| {
            apply_hidden_pair(candidate_masks, hidden_pair);
        },
        .pointing_line => |pointing_line| {
            apply_pointing_line(board_state.*, candidate_masks, pointing_line);
        },
        .box_line_reduction => |box_line_reduction| {
            apply_box_line_reduction(board_state.*, candidate_masks, box_line_reduction);
        },
    }
}

pub fn solve(board_state: *board.Board) bool {
    var candidate_masks_max = trivial_candidate_masks_max(board_state);
    const candidate_masks = candidate_masks_max[0 .. board_state.extent * board_state.extent];

    while (find_easiest_known_technique(board_state.*, candidate_masks)) |technique| {
        apply_technique(board_state, candidate_masks, technique);
    }

    for (board_state.numbers()) |number_opt| {
        if (number_opt == null) {
            return false;
        }
    }

    return true;
}

test {
    inline for (known_boards.TestLogicalSolver) |known_board| {
        var board_state: board.Board = .init(known_board.rules);
        board_state.fill_board_from_string(known_board.start_string);

        try std.testing.expect(solve(&board_state));

        var solution_board: board.Board = .init(known_board.rules);
        solution_board.fill_board_from_string(known_board.solution_string);

        try std.testing.expectEqualSlices(?board.NumberType, solution_board.numbers(), board_state.numbers());
    }
}
