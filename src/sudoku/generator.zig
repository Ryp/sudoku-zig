const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
// FIXME Use another simpler struct for the board?
const GameState = sudoku.GameState;
const UnsetNumber = sudoku.UnsetNumber;
const cell_at = sudoku.cell_at;
const u32_2 = sudoku.u32_2;

fn swap_random_col(game: *GameState, rng: *std.rand.Xoroshiro128) void {
    // FIXME Use box count var
    const box_x = rng.random().uintLessThan(u32, game.box_h);
    const col_offset = box_x * game.box_w;
    const col_a = col_offset + rng.random().uintLessThan(u32, game.box_w);
    const col_b = col_offset + (rng.random().uintLessThan(u32, game.box_w - 1) + col_a + 1) % game.box_w;

    assert(col_a != col_b);
    swap_region(game, game.col_regions[col_a], game.col_regions[col_b]);
}

fn swap_random_row(game: *GameState, rng: *std.rand.Xoroshiro128) void {
    // FIXME Use box count var
    const box_y = rng.random().uintLessThan(u32, game.box_w);
    const row_offset = box_y * game.box_h;
    const row_a = row_offset + rng.random().uintLessThan(u32, game.box_h);
    const row_b = row_offset + (rng.random().uintLessThan(u32, game.box_h - 1) + row_a + 1) % game.box_h;

    assert(row_a != row_b);
    swap_region(game, game.row_regions[row_a], game.row_regions[row_b]);
}

fn swap_region(game: *GameState, region_a: []u32_2, region_b: []u32_2) void {
    for (region_a, region_b) |cell_coord_a, cell_coord_b| {
        var cell_a = cell_at(game, cell_coord_a);
        var cell_b = cell_at(game, cell_coord_b);

        std.mem.swap(u5, &cell_a.number, &cell_b.number);
    }
}

pub fn generate_dumb_grid(game: *GameState) void {
    // Generate a full grid by using an ordered sequence
    // that guarantees a valid output
    for (0..game.extent) |region_index| {
        for (game.row_regions[region_index], 0..game.extent) |cell_coord, i| {
            var cell = cell_at(game, cell_coord);
            const line_offset = region_index * game.box_w;
            const box_offset = region_index / game.box_h;
            const number_index = @as(u32, @intCast(i + line_offset + box_offset)) % game.extent;

            cell.number = @intCast(number_index);
        }
    }

    // Using the method from the docs to get a reasonably random seed
    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(buf[0..]);
    const seed = std.mem.readIntSliceLittle(u64, buf[0..8]);

    var rng = std.rand.Xoroshiro128.init(seed);
    const rounds = 1000; // FIXME

    // Apply isomorphisms to that grid to make it look more interesting
    // Possible candidates:
    // - Swap two parallel lines going through the same column
    // - Flip horizontally or vertically
    // - Rotate by 180 degrees
    for (0..rounds) |_| {
        swap_random_col(game, &rng);
        swap_random_row(game, &rng);
    }

    // Remove numbers at random places to give a challenge to the player.
    // The biggest issue here is that we don't control resulting difficulty very well,
    // and we might even generate a grid that has too many holes therefore multiple solutions.
    const cell_count = game.extent * game.extent;
    var numbers_to_remove = (cell_count * 2) / 4;

    assert(numbers_to_remove < cell_count);

    while (numbers_to_remove > 0) {
        const x = rng.random().uintLessThan(u32, game.extent);
        const y = rng.random().uintLessThan(u32, game.extent);

        var cell = cell_at(game, .{ x, y });

        if (cell.number != UnsetNumber) {
            cell.number = UnsetNumber;
            numbers_to_remove -= 1;
        }
    }
}
