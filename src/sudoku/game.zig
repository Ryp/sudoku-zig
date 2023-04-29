const std = @import("std");
const assert = std.debug.assert;

const event = @import("event.zig");
const GameEvent = event.GameEvent;
const GameResult = event.GameResult;

pub const @"u16_2" = std.meta.Vector(2, u16);
pub const @"i16_2" = std.meta.Vector(2, i16);
pub const @"u32_2" = std.meta.Vector(2, u32);

const FullHintMask = 0b111111111;
const EmptyHintMask = 0b000000000;

const box_offset_table = [9]u32_2{
    .{ 0, 0 },
    .{ 1, 0 },
    .{ 2, 0 },
    .{ 0, 1 },
    .{ 1, 1 },
    .{ 2, 1 },
    .{ 0, 2 },
    .{ 1, 2 },
    .{ 2, 2 },
};

pub const CellState = struct {
    set_number: u5 = 0,
    hint_mask: u9 = 0,
};

pub const GameState = struct {
    extent: u32_2,
    board: [][]CellState,
    selected_cell: u16_2,
    rng: std.rand.Xoroshiro128, // Hardcode PRNG type for forward compatibility

    // Storage for game events
    event_history: []GameEvent,
    event_history_index: usize = 0,
    children_array: []u16_2,
    children_array_index: usize = 0,
};

pub fn range(len: usize) []const void {
    return @as([*]void, undefined)[0..len];
}

