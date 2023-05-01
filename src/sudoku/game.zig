const std = @import("std");
const assert = std.debug.assert;

// Soon to be deprecated in zig 0.11 for 0..x style ranges
fn range(len: usize) []const void {
    return @as([*]void, undefined)[0..len];
}

// I borrowed this name from HLSL
fn all(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.Vector.child == bool);
    assert(type_info.Vector.len > 1);

    return @reduce(.And, vector);
}

fn any(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.Vector.child == bool);
    assert(type_info.Vector.len > 1);

    return @reduce(.Or, vector);
}

fn first_bit_index(mask_ro: u32) u32 {
    var mask = mask_ro; // FIXME

    for (range(32)) |_, index| {
        if ((mask & 1) != 0)
            return @intCast(u32, index);
        mask = mask >> 1;
    }

    return 32;
}

fn count_bits(mask_ro: u32) u32 {
    var bits: u32 = 0;
    var mask = mask_ro; // FIXME

    for (range(32)) |_| {
        bits += mask & 1;
        mask = mask >> 1;
    }

    return bits;
}

pub const @"u32_2" = std.meta.Vector(2, u32);

pub fn flat_index_to_2d(extent: u32, flat_index: usize) u32_2 {
    const x = @intCast(u32, flat_index % extent);
    const y = @intCast(u32, flat_index / extent);

    return .{ x, y };
}

const MaxHistorySize = 512;
const FullHintMask = 0b111111111;
const EmptyHintMask = 0b000000000;

pub const CellState = struct {
    set_number: u5 = 0,
    hint_mask: u9 = 0,
};

pub const GameState = struct {
    extent: u32,
    box_w: u32,
    box_h: u32,
    board: []CellState = undefined,
    selected_cell: u32_2 = undefined,
    rng: std.rand.Xoroshiro128, // Hardcode PRNG type for forward compatibility

    col_regions: []u32_2,
    row_regions: []u32_2,
    box_regions: []u32_2,

    history: []CellState = undefined,
    history_index: u32 = 0,
    max_history_index: u32 = 0,
};

pub fn cell_at(game: *GameState, position: u32_2) *CellState {
    const flat_index = position[0] + game.extent * position[1];
    return &game.board[flat_index];
}

// Creates blank board without mines.
// Placement of mines is done on the first player input.
pub fn create_game_state(allocator: std.mem.Allocator, box_w: u32, box_h: u32, seed: u64) !GameState {
    const extent = box_w * box_h;
    const cell_count = extent * extent;

    // Allocate board
    const board = try allocator.alloc(CellState, cell_count);
    errdefer allocator.free(board);

    for (board) |*cell| {
        cell.* = .{};
    }

    // Allocate history stack
    const history = try allocator.alloc(CellState, cell_count * MaxHistorySize);
    errdefer allocator.free(history);

    const col_regions = try allocator.alloc(u32_2, cell_count);
    errdefer allocator.free(col_regions);

    const row_regions = try allocator.alloc(u32_2, cell_count);
    errdefer allocator.free(row_regions);

    const box_regions = try allocator.alloc(u32_2, cell_count);
    errdefer allocator.free(box_regions);

    fill_regions(extent, box_w, box_h, col_regions, row_regions, box_regions);

    return GameState{
        .extent = extent,
        .box_w = box_w,
        .box_h = box_h,
        .rng = std.rand.Xoroshiro128.init(seed),
        .board = board,
        .col_regions = col_regions,
        .row_regions = row_regions,
        .box_regions = box_regions,
        .history = history,
        .selected_cell = u32_2{ extent, extent }, // Invalid value
    };
}

pub fn destroy_game_state(allocator: std.mem.Allocator, game: *GameState) void {
    allocator.free(game.col_regions);
    allocator.free(game.row_regions);
    allocator.free(game.box_regions);
    allocator.free(game.history);
    allocator.free(game.board);
}

