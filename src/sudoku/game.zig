const std = @import("std");
const assert = std.debug.assert;

const generator = @import("generator.zig");
const solver = @import("solver.zig");
const solver_logical = @import("solver_logical.zig");

// I borrowed this name from HLSL
pub fn all(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.vector.child == bool);
    assert(type_info.vector.len > 1);

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

pub const GameType = union(enum) {
    regular: RegularSudoku,
    jigsaw: JigsawSudoku,
};

pub const BoardState = struct {
    numbers: []u5,
    extent: u32,
    game_type: GameType,
    // Helpers to iterate over regions
    region_offsets: []u32, // Raw memory, shouldn't be used directly
    all_regions: [][]u32,
    col_regions: [][]u32,
    row_regions: [][]u32,
    box_regions: [][]u32,
    box_indices: []u4,
};

const GameFlow = enum {
    Normal,
    WaitingForHintValidation,
};

pub const GameState = struct {
    board: BoardState,
    candidate_masks: []u16, // Should be set to zero when setting number
    selected_cells_full: []u32, // Full allocated array, we usually don't use it directly
    selected_cells: []u32, // Code handles this as a list but only a single cell is supported
    flow: GameFlow,
    board_history: []u5,
    candidate_masks_history: []u16,
    history_index: u32 = 0,
    max_history_index: u32 = 0,
    validation_error: ?ValidationError,
    solver_event: ?SolverEvent,
};

pub fn cell_coord_from_index(extent: u32, cell_index: usize) u32_2 {
    const x: u32 = @intCast(cell_index % extent);
    const y: u32 = @intCast(cell_index / extent);

    assert(x < extent and y < extent);

    return .{ x, y };
}

pub fn cell_index_from_coord(extent: u32, position: u32_2) u32 {
    assert(all(position < u32_2{ extent, extent }));
    return position[0] + extent * position[1];
}

pub fn mask_for_number(number: u4) u16 {
    return @as(u16, 1) << number;
}

pub fn full_candidate_mask(game_extent: u32) u16 {
    return @intCast((@as(u32, 1) << @intCast(game_extent)) - 1);
}

pub fn create_board_state(allocator: std.mem.Allocator, game_type: GameType) !BoardState {
    const extent = switch (game_type) {
        .regular => |regular| regular.box_w * regular.box_h,
        .jigsaw => |jigsaw| jigsaw.size,
    };

    assert(extent > 1);
    assert(extent <= MaxSudokuExtent);

    const board = try allocator.alloc(u5, extent * extent);
    errdefer allocator.free(board);

    for (board) |*cell_number| {
        cell_number.* = UnsetNumber;
    }

    const region_offsets = try allocator.alloc(u32, board.len * 3);
    errdefer allocator.free(region_offsets);

    const all_regions = try allocator.alloc([]u32, extent * 3);
    errdefer allocator.free(all_regions);

    const box_indices = try allocator.alloc(u4, board.len);
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

    const board_state = BoardState{
        .numbers = board,
        .extent = extent,
        .game_type = game_type,
        .region_offsets = region_offsets,
        .all_regions = all_regions,
        .col_regions = col_regions,
        .row_regions = row_regions,
        .box_regions = box_regions,
        .box_indices = box_indices,
    };

    return board_state;
}

pub fn destroy_board_state(allocator: std.mem.Allocator, board: BoardState) void {
    allocator.free(board.numbers);
    allocator.free(board.region_offsets);
    allocator.free(board.all_regions);
    allocator.free(board.box_indices);
}

