const std = @import("std");
const assert = std.debug.assert;

const rules = @import("rules.zig");
const board_generic = @import("board_generic.zig");

// Only generates a regular sudoku board
// This is a naive implementation that doesn't guarantee a unique solution
pub fn generate(extent: comptime_int, board_rules: rules.Rules, seed: u64) board_generic.State(extent) {
    std.debug.assert(!board_rules.chess_anti_king);
    std.debug.assert(!board_rules.chess_anti_knight);

    var board = board_generic.State(extent).init(board_rules);

    const regular_type: rules.RegularSudoku = switch (board.rules.type) {
        .regular => |r| r,
        else => @panic("Naive generator only supports regular sudoku boards"),
    };

    // Generate a full board by using an ordered sequence
    // that guarantees a valid output
    for (0..board.Extent) |region_index| {
        for (board.regions.row(region_index), 0..) |cell_index, col| {
            const line_offset = region_index * regular_type.box_extent[0];
            const box_offset = region_index / regular_type.box_extent[1];
            const number: u4 = @intCast(@as(u32, @intCast(col + line_offset + box_offset)) % board.Extent);

            board.numbers[cell_index] = number;
        }
    }

    var rng = std.Random.Xoroshiro128.init(seed);
    const rounds = 1000; // FIXME

    // Apply isomorphisms to that board to make it look more interesting
    // Possible candidates:
    // - Swap two parallel lines going through the same box
    // - Flip horizontally or vertically
    // - Rotate by 180 degrees
    for (0..rounds) |_| {
        swap_random_col(extent, &board, regular_type, &rng);
        swap_random_row(extent, &board, regular_type, &rng);
    }

    // Remove numbers at random places to give a challenge to the player.
    // FIXME The biggest issue here is that we don't control resulting difficulty very well,
    // and we might even generate a board that has too many holes therefore multiple solutions.
    var numbers_to_remove = (board.numbers.len * 2) / 4;

    assert(numbers_to_remove < board.numbers.len);

    while (numbers_to_remove > 0) {
        const cell_index = rng.random().uintLessThan(u32, board.ExtentSqr);

        if (board.numbers[cell_index] != null) {
            board.numbers[cell_index] = null;
            numbers_to_remove -= 1;
        }
    }

    return board;
}

fn swap_random_col(extent: comptime_int, board: *board_generic.State(extent), regular_type: rules.RegularSudoku, rng: *std.Random.Xoroshiro128) void {
    const box_x = rng.random().uintLessThan(u32, regular_type.box_extent[1]);
    const col_offset = box_x * regular_type.box_extent[0];
    const col_a = col_offset + rng.random().uintLessThan(u32, regular_type.box_extent[0]);
    const col_b = col_offset + (rng.random().uintLessThan(u32, regular_type.box_extent[0] - 1) + col_a + 1) % regular_type.box_extent[0];

    assert(col_a != col_b);

    swap_region(extent, board, &board.regions.col(col_a), &board.regions.col(col_b));
}

fn swap_random_row(extent: comptime_int, board: *board_generic.State(extent), regular_type: rules.RegularSudoku, rng: *std.Random.Xoroshiro128) void {
    const box_y = rng.random().uintLessThan(u32, regular_type.box_extent[0]);
    const row_offset = box_y * regular_type.box_extent[1];
    const row_a = row_offset + rng.random().uintLessThan(u32, regular_type.box_extent[1]);
    const row_b = row_offset + (rng.random().uintLessThan(u32, regular_type.box_extent[1] - 1) + row_a + 1) % regular_type.box_extent[1];

    assert(row_a != row_b);

    swap_region(extent, board, &board.regions.row(row_a), &board.regions.row(row_b));
}

fn swap_region(extent: comptime_int, board: *board_generic.State(extent), region_a: []const u32, region_b: []const u32) void {
    for (region_a, region_b) |cell_index_a, cell_index_b| {
        std.mem.swap(?u4, &board.numbers[cell_index_a], &board.numbers[cell_index_b]);
    }
}