fn fill_regions(extent: u32, box_w: u32, box_h: u32, col_regions: []u32_2, row_regions: []u32_2, box_regions: []u32_2) void {
    for (range(extent)) |_, region_index_usize| {
        const slice_start = region_index_usize * extent;
        const slice_end = slice_start + extent;

        var col_region = col_regions[slice_start..slice_end];
        var row_region = row_regions[slice_start..slice_end];
        var box_region = box_regions[slice_start..slice_end];

        assert(col_region.len == extent);

        const region_index = @intCast(u32, region_index_usize);
        const box_cell_offset_x = (region_index % box_h) * box_w;
        const box_cell_offset_y = (region_index / box_h) * box_h;

        for (range(extent)) |_, i| {
            col_region[i] = .{ @intCast(u32, region_index), @intCast(u32, i) };
            row_region[i] = .{ @intCast(u32, i), @intCast(u32, region_index) };

            const col_index = box_cell_offset_x + @intCast(u32, i) % box_w;
            const row_index = box_cell_offset_y + @intCast(u32, i) / box_w;
            box_region[i] = .{ col_index, row_index };
        }
    }
}

pub fn start_game(game: *GameState) void {
    fill_dummy_board(game);
    //fill_dummy_airplane_board(game);
    //fill_magic_board(game);
    fill_hints(game);

    // The history should contain the initial state to function correctly
    std.mem.copy(CellState, get_history_slice(game, 0), game.board);
}

pub fn player_select(game: *GameState, select_pos: u32_2) void {
    assert(all(select_pos < u32_2{ game.extent, game.extent }));

    game.selected_cell = select_pos;
}

pub fn player_input_number(game: *GameState, number_index: u5) void {
    if (all(game.selected_cell < u32_2{ game.extent, game.extent })) {
        place_number_remove_trivial_candidates(game, game.selected_cell, number_index);
    }
}

pub fn player_toggle_guess(game: *GameState, number_index: u5) void {
    if (all(game.selected_cell < u32_2{ game.extent, game.extent })) {
        var cell = cell_at(game, game.selected_cell);

        if (cell.set_number == 0) {
            const mask = @intCast(u9, @as(u32, 1) << number_index); // FIXME proper way of enforcing this?
            cell.hint_mask ^= mask;
        }

        push_state_to_history(game);
    }
}

fn place_number(game: *GameState, coord: u32_2, number_index: u5) void {
    var cell = cell_at(game, coord);

    cell.set_number = number_index + 1;
    cell.hint_mask = @intCast(u9, @as(u32, 1) << number_index);

    push_state_to_history(game);
}

fn remove_trivial_candidates(game: *GameState, coord: u32_2, number_index: u5) void {
    const box_x = (coord[0] / game.box_w);
    const box_y = (coord[1] / game.box_h);

    const col_start = game.extent * coord[0];
    const row_start = game.extent * coord[1];
    const box_start = game.extent * (box_x + box_y * game.box_h);

    const col_region = game.col_regions[col_start .. col_start + game.extent];
    const row_region = game.row_regions[row_start .. row_start + game.extent];
    const box_region = game.box_regions[box_start .. box_start + game.extent];

    const mask = @intCast(u9, @as(u32, 1) << number_index);

    for (range(game.extent)) |_, i| {
        cell_at(game, col_region[i]).hint_mask &= ~mask;
        cell_at(game, row_region[i]).hint_mask &= ~mask;
        cell_at(game, box_region[i]).hint_mask &= ~mask;
    }
}

fn place_number_remove_trivial_candidates(game: *GameState, coord: u32_2, number_index: u5) void {
    remove_trivial_candidates(game, coord, number_index);
    place_number(game, coord, number_index);
}

pub fn solve_basic_rules(game: *GameState) void {
    for (range(game.extent)) |_, region_index_usize| {
        const slice_start = region_index_usize * game.extent;
        const slice_end = slice_start + game.extent;

        const col_region = game.col_regions[slice_start..slice_end];
        const row_region = game.row_regions[slice_start..slice_end];
        const box_region = game.box_regions[slice_start..slice_end];

        solve_eliminate_candidate_region(game, col_region);
        solve_eliminate_candidate_region(game, row_region);
        solve_eliminate_candidate_region(game, box_region);
    }

    // If there's a cell with a single possibility left, put it down
    for (game.board) |cell, flat_index| {
        const index = flat_index_to_2d(game.extent, flat_index);

        if (cell.set_number == 0 and count_bits(cell.hint_mask) == 1) {
            place_number_remove_trivial_candidates(game, index, @intCast(u5, first_bit_index(cell.hint_mask)));
        }
    }

    push_state_to_history(game);
}

