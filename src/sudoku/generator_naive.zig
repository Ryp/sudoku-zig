const std = @import("std");
const assert = std.debug.assert;

const board_state = @import("board_legacy.zig");
const BoardState = board_state.BoardState;
const UnsetNumber = board_state.UnsetNumber;
const RegularSudoku = board_state.RegularSudoku;

// Only generates a regular sudoku board
// This is a naive implementation that doesn't guarantee a unique solution
pub fn generate(board: *BoardState, seed: u64) void {
    const regular_type = board.game_type.regular;

    // Generate a full board by using an ordered sequence
    // that guarantees a valid output
    for (0..board.extent) |region_index| {
        for (board.row_regions[region_index], 0..) |cell_index, i| {
            const line_offset = region_index * regular_type.box_w;
            const box_offset = region_index / regular_type.box_h;
            const number: u4 = @intCast(@as(u32, @intCast(i + line_offset + box_offset)) % board.extent);

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
        swap_random_col(board, regular_type, &rng);
        swap_random_row(board, regular_type, &rng);
    }

    // Remove numbers at random places to give a challenge to the player.
    // FIXME The biggest issue here is that we don't control resulting difficulty very well,
    // and we might even generate a board that has too many holes therefore multiple solutions.
    var numbers_to_remove = (board.numbers.len * 2) / 4;

    assert(numbers_to_remove < board.numbers.len);

    while (numbers_to_remove > 0) {
        const cell_index = rng.random().uintLessThan(u32, board.extent * board.extent);

        const cell_number = &board.numbers[cell_index];

        if (cell_number.* != UnsetNumber) {
            cell_number.* = UnsetNumber;
            numbers_to_remove -= 1;
        }
    }
}

fn swap_random_col(board: *BoardState, regular_type: RegularSudoku, rng: *std.Random.Xoroshiro128) void {
    // FIXME Use box count var
    const box_x = rng.random().uintLessThan(u32, regular_type.box_h);
    const col_offset = box_x * regular_type.box_w;
    const col_a = col_offset + rng.random().uintLessThan(u32, regular_type.box_w);
    const col_b = col_offset + (rng.random().uintLessThan(u32, regular_type.box_w - 1) + col_a + 1) % regular_type.box_w;

    assert(col_a != col_b);
    swap_region(board, board.col_regions[col_a], board.col_regions[col_b]);
}

fn swap_random_row(board: *BoardState, regular_type: RegularSudoku, rng: *std.Random.Xoroshiro128) void {
    // FIXME Use box count var
    const box_y = rng.random().uintLessThan(u32, regular_type.box_w);
    const row_offset = box_y * regular_type.box_h;
    const row_a = row_offset + rng.random().uintLessThan(u32, regular_type.box_h);
    const row_b = row_offset + (rng.random().uintLessThan(u32, regular_type.box_h - 1) + row_a + 1) % regular_type.box_h;

    assert(row_a != row_b);
    swap_region(board, board.row_regions[row_a], board.row_regions[row_b]);
}

fn swap_region(board: *BoardState, region_a: []u32, region_b: []u32) void {
    for (region_a, region_b) |cell_index_a, cell_index_b| {
        std.mem.swap(u5, &board.numbers[cell_index_a], &board.numbers[cell_index_b]);
    }
}