pub fn create_game_state(allocator: std.mem.Allocator, game_type: GameType, sudoku_string: []const u8) !GameState {
    var board = try create_board_state(allocator, game_type);

    if (sudoku_string.len == 0) {
        var random_buffer: [8]u8 = undefined;
        std.crypto.random.bytes(&random_buffer);

        const seed = std.mem.readInt(u64, &random_buffer, .little);

        generator.generate(&board, .{ .dancing_links = undefined }, seed);
    } else {
        fill_board_from_string(board.numbers, sudoku_string, board.extent);
    }

    {
        const string = try allocator.alloc(u8, board.numbers.len);
        defer allocator.free(string);

        fill_string_from_board(string, board.numbers, board.extent);

        std.debug.print("Board: {s}\n", .{string});
    }

    const candidate_masks = try allocator.alloc(u16, board.numbers.len);
    errdefer allocator.free(candidate_masks);

    for (candidate_masks) |*candidate_mask| {
        candidate_mask.* = 0;
    }

    const selected_cells_full = try allocator.alloc(u32, board.numbers.len);
    errdefer allocator.free(selected_cells_full);

    // Allocate history stack
    const board_history = try allocator.alloc(u5, board.numbers.len * MaxHistorySize);
    errdefer allocator.free(board_history);

    const candidate_masks_history = try allocator.alloc(u16, board.numbers.len * MaxHistorySize);
    errdefer allocator.free(candidate_masks_history);

    var game = GameState{
        .board = board,
        .candidate_masks = candidate_masks,
        .selected_cells_full = selected_cells_full,
        .selected_cells = selected_cells_full[0..0],
        .flow = GameFlow.Normal,
        .board_history = board_history,
        .candidate_masks_history = candidate_masks_history,
        .validation_error = null,
        .solver_event = null,
    };

    init_history_state(&game);

    return game;
}

pub fn destroy_game_state(allocator: std.mem.Allocator, game: *GameState) void {
    allocator.free(game.board_history);
    allocator.free(game.candidate_masks_history);
    allocator.free(game.selected_cells_full);
    allocator.free(game.candidate_masks);

    destroy_board_state(allocator, game.board);
}