fn solve_eliminate_candidate_region(game: *GameState, region: []u32_2) void {
    assert(region.len == game.extent);
    var used_mask: u9 = EmptyHintMask;

    for (region) |cell_coord| {
        const cell = cell_at(game, cell_coord);

        if (cell.set_number != 0) {
            const mask = @intCast(u9, @as(u32, 1) << (cell.set_number - 1));
            used_mask |= mask;
        }
    }

    for (region) |cell_coord| {
        const cell = cell_at(game, cell_coord);

        if (cell.set_number == 0) {
            cell.hint_mask &= ~used_mask;
        }
    }
}

pub fn solve_extra(game: *GameState) void {
    for (range(game.extent)) |_, region_index_usize| {
        const slice_start = region_index_usize * game.extent;
        const slice_end = slice_start + game.extent;

        const col_region = game.col_regions[slice_start..slice_end];
        const row_region = game.row_regions[slice_start..slice_end];
        const box_region = game.box_regions[slice_start..slice_end];

        solve_find_unique_candidate(game, col_region);
        solve_find_unique_candidate(game, row_region);
        solve_find_unique_candidate(game, box_region);
    }

    push_state_to_history(game);
}

// If there's a region (col/row/box) where a possibility appears only once, put it down
fn solve_find_unique_candidate(game: *GameState, region: []u32_2) void {
    assert(region.len == game.extent);
    assert(game.extent == 9);

    var counts = std.mem.zeroes([9]u32);
    var last_occurences: [9]u32_2 = undefined;

    for (region) |cell_coord| {
        const cell = cell_at(game, cell_coord);

        var mask = cell.hint_mask;

        for (range(game.extent)) |_, number_index| {
            if ((mask & 1) != 0) {
                counts[number_index] += 1;
                last_occurences[number_index] = cell_coord;
            }
            mask >>= 1;
        }
    }

    for (counts) |count, number_index| {
        if (count == 1) {
            const coords = last_occurences[number_index];
            var cell = cell_at(game, coords);

            if (cell.set_number == 0) {
                place_number_remove_trivial_candidates(game, coords, @intCast(u5, number_index));
            }
        }
    }
}

fn get_history_slice(game: *GameState, history_index: u32) []CellState {
    const cell_count = game.extent * game.extent;
    const start = cell_count * history_index;
    const stop = start + cell_count;

    return game.history[start..stop];
}

pub fn player_undo(game: *GameState) void {
    if (game.history_index > 0) {
        game.history_index -= 1;

        load_state_from_history(game, game.history_index);
    }
}

pub fn player_redo(game: *GameState) void {
    if (game.history_index < game.max_history_index) {
        game.history_index += 1;

        load_state_from_history(game, game.history_index);
    }
}

fn push_state_to_history(game: *GameState) void {
    if (game.history_index + 1 < MaxHistorySize) {
        game.history_index += 1;
        game.max_history_index = game.history_index;

        std.mem.copy(CellState, get_history_slice(game, game.history_index), game.board);
    }
}

fn load_state_from_history(game: *GameState, index: u32) void {
    std.mem.copy(CellState, game.board, get_history_slice(game, index));
}

fn fill_hints(game: *GameState) void {
    // Prepare hint mask for the solver
    for (game.board) |*cell| {
        if (cell.set_number != 0) {
            const mask = @intCast(u9, @as(u32, 1) << (cell.set_number - 1)); // FIXME proper way of enforcing this?
            cell.hint_mask = mask;
        } else {
            cell.hint_mask = @intCast(u9, (@as(u32, 1) << @intCast(u5, game.extent)) - 1);
        }
    }
}

