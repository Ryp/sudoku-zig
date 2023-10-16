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

pub const RegularSudoku = struct {
    box_w: u32,
    box_h: u32,
};

pub const SquigglySudoku = struct {
    size: u32,
    box_indices_string: []const u8,
};

pub const GameTypeTag = enum {
    regular,
    squiggly,
};

pub const GameType = union(GameTypeTag) {
    regular: RegularSudoku,
    squiggly: SquigglySudoku,
};

pub const GameState = struct {
    extent: u32,
    game_type: GameType,
    board: []CellState,
    selected_cell: u32_2,

    region_offsets: []u32_2,
    all_regions: [][]u32_2,
    col_regions: [][]u32_2,
    row_regions: [][]u32_2,
    box_regions: [][]u32_2,
    box_indices: []u4,

    history: []CellState,
    history_index: u32 = 0,
    max_history_index: u32 = 0,

    solver_events: []SolverEvent,
    solver_event_index: u32 = 0,
};

pub fn get_flat_index(extent: u32, position: u32_2) u32 // FIXME flatten all?
{
    return position[0] + extent * position[1];
}

pub fn cell_at(game: *GameState, position: u32_2) *CellState {
    const flat_index = get_flat_index(game.extent, position);
    return &game.board[flat_index];
}

pub fn box_index_from_cell(game: *GameState, cell_coord: u32_2) u32 {
    assert(all(cell_coord < u32_2{ game.extent, game.extent }));

    const flat_index = get_flat_index(game.extent, cell_coord);
    return game.box_indices[flat_index];
}

pub fn mask_for_number(number: u4) u16 {
    return @as(u16, 1) << number;
}

pub fn full_hint_mask(game_extent: u32) u16 {
    return @intCast((@as(u32, 1) << @intCast(game_extent)) - 1);
}

pub fn create_game_state(allocator: std.mem.Allocator, game_type: GameType, sudoku_string: []const u8) !GameState {
    const extent = switch (game_type) {
        .regular => |regular| regular.box_w * regular.box_h,
        .squiggly => |squiggly| squiggly.size,
    };
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

    const box_indices = try allocator.alloc(u4, cell_count);
    errdefer allocator.free(box_indices);

    switch (game_type) {
        .regular => |regular| {
            fill_region_indices_regular(box_indices, extent, regular.box_w, regular.box_h);
        },
        .squiggly => |squiggly| {
            fill_region_indices_from_string(box_indices, squiggly.box_indices_string, extent);
        },
    }

    // Map regions to raw offset slices
    for (all_regions, 0..) |*region, region_index| {
        const slice_start = region_index * extent;

        region.* = region_offsets[slice_start .. slice_start + extent];
    }

    const col_regions = all_regions[0 * extent .. 1 * extent];
    const row_regions = all_regions[1 * extent .. 2 * extent];
    const box_regions = all_regions[2 * extent .. 3 * extent];

    fill_regions(extent, col_regions, row_regions, box_regions, box_indices);

    const solver_events = try allocator.alloc(SolverEvent, cell_count * extent);
    errdefer allocator.free(solver_events);

    var game = GameState{
        .extent = extent,
        .game_type = game_type,
        .board = board,
        .region_offsets = region_offsets,
        .all_regions = all_regions,
        .col_regions = col_regions,
        .row_regions = row_regions,
        .box_regions = box_regions,
        .box_indices = box_indices,
        .history = history,
        .selected_cell = u32_2{ extent, extent }, // Invalid value
        .solver_events = solver_events,
    };

    if (sudoku_string.len == 0) {
        generator.generate_dumb_board(&game);
    } else {
        fill_board_from_string(&game, sudoku_string);
    }

    // The history should contain the initial state to function correctly
    std.mem.copy(CellState, get_history_slice(&game, 0), game.board);

    return game;
}

pub fn destroy_game_state(allocator: std.mem.Allocator, game: *GameState) void {
    allocator.free(game.solver_events);
    allocator.free(game.box_indices);
    allocator.free(game.all_regions);
    allocator.free(game.region_offsets);
    allocator.free(game.history);
    allocator.free(game.board);
}

fn fill_regions(extent: u32, col_regions: [][]u32_2, row_regions: [][]u32_2, box_regions: [][]u32_2, box_indices: []const u4) void {
    for (0..extent) |region_index_usize| {
        var col_region = col_regions[region_index_usize];
        var row_region = row_regions[region_index_usize];

        assert(col_region.len == extent);
        assert(row_region.len == extent);

        const region_index: u32 = @intCast(region_index_usize);

        for (col_region, row_region, 0..) |*col_cell, *row_cell, cell_index_usize| {
            const cell_index: u32 = @intCast(cell_index_usize);
            col_cell.* = .{ region_index, cell_index };
            row_cell.* = .{ cell_index, region_index };
        }
    }

    var region_slot_full = std.mem.zeroes([MaxSudokuExtent]u32);
    var region_slot = region_slot_full[0..extent];

    for (box_indices, 0..) |box_index, flat_index| {
        const slot = region_slot[box_index];

        var box_region = box_regions[box_index];
        box_region[slot] = flat_index_to_2d(extent, flat_index);

        region_slot[box_index] += 1;
    }

    for (region_slot) |slot| {
        assert(slot == extent);
    }
}

fn fill_board_from_string(game: *GameState, sudoku_string: []const u8) void {
    assert(sudoku_string.len == game.extent * game.extent);

    for (game.board, sudoku_string) |*cell, char| {
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

fn fill_region_indices_regular(box_indices: []u4, extent: u32, box_w: u32, box_h: u32) void {
    for (box_indices, 0..) |*box_index, i| {
        const cell_coord = flat_index_to_2d(extent, i);
        const box_coord_x = (cell_coord[0] / box_w);
        const box_coord_y = (cell_coord[1] / box_h);

        box_index.* = @intCast(box_coord_x + box_coord_y * box_h);
    }
}

fn fill_region_indices_from_string(box_indices: []u4, box_indices_string: []const u8, extent: u32) void {
    assert(box_indices_string.len == extent * extent);

    var region_sizes_full = std.mem.zeroes([MaxSudokuExtent]u32);
    var region_sizes = region_sizes_full[0..extent];

    for (box_indices, box_indices_string) |*box_index, char| {
        var number: u8 = undefined;

        if (char >= '1' and char <= '9') {
            number = char - '1';
        } else if (char >= 'A' and char <= 'G') {
            number = char - 'A' + 9;
        } else if (char >= 'a' and char <= 'g') {
            number = char - 'a' + 9;
        }

        assert(number < extent);

        box_index.* = @intCast(number);

        region_sizes[number] += 1;
    }

    for (region_sizes) |region_size| {
        assert(region_size == extent);
    }
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
    if (brute_solver.solve(game, .{})) {
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