pub fn cell_at(game: *GameState, position: u32_2) *CellState {
    return &game.board[position[0]][position[1]];
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

pub fn fill_dummy_board(game: *GameState) void {
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

pub fn fill_dummy_airplane_board(game: *GameState) void {
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

pub fn fill_hints(game: *GameState) void {
    // Prepare hint mask for the solver
    for (game.board) |column| {
        for (column) |*cell| {
            if (cell.set_number != 0) {
                const mask = @intCast(u9, @as(u32, 1) << (cell.set_number - 1)); // FIXME proper way of enforcing this?
                cell.hint_mask = mask;
            } else {
                cell.hint_mask = FullHintMask;
            }
        }
    }
}

// Creates blank board without mines.
// Placement of mines is done on the first player input.
pub fn create_game_state(allocator: std.mem.Allocator, extent: u32_2, seed: u64) !GameState {
    const cell_count = extent[0] * extent[1];

    // Allocate board
    const board = try allocator.alloc([]CellState, extent[0]);
    errdefer allocator.free(board);

    for (board) |*column| {
        column.* = try allocator.alloc(CellState, extent[1]);
        errdefer allocator.free(column);

        for (column.*) |*cell| {
            cell.* = .{};
        }
    }

    // Allocate array to hold events
    const max_events = cell_count + 2000;

    const event_history = try allocator.alloc(GameEvent, max_events);
    errdefer allocator.free(event_history);

    // Allocate array to hold cells discovered in events
    const children_array = try allocator.alloc(u16_2, cell_count);
    errdefer allocator.free(children_array);

    return GameState{
        .extent = extent,
        .rng = std.rand.Xoroshiro128.init(seed),
        .board = board,
        .selected_cell = u16_2{ 9, 9 },
        .event_history = event_history,
        .children_array = children_array,
    };
}

pub fn destroy_game_state(allocator: std.mem.Allocator, game: *GameState) void {
    allocator.free(game.children_array);
    allocator.free(game.event_history);

    for (game.board) |column| {
        allocator.free(column);
    }

    allocator.free(game.board);
}

pub fn select(game: *GameState, select_pos: u16_2) void {
    assert(all(select_pos < @intCast(u16_2, game.extent)));

    game.selected_cell = select_pos;
}

pub fn input_number(game: *GameState, number_index: u5) void {
    assert(all(game.selected_cell < @intCast(u16_2, game.extent)));

    place_number_remove_trivial_candidates(game, game.selected_cell, number_index);
}

pub fn toggle_guess(game: *GameState, number_index: u5) void {
    assert(all(game.selected_cell < @intCast(u16_2, game.extent)));

    var cell = cell_at(game, game.selected_cell);

    if (cell.set_number == 0) {
        const mask = @intCast(u9, @as(u32, 1) << number_index); // FIXME proper way of enforcing this?
        cell.hint_mask ^= mask;
    }
}

pub fn solve_extra(game: *GameState) void {
    for (range(9)) |_, region_index_usize| {
        const region_index = @intCast(u32, region_index_usize);
        var col_region: [9]u32_2 = undefined;
        var row_region: [9]u32_2 = undefined;
        var box_region: [9]u32_2 = undefined;

        const box_cell_offset_x = (region_index % 3) * 3;
        const box_cell_offset_y = (region_index / 3) * 3;

        for (range(9)) |_, i| {
            col_region[i] = .{ @intCast(u32, region_index), @intCast(u32, i) };
            row_region[i] = .{ @intCast(u32, i), @intCast(u32, region_index) };

            const col_index = box_cell_offset_x + box_offset_table[i][0];
            const row_index = box_cell_offset_y + box_offset_table[i][1];
            box_region[i] = .{ col_index, row_index };
        }

        solve_find_unique_candidate(game, &col_region);
        solve_find_unique_candidate(game, &row_region);
        solve_find_unique_candidate(game, &box_region);
    }
}

fn solve_eliminate_candidate_region(game: *GameState, regions: []u32_2) void {
    assert(regions.len == 9);
    var used_mask: u9 = EmptyHintMask;

    for (regions) |region| {
        const cell = cell_at(game, region);

        if (cell.set_number != 0) {
            const mask = @intCast(u9, @as(u32, 1) << (cell.set_number - 1));
            used_mask |= mask;
        }
    }

    for (regions) |region| {
        const cell = cell_at(game, region);

        if (cell.set_number == 0) {
            cell.hint_mask &= ~used_mask;
        }
    }
}

fn place_number(game: *GameState, coord: u32_2, number_index: u5) void {
    var cell = cell_at(game, coord);

    cell.set_number = number_index + 1;
    cell.hint_mask = @intCast(u9, @as(u32, 1) << number_index);
}

fn remove_trivial_candidates(game: *GameState, coord: u32_2, number_index: u5) void {
    const mask = @intCast(u9, @as(u32, 1) << number_index);

    const box_cell_offset_x = (coord[0] / 3) * 3;
    const box_cell_offset_y = (coord[1] / 3) * 3;

    for (range(9)) |_, i| {
        const box_col_index = box_cell_offset_x + box_offset_table[i][0];
        const box_row_index = box_cell_offset_y + box_offset_table[i][1];

        var col_cell = cell_at(game, .{ coord[0], @intCast(u32, i) });
        var row_cell = cell_at(game, .{ @intCast(u32, i), coord[1] });
        var box_cell = cell_at(game, .{ box_col_index, box_row_index });

        col_cell.hint_mask &= ~mask;
        row_cell.hint_mask &= ~mask;
        box_cell.hint_mask &= ~mask;
    }
}

fn place_number_remove_trivial_candidates(game: *GameState, coord: u32_2, number_index: u5) void {
    place_number(game, coord, number_index);
    remove_trivial_candidates(game, coord, number_index);
}

// If there's a region (col/row/box) where a possibility appears only once, put it down
fn solve_find_unique_candidate(game: *GameState, regions: []u32_2) void {
    assert(regions.len == 9);

    var counts = std.mem.zeroes([9]u32);
    var last_occurences: [9]u32_2 = undefined;

    for (regions) |cell_coord| {
        const cell = cell_at(game, cell_coord);

        var mask = cell.hint_mask;

        for (range(9)) |_, number_index| {
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

pub fn solve_basic_rules(game: *GameState) void {
    for (range(9)) |_, region_index_usize| {
        const region_index = @intCast(u32, region_index_usize);
        var col_region: [9]u32_2 = undefined;
        var row_region: [9]u32_2 = undefined;
        var box_region: [9]u32_2 = undefined;

        const box_cell_offset_x = (region_index % 3) * 3;
        const box_cell_offset_y = (region_index / 3) * 3;

        for (range(9)) |_, i| {
            col_region[i] = .{ @intCast(u32, region_index), @intCast(u32, i) };
            row_region[i] = .{ @intCast(u32, i), @intCast(u32, region_index) };

            const col_index = box_cell_offset_x + box_offset_table[i][0];
            const row_index = box_cell_offset_y + box_offset_table[i][1];
            box_region[i] = .{ col_index, row_index };
        }

        solve_eliminate_candidate_region(game, &col_region);
        solve_eliminate_candidate_region(game, &row_region);
        solve_eliminate_candidate_region(game, &box_region);
    }

    // If there's a cell with a single possibility left, put it down
    for (game.board) |column, i| {
        for (column) |*cell, j| {
            if (cell.set_number == 0 and count_bits(cell.hint_mask) == 1) {
                place_number_remove_trivial_candidates(game, .{ @intCast(u32, i), @intCast(u32, j) }, @intCast(u5, first_bit_index(cell.hint_mask)));
            }
        }
    }
}
