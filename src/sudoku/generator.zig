const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
// FIXME Use another simpler struct for the board?
const GameState = sudoku.GameState;
const UnsetNumber = sudoku.UnsetNumber;

fn swap_random_col(game: *GameState, regular_type: sudoku.RegularSudoku, rng: *std.rand.Xoroshiro128) void {
    // FIXME Use box count var
    const box_x = rng.random().uintLessThan(u32, regular_type.box_h);
    const col_offset = box_x * regular_type.box_w;
    const col_a = col_offset + rng.random().uintLessThan(u32, regular_type.box_w);
    const col_b = col_offset + (rng.random().uintLessThan(u32, regular_type.box_w - 1) + col_a + 1) % regular_type.box_w;

    assert(col_a != col_b);
    swap_region(game, game.col_regions[col_a], game.col_regions[col_b]);
}

fn swap_random_row(game: *GameState, regular_type: sudoku.RegularSudoku, rng: *std.rand.Xoroshiro128) void {
    // FIXME Use box count var
    const box_y = rng.random().uintLessThan(u32, regular_type.box_w);
    const row_offset = box_y * regular_type.box_h;
    const row_a = row_offset + rng.random().uintLessThan(u32, regular_type.box_h);
    const row_b = row_offset + (rng.random().uintLessThan(u32, regular_type.box_h - 1) + row_a + 1) % regular_type.box_h;

    assert(row_a != row_b);
    swap_region(game, game.row_regions[row_a], game.row_regions[row_b]);
}

fn swap_region(game: *GameState, region_a: []u32, region_b: []u32) void {
    for (region_a, region_b) |cell_index_a, cell_index_b| {
        var cell_a = &game.board[cell_index_a];
        var cell_b = &game.board[cell_index_b];

        std.mem.swap(u5, &cell_a.number, &cell_b.number);
    }
}

pub fn generate_dumb_board(game: *GameState) void {
    const regular_type = game.game_type.regular;

    // Generate a full board by using an ordered sequence
    // that guarantees a valid output
    for (0..game.extent) |region_index| {
        for (game.row_regions[region_index], 0..) |cell_index, i| {
            const line_offset = region_index * regular_type.box_w;
            const box_offset = region_index / regular_type.box_h;
            const number: u4 = @intCast(@as(u32, @intCast(i + line_offset + box_offset)) % game.extent);

            game.board[cell_index].number = number;
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
        swap_random_col(game, regular_type, &rng);
        swap_random_row(game, regular_type, &rng);
    }

    // Remove numbers at random places to give a challenge to the player.
    // FIXME The biggest issue here is that we don't control resulting difficulty very well,
    // and we might even generate a board that has too many holes therefore multiple solutions.
    const cell_count = game.extent * game.extent;
    var numbers_to_remove = (cell_count * 2) / 4;

    assert(numbers_to_remove < cell_count);

    while (numbers_to_remove > 0) {
        const cell_index = rng.random().uintLessThan(u32, game.extent * game.extent);

        var cell = &game.board[cell_index];

        if (cell.number != UnsetNumber) {
            cell.number = UnsetNumber;
            numbers_to_remove -= 1;
        }
    }
}
