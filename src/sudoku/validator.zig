const rules = @import("rules.zig");
const board_generic = @import("board_generic.zig");

const common = @import("common.zig");
const i32_2 = common.i32_2;
const all = common.all;

pub const Error = struct {
    number: u4,
    is_candidate: bool,
    invalid_cell_index: u32,
    reference_cell_index: u32,
    region_index_opt: ?board_generic.RegionIndex,
};

pub fn check_board_for_errors(extent: comptime_int, board: *const board_generic.State(extent), candidate_masks_opt: ?[]const board_generic.MaskType(extent)) ?Error {
    // Iterate over all filled cells of the board
    for (board.numbers, 0..) |number_opt, reference_cell_index| {
        if (number_opt) |number| {
            const number_mask = board.mask_for_number(number);

            const cell_coord = board.cell_coord_from_index(reference_cell_index);

            const col_region_index = board.regions.get_region_index(.Col, cell_coord[0]);
            const row_region_index = board.regions.get_region_index(.Row, cell_coord[1]);
            const box_region_index = board.regions.get_region_index(.Box, board.regions.box_indices[reference_cell_index]);

            // For that filled cell, check all its connected regions for duplicates
            inline for (.{ col_region_index, row_region_index, box_region_index }) |region_index| {
                const region = board.regions.get(region_index);

                // Check for duplicate in a region
                for (region) |other_cell_index| {
                    // Don't count our reference cell
                    if (other_cell_index != reference_cell_index) {
                        if (board.numbers[other_cell_index] == number) {
                            return .{
                                .number = number,
                                .is_candidate = false,
                                .invalid_cell_index = @intCast(other_cell_index),
                                .reference_cell_index = @intCast(reference_cell_index),
                                .region_index_opt = region_index,
                            };
                        }

                        // Also check for invalid candidates if provided
                        if (candidate_masks_opt) |candidate_masks| {
                            if (candidate_masks[other_cell_index] & number_mask != 0) {
                                return .{
                                    .number = number,
                                    .is_candidate = true,
                                    .invalid_cell_index = @intCast(other_cell_index),
                                    .reference_cell_index = @intCast(reference_cell_index),
                                    .region_index_opt = region_index,
                                };
                            }
                        }
                    }
                }
            }

            const cell_coord_signed: i32_2 = @intCast(cell_coord);

            if (board.rules.chess_anti_king) {
                if (check_anti_rule(extent, board, candidate_masks_opt, &rules.AntiKingOffsets, @intCast(reference_cell_index), cell_coord_signed, number)) |err| {
                    return err;
                }
            }

            if (board.rules.chess_anti_knight) {
                if (check_anti_rule(extent, board, candidate_masks_opt, &rules.AntiKnightOffsets, @intCast(reference_cell_index), cell_coord_signed, number)) |err| {
                    return err;
                }
            }
        }
    }

    return null;
}

fn check_anti_rule(extent: comptime_int, board: *const board_generic.State(extent), candidate_masks_opt: ?[]const board_generic.MaskType(extent), rule_offsets: []const i32_2, reference_cell_index: u32, cell_coord_signed: i32_2, number: u4) ?Error {
    const number_mask = board.mask_for_number(number);

    for (rule_offsets) |offset| {
        const other_cell_coord = cell_coord_signed + offset;

        if (all(other_cell_coord >= i32_2{ 0, 0 }) and all(other_cell_coord < i32_2{ board.Extent, board.Extent })) {
            const other_cell_index = board.cell_index_from_coord(@intCast(other_cell_coord));

            if (board.numbers[other_cell_index] == number) {
                return .{
                    .number = number,
                    .is_candidate = false,
                    .invalid_cell_index = other_cell_index,
                    .reference_cell_index = reference_cell_index,
                    .region_index_opt = null,
                };
            }

            if (candidate_masks_opt) |candidate_masks| {
                if (candidate_masks[other_cell_index] & number_mask != 0) {
                    return .{
                        .number = number,
                        .is_candidate = true,
                        .invalid_cell_index = other_cell_index,
                        .reference_cell_index = reference_cell_index,
                        .region_index_opt = null,
                    };
                }
            }
        }
    }

    return null;
}
