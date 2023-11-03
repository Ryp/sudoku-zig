const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
// FIXME Use another simpler struct for the board?
const BoardState = sudoku.BoardState;
const UnsetNumber = sudoku.UnsetNumber;

fn swap_random_col(board: *BoardState, regular_type: sudoku.RegularSudoku, rng: *std.rand.Xoroshiro128) void {
    // FIXME Use box count var
    const box_x = rng.random().uintLessThan(u32, regular_type.box_h);
    const col_offset = box_x * regular_type.box_w;
    const col_a = col_offset + rng.random().uintLessThan(u32, regular_type.box_w);
    const col_b = col_offset + (rng.random().uintLessThan(u32, regular_type.box_w - 1) + col_a + 1) % regular_type.box_w;

    assert(col_a != col_b);
    swap_region(board, board.col_regions[col_a], board.col_regions[col_b]);
}

fn swap_random_row(board: *BoardState, regular_type: sudoku.RegularSudoku, rng: *std.rand.Xoroshiro128) void {
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

pub fn generate_dumb_board(board: *BoardState) void {
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

    // Using the method from the docs to get a reasonably random seed
    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(buf[0..]);
    const seed = std.mem.readIntSliceLittle(u64, buf[0..8]);

    var rng = std.rand.Xoroshiro128.init(seed);
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
    const cell_count = board.extent * board.extent;
    var numbers_to_remove = (cell_count * 2) / 4;

    assert(numbers_to_remove < cell_count);

    while (numbers_to_remove > 0) {
        const cell_index = rng.random().uintLessThan(u32, board.extent * board.extent);

        var cell_number = &board.numbers[cell_index];

        if (cell_number.* != UnsetNumber) {
            cell_number.* = UnsetNumber;
            numbers_to_remove -= 1;
        }
    }
}
