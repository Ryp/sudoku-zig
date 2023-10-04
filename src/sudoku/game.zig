const std = @import("std");
const assert = std.debug.assert;

const generator = @import("generator.zig");
const brute_solver = @import("brute_solver.zig");
const solver = @import("solver.zig");
const event = @import("event.zig");
const SolverEvent = event.SolverEvent;

// I borrowed this name from HLSL
pub fn all(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.Vector.child == bool);
    assert(type_info.Vector.len > 1);

    return @reduce(.And, vector);
}

pub const u32_2 = @Vector(2, u32);

pub fn flat_index_to_2d(extent: u32, flat_index: usize) u32_2 {
    const x: u32 = @intCast(flat_index % extent);
    const y: u32 = @intCast(flat_index / extent);

    return .{ x, y };
}

pub const MaxSudokuExtent = 16;
pub const UnsetNumber: u5 = 0x1F;
const MaxHistorySize = 512;

pub const CellState = struct {
    number: u5 = UnsetNumber,
    hint_mask: u16 = 0,
};

pub const GameState = struct {
    extent: u32,
    box_w: u32,
    box_h: u32,
    board: []CellState,
    selected_cell: u32_2,

    region_offsets: []u32_2,
    all_regions: [][]u32_2,
    col_regions: [][]u32_2,
    row_regions: [][]u32_2,
    box_regions: [][]u32_2,

    history: []CellState,
    history_index: u32 = 0,
    max_history_index: u32 = 0,

    solver_events: []SolverEvent,
    solver_event_index: u32 = 0,
};

pub fn cell_at(game: *GameState, position: u32_2) *CellState {
    const flat_index = position[0] + game.extent * position[1];
    return &game.board[flat_index];
}

pub fn box_coord_from_cell(game: *GameState, cell_coord: u32_2) u32_2 {
    const x = (cell_coord[0] / game.box_w);
    const y = (cell_coord[1] / game.box_h);

    return .{ x, y };
}

pub fn box_index_from_cell(game: *GameState, cell_coord: u32_2) u32 {
    const box_coord = box_coord_from_cell(game, cell_coord);

    return box_coord[0] + box_coord[1] * game.box_h;
}

pub fn mask_for_number(number: u4) u16 {
    return @as(u16, 1) << number;
}

pub fn full_hint_mask(game_extent: u32) u16 {
    return @intCast((@as(u32, 1) << @intCast(game_extent)) - 1);
}

pub fn create_game_state(allocator: std.mem.Allocator, box_w: u32, box_h: u32) !GameState {
    const extent = box_w * box_h;
    const cell_count = extent * extent;

    assert(extent > 1);
    assert(extent <= MaxSudokuExtent);

    // Allocate board
    const board = try allocator.alloc(CellState, cell_count);
    errdefer allocator.free(board);

    for (board) |*cell| {
        cell.* = .{};
    }

    // Allocate history stack
    const history = try allocator.alloc(CellState, cell_count * MaxHistorySize);
    errdefer allocator.free(history);

    const region_offsets = try allocator.alloc(u32_2, cell_count * 3);
    errdefer allocator.free(region_offsets);

    const all_regions = try allocator.alloc([]u32_2, extent * 3);
    errdefer allocator.free(all_regions);

    // Map regions to raw offset slices
    for (all_regions, 0..) |*region, region_index| {
        const slice_start = region_index * extent;

        region.* = region_offsets[slice_start .. slice_start + extent];
    }

    const col_regions = all_regions[0 * extent .. 1 * extent];
    const row_regions = all_regions[1 * extent .. 2 * extent];
    const box_regions = all_regions[2 * extent .. 3 * extent];

    fill_regions(extent, box_w, box_h, col_regions, row_regions, box_regions);

    const solver_events = try allocator.alloc(SolverEvent, cell_count * extent);
    errdefer allocator.free(solver_events);

    return GameState{
        .extent = extent,
        .box_w = box_w,
        .box_h = box_h,
        .board = board,
        .region_offsets = region_offsets,
        .all_regions = all_regions,
        .col_regions = col_regions,
        .row_regions = row_regions,
        .box_regions = box_regions,
        .history = history,
        .selected_cell = u32_2{ extent, extent }, // Invalid value
        .solver_events = solver_events,
    };
}

pub fn destroy_game_state(allocator: std.mem.Allocator, game: *GameState) void {
    allocator.free(game.solver_events);
    allocator.free(game.all_regions);
    allocator.free(game.region_offsets);
    allocator.free(game.history);
    allocator.free(game.board);
}

