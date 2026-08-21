const std = @import("std");

const rules = @import("rules.zig");
const board = @import("board.zig");

const common = @import("common.zig");
const i32_2 = common.i32_2;
const all = common.all;

pub const ValidationError = struct {
    number: u4,
    is_candidate: bool,
    invalid_cell_index: u32,
    reference_cell_index: u32,
    region_index_opt: ?board.RegionIndex,
};

pub fn check_board_for_errors(board_state: *const board.Board, candidate_masks_opt: ?[]const board.MaskType) ?ValidationError {
    // Iterate over all filled cells of the board
    for (board_state.numbers_const(), 0..) |number_opt, reference_cell_index| {
        if (number_opt) |number| {
            const number_mask = board_state.mask_for_number(number);

            const cell_coord = board_state.cell_coord_from_index(reference_cell_index);

            const col_region_index = board_state.regions.get_region_index(.Col, cell_coord[0]);
            const row_region_index = board_state.regions.get_region_index(.Row, cell_coord[1]);
            const box_region_index = board_state.regions.get_region_index(.Box, board_state.regions.box_indices()[reference_cell_index]);

            // For that filled cell, check all its connected regions for duplicates
            inline for (.{ col_region_index, row_region_index, box_region_index }) |region_index| {
                const region = board_state.regions.get(region_index);

                // Check for duplicate in a region
                for (region) |other_cell_index| {
                    // Don't count our reference cell
                    if (other_cell_index != reference_cell_index) {
                        if (board_state.numbers_const()[other_cell_index] == number) {
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

            if (board_state.rules.chess_anti_king) {
                if (check_anti_rule(board_state, candidate_masks_opt, &rules.AntiKingOffsets, @intCast(reference_cell_index), cell_coord_signed, number)) |err| {
                    return err;
                }
            }

            if (board_state.rules.chess_anti_knight) {
                if (check_anti_rule(board_state, candidate_masks_opt, &rules.AntiKnightOffsets, @intCast(reference_cell_index), cell_coord_signed, number)) |err| {
                    return err;
                }
            }
        }
    }

    return null;
}

fn check_anti_rule(board_state: *const board.Board, candidate_masks_opt: ?[]const board.MaskType, rule_offsets: []const i32_2, reference_cell_index: u32, cell_coord_signed: i32_2, number: u4) ?ValidationError {
    const number_mask = board_state.mask_for_number(number);

    for (rule_offsets) |offset| {
        const other_cell_coord = cell_coord_signed + offset;

        if (all(other_cell_coord >= i32_2{ 0, 0 }) and all(other_cell_coord < i32_2{ @intCast(board_state.extent), @intCast(board_state.extent) })) {
            const other_cell_index = board_state.cell_index_from_coord(@intCast(other_cell_coord));

            if (board_state.numbers_const()[other_cell_index] == number) {
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

const Regular2x2 = rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 2, 2 } } } };

test "Valid boards" {
    var board_state: board.Board = try .init(Regular2x2);

    // Empty board
    try std.testing.expectEqual(null, check_board_for_errors(&board_state, null));

    // Solved board
    try board_state.fill_board_from_string("1234341221434321");
    try std.testing.expectEqual(null, check_board_for_errors(&board_state, null));
}

test "Duplicate numbers in a region" {
    const any_number = 0;

    var board_state: board.Board = try .init(Regular2x2);

    const cell_index_ref = board_state.cell_index_from_coord(i32_2{ 1, 1 }); // A
    const cell_index_b = board_state.cell_index_from_coord(i32_2{ 2, 1 }); // On the same row as A
    const cell_index_c = board_state.cell_index_from_coord(i32_2{ 1, 2 }); // On the same column as A
    const cell_index_d = board_state.cell_index_from_coord(i32_2{ 0, 0 }); // On the same box as A

    // Setup row conflict
    board_state.numbers()[cell_index_ref] = any_number;
    board_state.numbers()[cell_index_b] = any_number;

    try std.testing.expectEqual(ValidationError{
        .number = any_number,
        .is_candidate = false,
        // It shouldn't matter in which order the conflicting cells are reported, so this test might prove flaky since it expects a particular order.
        .invalid_cell_index = cell_index_b,
        .reference_cell_index = cell_index_ref,
        .region_index_opt = board_state.regions.get_region_index(.Row, 1),
    }, check_board_for_errors(&board_state, null));

    // Setup column conflict
    board_state.numbers()[cell_index_b] = null;
    board_state.numbers()[cell_index_c] = any_number;

    // Column duplicate
    try std.testing.expectEqual(ValidationError{
        .number = any_number,
        .is_candidate = false,
        // It shouldn't matter in which order the conflicting cells are reported, so this test might prove flaky since it expects a particular order.
        .invalid_cell_index = cell_index_c,
        .reference_cell_index = cell_index_ref,
        .region_index_opt = board_state.regions.get_region_index(.Col, 1),
    }, check_board_for_errors(&board_state, null));

    // Setup box conflict
    board_state.numbers()[cell_index_c] = null;
    board_state.numbers()[cell_index_d] = any_number;

    // Column duplicate
    try std.testing.expectEqual(ValidationError{
        .number = any_number,
        .is_candidate = false,
        // It shouldn't matter in which order the conflicting cells are reported, so this test might prove flaky since it expects a particular order.
        .invalid_cell_index = cell_index_ref,
        .reference_cell_index = cell_index_d,
        .region_index_opt = board_state.regions.get_region_index(.Box, 0),
    }, check_board_for_errors(&board_state, null));
}

test "Candidate conflicting with a placed number" {
    var board_state: board.Board = try .init(Regular2x2);
    try board_state.fill_board_from_string("1...............");

    var candidate_masks = std.mem.zeroes([16]board.MaskType);
    try std.testing.expectEqual(null, check_board_for_errors(&board_state, &candidate_masks));

    // Mark number 1 as a candidate in the same row
    candidate_masks[2] = board_state.mask_for_number(0);

    const candidate_error = check_board_for_errors(&board_state, &candidate_masks) orelse return error.TestExpectedError;
    try std.testing.expectEqual(0, candidate_error.number);
    try std.testing.expect(candidate_error.is_candidate);
    try std.testing.expectEqual(2, candidate_error.invalid_cell_index);
}

test "king" {
    var king_rules = Regular2x2;
    king_rules.chess_anti_king = true;
    var king_board: board.Board = try .init(king_rules);

    const any_number = 2;

    const cell_index_a = king_board.cell_index_from_coord(i32_2{ 1, 1 });
    const cell_index_b = king_board.cell_index_from_coord(i32_2{ 2, 2 }); // At a king's move from A (should fire)
    const cell_index_c = king_board.cell_index_from_coord(i32_2{ 3, 0 }); // At a knight's move from A (shouldn't fire)

    king_board.numbers()[cell_index_a] = any_number;
    king_board.numbers()[cell_index_b] = any_number;
    king_board.numbers()[cell_index_c] = any_number;

    try std.testing.expectEqual(ValidationError{
        .number = any_number,
        .is_candidate = false,
        // It shouldn't matter in which order the conflicting cells are reported, so this test might prove flaky since it expects a particular order.
        .invalid_cell_index = cell_index_b,
        .reference_cell_index = cell_index_a,
        .region_index_opt = null,
    }, check_board_for_errors(&king_board, null));
}

test "knight" {
    var knight_rules = Regular2x2;
    knight_rules.chess_anti_knight = true;
    var knight_board: board.Board = try .init(knight_rules);

    const any_number = 3;

    const cell_index_a = knight_board.cell_index_from_coord(i32_2{ 1, 1 });
    const cell_index_b = knight_board.cell_index_from_coord(i32_2{ 3, 0 }); // At a knight's move from A (should fire)
    const cell_index_c = knight_board.cell_index_from_coord(i32_2{ 2, 2 }); // At a king's move from A (shouldn't fire)

    knight_board.numbers()[cell_index_a] = any_number;
    knight_board.numbers()[cell_index_b] = any_number;
    knight_board.numbers()[cell_index_c] = any_number;

    try std.testing.expectEqual(ValidationError{
        .number = any_number,
        .is_candidate = false,
        // It shouldn't matter in which order the conflicting cells are reported, so this test might prove flaky since it expects a particular order.
        .invalid_cell_index = cell_index_a,
        .reference_cell_index = cell_index_b,
        .region_index_opt = null,
    }, check_board_for_errors(&knight_board, null));
}