fn fill_regions(extent: u32, col_regions: [][]u32, row_regions: [][]u32, box_regions: [][]u32, box_indices: []const u4) void {
    for (0..extent) |region_index_usize| {
        const col_region = col_regions[region_index_usize];
        const row_region = row_regions[region_index_usize];

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

pub fn fill_empty_board(board: []u5) void {
    for (board) |*cell_number| {
        cell_number.* = UnsetNumber;
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

pub fn place_number_remove_trivial_candidates(board: *BoardState, candidate_masks: []u16, cell_index: u32, number: u4) void {
    board.numbers[cell_index] = number;
    candidate_masks[cell_index] = 0;

    solver_logical.remove_trivial_candidates_at(board, candidate_masks, cell_index, number);
}

const NothingFound = struct {};

pub const SolverEvent = union(enum) {
    naked_single: solver_logical.NakedSingle,
    hidden_single: solver_logical.HiddenSingle,
    hidden_pair: solver_logical.HiddenPair,
    pointing_line: solver_logical.PointingLine,
    box_line_reduction: solver_logical.BoxLineReduction,
    nothing_found: NothingFound,
};

fn solve_human_step(game: *GameState) ?SolverEvent {
    solver_logical.solve_trivial_candidates(&game.board, game.candidate_masks);

    if (solver_logical.find_naked_single(game.board, game.candidate_masks)) |naked_single| {
        return .{ .naked_single = naked_single };
    } else if (solver_logical.find_hidden_single(game.board, game.candidate_masks)) |hidden_single| {
        return .{ .hidden_single = hidden_single };
    } else if (solver_logical.find_hidden_pair(game.board, game.candidate_masks)) |hidden_pair| {
        return .{ .hidden_pair = hidden_pair };
    } else if (solver_logical.find_pointing_line(game.board, game.candidate_masks)) |pointing_line| {
        return .{ .pointing_line = pointing_line };
    } else if (solver_logical.find_box_line_reduction(game.board, game.candidate_masks)) |box_line_reduction| {
        return .{ .box_line_reduction = box_line_reduction };
    } else {
        return null;
    }
}

pub fn apply_solver_event(board: *BoardState, candidate_masks: []u16, solver_event: SolverEvent) void {
    switch (solver_event) {
        .naked_single => |naked_single| {
            place_number_remove_trivial_candidates(board, candidate_masks, naked_single.cell_index, naked_single.number);
        },
        .hidden_single => |hidden_single| {
            place_number_remove_trivial_candidates(board, candidate_masks, hidden_single.cell_index, hidden_single.number);
            // candidate_masks[hidden_single.cell_index] &= ~hidden_single.deletion_mask;
        },
        .hidden_pair => |hidden_pair| {
            candidate_masks[hidden_pair.a.cell_index] &= ~hidden_pair.a.deletion_mask;
            candidate_masks[hidden_pair.b.cell_index] &= ~hidden_pair.b.deletion_mask;
        },
        .pointing_line => |pointing_line| {
            const number_mask = mask_for_number(pointing_line.number);
            for (pointing_line.line_region, 0..) |cell_index, region_cell_index| {
                // FIXME super confusing
                if (mask_for_number(@intCast(region_cell_index)) & pointing_line.line_region_deletion_mask != 0) {
                    candidate_masks[cell_index] &= ~number_mask;
                }
            }
        },
        .box_line_reduction => |box_line_reduction| {
            const number_mask = mask_for_number(box_line_reduction.number);
            for (box_line_reduction.box_region, 0..) |cell_index, region_cell_index| {
                // FIXME super confusing
                if (mask_for_number(@intCast(region_cell_index)) & box_line_reduction.box_region_deletion_mask != 0) {
                    candidate_masks[cell_index] &= ~number_mask;
                }
            }
        },
        else => unreachable,
    }
}

fn get_board_history_slice(game: *GameState, history_index: u32) []u5 {
    const cell_count = game.board.numbers.len;
    const start = cell_count * history_index;
    const stop = start + cell_count;

    return game.board_history[start..stop];
}

fn get_candidate_masks_history_slice(game: *GameState, history_index: u32) []u16 {
    const cell_count = game.board.numbers.len;
    const start = cell_count * history_index;
    const stop = start + cell_count;

    return game.candidate_masks_history[start..stop];
}

fn push_state_to_history(game: *GameState) void {
    if (game.history_index + 1 < MaxHistorySize) {
        game.history_index += 1;
        game.max_history_index = game.history_index;

        std.mem.copyForwards(u5, get_board_history_slice(game, game.history_index), game.board.numbers);
        std.mem.copyForwards(u16, get_candidate_masks_history_slice(game, game.history_index), game.candidate_masks);
    }
}

fn init_history_state(game: *GameState) void {
    std.mem.copyForwards(u5, get_board_history_slice(game, 0), game.board.numbers);
    std.mem.copyForwards(u16, get_candidate_masks_history_slice(game, 0), game.candidate_masks);
}

fn load_state_from_history(game: *GameState, index: u32) void {
    std.mem.copyForwards(u5, game.board.numbers, get_board_history_slice(game, index));
    std.mem.copyForwards(u16, game.candidate_masks, get_candidate_masks_history_slice(game, index));
}

fn fill_candidate_mask(board: BoardState, candidate_masks: []u16) void {
    var col_region_candidate_masks_full: [MaxSudokuExtent]u16 = undefined;
    var row_region_candidate_masks_full: [MaxSudokuExtent]u16 = undefined;
    var box_region_candidate_masks_full: [MaxSudokuExtent]u16 = undefined;
    const col_region_candidate_masks = col_region_candidate_masks_full[0..board.extent];
    const row_region_candidate_masks = row_region_candidate_masks_full[0..board.extent];
    const box_region_candidate_masks = box_region_candidate_masks_full[0..board.extent];

    fill_candidate_mask_regions(board, col_region_candidate_masks, row_region_candidate_masks, box_region_candidate_masks);

    for (candidate_masks, 0..) |*cell_candidate_mask, cell_index| {
        if (board.numbers[cell_index] == UnsetNumber) {
            const cell_coord = cell_coord_from_index(board.extent, cell_index);
            const col = cell_coord[0];
            const row = cell_coord[1];
            const box = board.box_indices[cell_index];

            const col_candidate_mask = col_region_candidate_masks[col];
            const row_candidate_mask = row_region_candidate_masks[row];
            const box_candidate_mask = box_region_candidate_masks[box];

            cell_candidate_mask.* = col_candidate_mask & row_candidate_mask & box_candidate_mask;
        } else {
            // It should already be zero for set numbers
            assert(cell_candidate_mask.* == 0);
        }
    }
}

fn fill_candidate_mask_regions(board: BoardState, col_region_candidate_masks: []u16, row_region_candidate_masks: []u16, box_region_candidate_masks: []u16) void {
    const full_mask = full_candidate_mask(board.extent);

    for (col_region_candidate_masks) |*col_region_candidate_mask| {
        col_region_candidate_mask.* = full_mask;
    }

    for (row_region_candidate_masks) |*row_region_candidate_mask| {
        row_region_candidate_mask.* = full_mask;
    }

    for (box_region_candidate_masks) |*box_region_candidate_mask| {
        box_region_candidate_mask.* = full_mask;
    }

    for (board.numbers, 0..) |cell_number, cell_index| {
        if (cell_number != UnsetNumber) {
            const cell_coord = cell_coord_from_index(board.extent, cell_index);

            const col = cell_coord[0];
            const row = cell_coord[1];
            const box = board.box_indices[cell_index];

            const mask = ~mask_for_number(@intCast(cell_number));

            col_region_candidate_masks[col] &= mask;
            row_region_candidate_masks[row] &= mask;
            box_region_candidate_masks[box] &= mask;
        }
    }
}

pub const PlayerAction = union(enum) {
    toggle_select: PlayerToggleSelect,
    move_selection: PlayerMoveSelection,
    set_number: PlayerSetNumberAtSelection,
    toggle_candidate: PlayerToggleCandidateAtSelection,
    clear_selected_cell: PlayerClearSelectedCell,
    undo: PlayerUndo,
    redo: PlayerRedo,
    fill_candidates: PlayerFillCandidates,
    fill_all_candidates: PlayerFillAllCandidates,
    clear_all_candidates: PlayerClearCandidates,
    get_hint: PlayerGetHint,
    solve_board: PlayerSolveBoard,
};

pub fn apply_player_event(game: *GameState, action: PlayerAction) void {
    switch (game.flow) {
        GameFlow.Normal => {
            apply_player_event_normal_flow(game, action);
        },
        GameFlow.WaitingForHintValidation => {
            switch (action) {
                .get_hint => |_| {
                    player_apply_hint(game);
                },
                else => {},
            }
        },
    }

    game.validation_error = check_board_for_validation_errors(game.board, game.candidate_masks);
}

fn apply_player_event_normal_flow(game: *GameState, action: PlayerAction) void {
    switch (action) {
        .toggle_select => |toggle_select| {
            player_toggle_select(game, toggle_select.coord);
        },
        .move_selection => |move_selection| {
            player_move_selection(game, move_selection);
        },
        .set_number => |set_number| {
            player_set_number(game, set_number.number);
        },
        .toggle_candidate => |toggle_candidate| {
            player_toggle_candidate(game, toggle_candidate.number);
        },
        .clear_selected_cell => |_| {
            player_clear_selected_cell(game);
        },
        .undo => |_| {
            player_undo(game);
        },
        .redo => |_| {
            player_redo(game);
        },
        .fill_candidates => |_| {
            player_fill_candidates(game);
        },
        .fill_all_candidates => |_| {
            player_fill_candidates_all(game);
        },
        .clear_all_candidates => |_| {
            player_clear_candidates(game);
        },
        .get_hint => |_| {
            player_get_hint(game);
        },
        .solve_board => |_| {
            player_solve_board(game);
        },
    }
}

const PlayerToggleSelect = struct {
    coord: u32_2,
};

fn player_toggle_select(game: *GameState, toggle_coord: u32_2) void {
    const toggle_index = cell_index_from_coord(game.board.extent, toggle_coord);

    if (game.selected_cells.len > 0 and toggle_index == game.selected_cells[0]) {
        game.selected_cells = game.selected_cells_full[0..0];
    } else {
        game.selected_cells = game.selected_cells_full[0..1];
        game.selected_cells[0] = toggle_index;
    }
}

const PlayerMoveSelection = struct {
    x_offset: i32,
    y_offset: i32,
};

fn player_move_selection(game: *GameState, event: PlayerMoveSelection) void {
    if (game.selected_cells.len > 0) {
        const extent = game.board.extent;
        const current_pos = cell_coord_from_index(extent, game.selected_cells[0]);

        assert(all(current_pos < u32_2{ extent, extent }));

        game.selected_cells[0] = cell_index_from_coord(extent, .{
            @min(extent - 1, @max(0, @as(i32, @intCast(current_pos[0])) + event.x_offset)),
            @min(extent - 1, @max(0, @as(i32, @intCast(current_pos[1])) + event.y_offset)),
        });
    }
}

const PlayerSetNumberAtSelection = struct {
    number: u4,
};

fn player_set_number(game: *GameState, number: u4) void {
    const extent = game.board.extent;
    if (number < extent and game.selected_cells.len > 0) {
        place_number_remove_trivial_candidates(&game.board, game.candidate_masks, game.selected_cells[0], number);
        push_state_to_history(game);
    }
}

const PlayerToggleCandidateAtSelection = struct {
    number: u4,
};

fn player_toggle_candidate(game: *GameState, number: u4) void {
    const extent = game.board.extent;
    if (number < extent and game.selected_cells.len > 0) {
        const cell_index = game.selected_cells[0];

        if (game.board.numbers[cell_index] == UnsetNumber) {
            game.candidate_masks[cell_index] ^= mask_for_number(number);
        }

        push_state_to_history(game);
    }
}

const PlayerClearSelectedCell = struct {
    // Nothing yet
};

fn player_clear_selected_cell(game: *GameState) void {
    if (game.selected_cells.len > 0) {
        const cell_index = game.selected_cells[0];

        game.board.numbers[cell_index] = UnsetNumber;
        game.candidate_masks[cell_index] = 0;

        push_state_to_history(game);
    }
}

const PlayerUndo = struct {
    // Nothing yet
};

fn player_undo(game: *GameState) void {
    if (game.history_index > 0) {
        game.history_index -= 1;

        load_state_from_history(game, game.history_index);
    }
}

const PlayerRedo = struct {
    // Nothing yet
};

fn player_redo(game: *GameState) void {
    if (game.history_index < game.max_history_index) {
        game.history_index += 1;

        load_state_from_history(game, game.history_index);
    }
}

const PlayerFillCandidates = struct {
    // Nothing yet
};

fn player_fill_candidates(game: *GameState) void {
    fill_candidate_mask(game.board, game.candidate_masks);

    push_state_to_history(game);
}

const PlayerFillAllCandidates = struct {
    // Nothing yet
};

fn player_fill_candidates_all(game: *GameState) void {
    const full_mask = full_candidate_mask(game.board.extent);

    for (game.candidate_masks, 0..) |*cell_candidate_mask, cell_index| {
        if (game.board.numbers[cell_index] == UnsetNumber) {
            cell_candidate_mask.* = full_mask;
        }
    }

    push_state_to_history(game);
}

const PlayerClearCandidates = struct {
    // Nothing yet
};

fn player_clear_candidates(game: *GameState) void {
    for (game.candidate_masks) |*candidate_mask| {
        candidate_mask.* = 0;
    }

    push_state_to_history(game);
}

const PlayerGetHint = struct {
    // Nothing yet
};

fn player_get_hint(game: *GameState) void {
    if (solve_human_step(game)) |solver_event| {
        game.solver_event = solver_event;
        game.flow = GameFlow.WaitingForHintValidation;
    } else {
        game.solver_event = .{ .nothing_found = .{} }; // FIXME clear this at one point
    }
}

fn player_apply_hint(game: *GameState) void {
    assert(game.solver_event != null);

    apply_solver_event(&game.board, game.candidate_masks, game.solver_event.?);

    game.solver_event = null;

    push_state_to_history(game);

    game.flow = GameFlow.Normal;
}

const PlayerSolveBoard = struct {
    // Nothing yet
};

fn player_solve_board(game: *GameState) void {
    if (solver.solve(&game.board, .{ .dancing_links = undefined })) {
        player_clear_candidates(game);
        // NOTE: Already done in the body of clear_candidates.
        // push_state_to_history(game);
    } else {
        // We didn't manage to solve the puzzle
        // FIXME tell the player somehow
    }
}

pub const ValidationError = struct {
    number: u4,
    is_candidate: bool,
    invalid_cell_index: u32,
    reference_cell_index: u32,
    region: []u32,
};

fn check_board_for_validation_errors(board: BoardState, candidate_masks: []const u16) ?ValidationError {
    for (0..board.extent) |number_usize| {
        const number: u4 = @intCast(number_usize);
        const number_mask = mask_for_number(number);

        for (board.all_regions) |region| {
            var last_cell_index: u32 = undefined;
            var found = false;

            for (region) |cell_index| {
                if (found and candidate_masks[cell_index] & number_mask != 0) {
                    return .{
                        .number = number,
                        .is_candidate = true,
                        .invalid_cell_index = cell_index,
                        .reference_cell_index = last_cell_index,
                        .region = region,
                    };
                }

                if (board.numbers[cell_index] == number) {
                    if (found) {
                        return .{
                            .number = number,
                            .is_candidate = false,
                            .invalid_cell_index = cell_index,
                            .reference_cell_index = last_cell_index,
                            .region = region,
                        };
                    }

                    found = true;
                    last_cell_index = cell_index;
                }
            }
        }
    }

    return null;
}