fn fill_dummy_board(game: *GameState) void {
    cell_at(game, .{ 3, 0 }).set_number = 8;

    cell_at(game, .{ 0, 1 }).set_number = 4;
    cell_at(game, .{ 4, 1 }).set_number = 1;
    cell_at(game, .{ 5, 1 }).set_number = 5;
    cell_at(game, .{ 7, 1 }).set_number = 3;

    cell_at(game, .{ 1, 2 }).set_number = 2;
    cell_at(game, .{ 2, 2 }).set_number = 9;
    cell_at(game, .{ 4, 2 }).set_number = 4;
    cell_at(game, .{ 6, 2 }).set_number = 5;
    cell_at(game, .{ 7, 2 }).set_number = 1;
    cell_at(game, .{ 8, 2 }).set_number = 8;

    cell_at(game, .{ 1, 3 }).set_number = 4;
    cell_at(game, .{ 6, 3 }).set_number = 1;
    cell_at(game, .{ 7, 3 }).set_number = 2;

    cell_at(game, .{ 3, 4 }).set_number = 6;
    cell_at(game, .{ 5, 4 }).set_number = 2;

    cell_at(game, .{ 1, 5 }).set_number = 3;
    cell_at(game, .{ 2, 5 }).set_number = 2;
    cell_at(game, .{ 7, 5 }).set_number = 9;

    cell_at(game, .{ 0, 6 }).set_number = 6;
    cell_at(game, .{ 1, 6 }).set_number = 9;
    cell_at(game, .{ 2, 6 }).set_number = 3;
    cell_at(game, .{ 4, 6 }).set_number = 5;
    cell_at(game, .{ 6, 6 }).set_number = 8;
    cell_at(game, .{ 7, 6 }).set_number = 7;

    cell_at(game, .{ 1, 7 }).set_number = 5;
    cell_at(game, .{ 3, 7 }).set_number = 4;
    cell_at(game, .{ 4, 7 }).set_number = 8;
    cell_at(game, .{ 8, 7 }).set_number = 1;

    cell_at(game, .{ 5, 8 }).set_number = 3;
}

fn fill_dummy_airplane_board(game: *GameState) void {
    cell_at(game, .{ 0, 0 }).set_number = 6;
    cell_at(game, .{ 2, 0 }).set_number = 9;
    cell_at(game, .{ 7, 0 }).set_number = 3;

    cell_at(game, .{ 0, 1 }).set_number = 7;
    cell_at(game, .{ 2, 1 }).set_number = 3;
    cell_at(game, .{ 5, 1 }).set_number = 4;
    cell_at(game, .{ 7, 1 }).set_number = 9;

    cell_at(game, .{ 2, 2 }).set_number = 4;
    cell_at(game, .{ 3, 2 }).set_number = 2;
    cell_at(game, .{ 5, 2 }).set_number = 9;
    cell_at(game, .{ 7, 2 }).set_number = 7;

    cell_at(game, .{ 0, 3 }).set_number = 2;
    cell_at(game, .{ 1, 3 }).set_number = 8;
    cell_at(game, .{ 2, 3 }).set_number = 7;
    cell_at(game, .{ 5, 3 }).set_number = 3;

    cell_at(game, .{ 6, 4 }).set_number = 3;

    cell_at(game, .{ 3, 5 }).set_number = 9;
    cell_at(game, .{ 6, 5 }).set_number = 1;
    cell_at(game, .{ 7, 5 }).set_number = 8;
    cell_at(game, .{ 8, 5 }).set_number = 7;

    cell_at(game, .{ 1, 6 }).set_number = 4;
    cell_at(game, .{ 3, 6 }).set_number = 8;
    cell_at(game, .{ 5, 6 }).set_number = 5;
    cell_at(game, .{ 6, 6 }).set_number = 7;

    cell_at(game, .{ 1, 7 }).set_number = 7;
    cell_at(game, .{ 3, 7 }).set_number = 1;
    cell_at(game, .{ 6, 7 }).set_number = 4;
    cell_at(game, .{ 8, 7 }).set_number = 3;

    cell_at(game, .{ 1, 8 }).set_number = 6;
    cell_at(game, .{ 6, 8 }).set_number = 5;
    cell_at(game, .{ 8, 8 }).set_number = 8;
}

fn fill_magic_board(game: *GameState) void {
    cell_at(game, .{ 4, 2 }).set_number = 4;
    cell_at(game, .{ 2, 3 }).set_number = 3;
}
