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

pub const MaxSudokuExtent = 16;
pub const UnsetNumber: u5 = 0x1F;
const MaxHistorySize = 512;

pub const RegularSudoku = struct {
    box_w: u32,
    box_h: u32,
};

pub const JigsawSudoku = struct {
    size: u32,
    box_indices_string: []const u8,
};

pub const GameTypeTag = enum {
    regular,
    jigsaw,
};

pub const GameType = union(GameTypeTag) {
    regular: RegularSudoku,
    jigsaw: JigsawSudoku,
};

pub const GameState = struct {
    extent: u32,
    game_type: GameType,
    board: []u5,
    candidate_masks: []u16,
    selected_cell: u32_2,

    region_offsets: []u32,
    all_regions: [][]u32,
    col_regions: [][]u32,
    row_regions: [][]u32,
    box_regions: [][]u32,
    box_indices: []u4,

    board_history: []u5,
    candidate_masks_history: []u16,
    history_index: u32 = 0,
    max_history_index: u32 = 0,

    solver_events: []SolverEvent,
    solver_event_index: u32 = 0,
};

pub fn cell_coord_from_index(extent: u32, cell_index: usize) u32_2 {
    const x: u32 = @intCast(cell_index % extent);
    const y: u32 = @intCast(cell_index / extent);

    return .{ x, y };
}

pub fn cell_index_from_coord(extent: u32, position: u32_2) u32 {
    return position[0] + extent * position[1];
}

pub fn mask_for_number(number: u4) u16 {
    return @as(u16, 1) << number;
}

pub fn full_candidate_mask(game_extent: u32) u16 {
    return @intCast((@as(u32, 1) << @intCast(game_extent)) - 1);
}