fn fill_regions(extent: u32, box_w: u32, box_h: u32, col_regions: [][]u32_2, row_regions: [][]u32_2, box_regions: [][]u32_2) void {
    for (0..extent) |region_index_usize| {
        var col_region = col_regions[region_index_usize];
        var row_region = row_regions[region_index_usize];
        var box_region = box_regions[region_index_usize];

        assert(col_region.len == extent);

        const region_index: u32 = @intCast(region_index_usize);
        const box_cell_offset_x = (region_index % box_h) * box_w;
        const box_cell_offset_y = (region_index / box_h) * box_h;

        for (col_region, row_region, box_region, 0..) |*col_cell, *row_cell, *box_cell, cell_index_usize| {
            const cell_index: u32 = @intCast(cell_index_usize);
            col_cell.* = .{ region_index, cell_index };
            row_cell.* = .{ cell_index, region_index };

            const box_col_index: u32 = box_cell_offset_x + cell_index % box_w;
            const box_row_index: u32 = box_cell_offset_y + cell_index / box_w;
            box_cell.* = .{ box_col_index, box_row_index };
        }
    }
}

pub fn fill_from_string(game: *GameState, str: []u8) void {
    assert(str.len == game.extent * game.extent);

    for (game.board, str) |*cell, char| {
        var number: u8 = UnsetNumber;

        if (char >= '1' and char <= '9') {
            number = char - '1';
        } else if (char >= 'A' and char <= 'G') {
            number = char - 'A' + 9;
        } else if (char >= 'a' and char <= 'g') {
            number = char - 'a' + 9;
        }

        assert(number < game.extent or number == UnsetNumber);

        cell.number = @intCast(number);
    }
}

pub fn fill_from_generator(game: *GameState) void {
    generator.generate_dumb_grid(game);
}

pub fn start_game(game: *GameState) void {
    // The history should contain the initial state to function correctly
    std.mem.copy(CellState, get_history_slice(game, 0), game.board);
}

pub fn player_toggle_select(game: *GameState, select_pos: u32_2) void {
    assert(all(select_pos < u32_2{ game.extent, game.extent }));

    if (all(select_pos == game.selected_cell)) {
        game.selected_cell = .{ game.extent, game.extent };
    } else {
        game.selected_cell = select_pos;
    }
}

pub fn player_clear_number(game: *GameState) void {
    if (all(game.selected_cell < u32_2{ game.extent, game.extent })) {
        var cell = cell_at(game, game.selected_cell);
        cell.number = UnsetNumber;
        cell.hint_mask = 0;

        push_state_to_history(game);
    }
}

pub fn player_input_number(game: *GameState, number: u4) void {
    if (number < game.extent and all(game.selected_cell < u32_2{ game.extent, game.extent })) {
        place_number_remove_trivial_candidates(game, game.selected_cell, number);
        push_state_to_history(game);
    }
}

pub fn player_toggle_guess(game: *GameState, number: u4) void {
    if (number < game.extent and all(game.selected_cell < u32_2{ game.extent, game.extent })) {
        var cell = cell_at(game, game.selected_cell);

        if (cell.number == UnsetNumber) {
            cell.hint_mask ^= mask_for_number(number);
        }

        push_state_to_history(game);
    }
}

pub fn place_number(cell: *CellState, number: u4) void {
    cell.number = number;
    cell.hint_mask = mask_for_number(number);
}

pub fn place_number_remove_trivial_candidates(game: *GameState, coord: u32_2, number: u4) void {
    var cell = cell_at(game, coord);

    place_number(cell, number);
    solver.solve_trivial_candidates_at(game, coord, number);
}

// FIXME We need a good way to communicate this to the user
pub fn player_solve_human_step(game: *GameState) void {
    solver.solve_trivial_candidates(game);
    solver.solve_naked_singles(game);
    solver.solve_hidden_singles(game);
    solver.solve_hidden_pairs(game);
    solver.solve_pointing_lines(game);

    push_state_to_history(game);
}

pub fn player_solve_brute_force(game: *GameState) void {
    if (brute_solver.solve(game)) {
        push_state_to_history(game);
    } else {
        // We didn't manage to solve the puzzle
        // FIXME Tell the player somehow
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

pub fn player_fill_hints(game: *GameState) void {
    // Prepare hint mask for the solver
    for (game.board) |*cell| {
        if (cell.number != UnsetNumber) {
            cell.hint_mask = mask_for_number(@intCast(cell.number));
        } else {
            cell.hint_mask = full_hint_mask(game.extent);
        }
    }

    for (game.board, 0..) |*cell, flat_index| {
        if (cell.number != UnsetNumber) {
            const index = flat_index_to_2d(game.extent, flat_index);
            place_number_remove_trivial_candidates(game, index, @intCast(cell.number));
        }
    }

    push_state_to_history(game);
}

pub fn player_clear_hints(game: *GameState) void {
    for (game.board) |*cell| {
        cell.hint_mask = 0;
    }

    push_state_to_history(game);
}