pub fn create_game_state(allocator: std.mem.Allocator, game_type: GameType, sudoku_string: []const u8) !GameState {
    const extent = switch (game_type) {
        .regular => |regular| regular.box_w * regular.box_h,
        .jigsaw => |jigsaw| jigsaw.size,
    };
    const cell_count = extent * extent;

    assert(extent > 1);
    assert(extent <= MaxSudokuExtent);

    const board = try allocator.alloc(u5, cell_count);
    errdefer allocator.free(board);

    for (board) |*cell_number| {
        cell_number.* = UnsetNumber;
    }

    const candidate_masks = try allocator.alloc(u16, cell_count);
    errdefer allocator.free(candidate_masks);

    for (candidate_masks) |*candidate_mask| {
        candidate_mask.* = 0;
    }

    // Allocate history stack
    const board_history = try allocator.alloc(u5, cell_count * MaxHistorySize);
    errdefer allocator.free(board_history);

    const candidate_masks_history = try allocator.alloc(u16, cell_count * MaxHistorySize);
    errdefer allocator.free(candidate_masks_history);

    const region_offsets = try allocator.alloc(u32, cell_count * 3);
    errdefer allocator.free(region_offsets);

    const all_regions = try allocator.alloc([]u32, extent * 3);
    errdefer allocator.free(all_regions);

    const box_indices = try allocator.alloc(u4, cell_count);
    errdefer allocator.free(box_indices);

    switch (game_type) {
        .regular => |regular| {
            fill_region_indices_regular(box_indices, extent, regular.box_w, regular.box_h);
        },
        .jigsaw => |jigsaw| {
            fill_region_indices_from_string(box_indices, jigsaw.box_indices_string, extent);
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
        .candidate_masks = candidate_masks,
        .region_offsets = region_offsets,
        .all_regions = all_regions,
        .col_regions = col_regions,
        .row_regions = row_regions,
        .box_regions = box_regions,
        .box_indices = box_indices,
        .board_history = board_history,
        .candidate_masks_history = candidate_masks_history,
        .selected_cell = u32_2{ extent, extent }, // Invalid value
        .solver_events = solver_events,
    };

    if (sudoku_string.len == 0) {
        generator.generate_dumb_board(&game);
    } else {
        fill_board_from_string(game.board, sudoku_string, game.extent);
    }

    init_history_state(&game);

    return game;
}

pub fn destroy_game_state(allocator: std.mem.Allocator, game: *GameState) void {
    allocator.free(game.solver_events);
    allocator.free(game.box_indices);
    allocator.free(game.all_regions);
    allocator.free(game.region_offsets);
    allocator.free(game.board_history);
    allocator.free(game.candidate_masks_history);
    allocator.free(game.candidate_masks);
    allocator.free(game.board);
}

fn fill_regions(extent: u32, col_regions: [][]u32, row_regions: [][]u32, box_regions: [][]u32, box_indices: []const u4) void {
    for (0..extent) |region_index_usize| {
        var col_region = col_regions[region_index_usize];
        var row_region = row_regions[region_index_usize];

        assert(col_region.len == extent);
        assert(row_region.len == extent);

        const region_index: u32 = @intCast(region_index_usize);

        for (col_region, row_region, 0..) |*col_cell, *row_cell, cell_index_usize| {
            const cell_index: u32 = @intCast(cell_index_usize);
            col_cell.* = cell_index_from_coord(extent, .{ region_index, cell_index });
            row_cell.* = cell_index_from_coord(extent, .{ cell_index, region_index });
        }
    }

    var region_slot_full = std.mem.zeroes([MaxSudokuExtent]u32);
    var region_slot = region_slot_full[0..extent];

    for (box_indices, 0..) |box_index, cell_index| {
        const slot = region_slot[box_index];

        var box_region = box_regions[box_index];
        box_region[slot] = @intCast(cell_index);

        region_slot[box_index] += 1;
    }

    for (region_slot) |slot| {
        assert(slot == extent);
    }
}

pub fn fill_board_from_string(board: []u5, sudoku_string: []const u8, extent: u32) void {
    assert(board.len == extent * extent);
    assert(sudoku_string.len == extent * extent);

    for (board, sudoku_string) |*cell_number, char| {
        var number: u8 = UnsetNumber;

        if (char >= '1' and char <= '9') {
            number = char - '1';
        } else if (char >= 'A' and char <= 'G') {
            number = char - 'A' + 9;
        } else if (char >= 'a' and char <= 'g') {
            number = char - 'a' + 9;
        }

        assert(number < extent or number == UnsetNumber);

        cell_number.* = @intCast(number);
    }
}

pub fn fill_string_from_board(sudoku_string: []u8, board: []const u5, extent: u32) void {
    assert(board.len == extent * extent);
    assert(sudoku_string.len == extent * extent);

    for (board, sudoku_string) |cell_number, *char| {
        if (cell_number == UnsetNumber) {
            char.* = '.';
        } else {
            char.* = '1' + @as(u8, @intCast(cell_number));
        }
    }
}

fn fill_region_indices_regular(box_indices: []u4, extent: u32, box_w: u32, box_h: u32) void {
    for (box_indices, 0..) |*box_index, i| {
        const cell_coord = cell_coord_from_index(extent, i);
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
        const cell_index = cell_index_from_coord(game.extent, game.selected_cell);

        game.board[cell_index] = UnsetNumber;
        game.candidate_masks[cell_index] = 0;

        push_state_to_history(game);
    }
}

pub fn player_input_number(game: *GameState, number: u4) void {
    if (number < game.extent and all(game.selected_cell < u32_2{ game.extent, game.extent })) {
        place_number_remove_trivial_candidates(game, cell_index_from_coord(game.extent, game.selected_cell), number);
        push_state_to_history(game);
    }
}

pub fn player_toggle_guess(game: *GameState, number: u4) void {
    if (number < game.extent and all(game.selected_cell < u32_2{ game.extent, game.extent })) {
        const cell_index = cell_index_from_coord(game.extent, game.selected_cell);

        if (game.board[cell_index] == UnsetNumber) {
            game.candidate_masks[cell_index] ^= mask_for_number(number);
        }

        push_state_to_history(game);
    }
}

pub fn place_number_remove_trivial_candidates(game: *GameState, cell_index: u32, number: u4) void {
    game.board[cell_index] = number;
    game.candidate_masks[cell_index] = mask_for_number(number);

    solver.solve_trivial_candidates_at(game, cell_index, number);
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

fn get_board_history_slice(game: *GameState, history_index: u32) []u5 {
    const cell_count = game.extent * game.extent;
    const start = cell_count * history_index;
    const stop = start + cell_count;

    return game.board_history[start..stop];
}

fn get_candidate_masks_history_slice(game: *GameState, history_index: u32) []u16 {
    const cell_count = game.extent * game.extent;
    const start = cell_count * history_index;
    const stop = start + cell_count;

    return game.candidate_masks_history[start..stop];
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

        std.mem.copy(u5, get_board_history_slice(game, game.history_index), game.board);
        std.mem.copy(u16, get_candidate_masks_history_slice(game, game.history_index), game.candidate_masks);
    }
}

fn init_history_state(game: *GameState) void {
    std.mem.copy(u5, get_board_history_slice(game, 0), game.board);
    std.mem.copy(u16, get_candidate_masks_history_slice(game, 0), game.candidate_masks);
}

fn load_state_from_history(game: *GameState, index: u32) void {
    std.mem.copy(u5, game.board, get_board_history_slice(game, index));
    std.mem.copy(u16, game.candidate_masks, get_candidate_masks_history_slice(game, index));
}

pub fn player_fill_candidates(game: *GameState) void {
    // Prepare candidate mask for the solver
    for (game.board, game.candidate_masks) |cell_number, *candidate_mask| {
        if (cell_number != UnsetNumber) {
            candidate_mask.* = mask_for_number(@intCast(cell_number));
        } else {
            candidate_mask.* = full_candidate_mask(game.extent);
        }
    }

    for (game.board, 0..) |cell_number, cell_index| {
        if (cell_number != UnsetNumber) {
            place_number_remove_trivial_candidates(game, @intCast(cell_index), @intCast(cell_number));
        }
    }

    push_state_to_history(game);
}

pub fn player_clear_candidates(game: *GameState) void {
    for (game.candidate_masks) |*candidate_mask| {
        candidate_mask.* = 0;
    }

    push_state_to_history(game);
}
