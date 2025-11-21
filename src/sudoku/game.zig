const std = @import("std");
const assert = std.debug.assert;

const generator = @import("generator.zig");
const solver = @import("solver.zig");
const solver_logical = @import("solver_logical.zig");
const boards = @import("boards.zig");
const board_legacy = @import("board_legacy.zig");

// FIXME
pub const RegularSudoku = board_legacy.RegularSudoku;
pub const JigsawSudoku = board_legacy.JigsawSudoku;
pub const GameType = board_legacy.GameType;
pub const BoardState = board_legacy.BoardState;

// I borrowed this name from HLSL
pub fn all(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.vector.child == bool);
    assert(type_info.vector.len > 1);

    return @reduce(.And, vector);
}

pub const u32_2 = @Vector(2, u32);
const i32_2 = @Vector(2, i32);

pub const MaxSudokuExtent = board_legacy.MaxSudokuExtent;
pub const UnsetNumber: u5 = board_legacy.UnsetNumber;
const MaxHistorySize = 512;

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

pub fn create_game_state(allocator: std.mem.Allocator, game_type: GameType, sudoku_string: []const u8) !GameState {
    var board = try BoardState.create(allocator, game_type);

    if (sudoku_string.len == 0) {
        var random_buffer: [8]u8 = undefined;
        std.crypto.random.bytes(&random_buffer);

        const seed = std.mem.readInt(u64, &random_buffer, .little);

        generator.generate(&board, .{ .dancing_links = .{ .difficulty = 200 } }, seed);
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
        .flow = .Normal,
        .board_history = board_history,
        .candidate_masks_history = candidate_masks_history,
        .validation_error = null,
        .solver_event = null,
    };

    save_state_to_history(&game, 0);

    return game;
}

pub fn destroy_game_state(allocator: std.mem.Allocator, game: *GameState) void {
    allocator.free(game.board_history);
    allocator.free(game.candidate_masks_history);
    allocator.free(game.selected_cells_full);
    allocator.free(game.candidate_masks);

    game.board.destroy(allocator);
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
            char.* = boards.NumbersString[cell_number];
        }
    }
}

pub const SolverEvent = union(enum) {
    found_technique: solver_logical.Technique,
    found_nothing,
};

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

        save_state_to_history(game, game.history_index);
    }
}

fn save_state_to_history(game: *GameState, index: u32) void {
    @memcpy(get_board_history_slice(game, index), game.board.numbers);
    @memcpy(get_candidate_masks_history_slice(game, index), game.candidate_masks);
}

fn load_state_from_history(game: *GameState, index: u32) void {
    @memcpy(game.board.numbers, get_board_history_slice(game, index));
    @memcpy(game.candidate_masks, get_candidate_masks_history_slice(game, index));
}

pub fn fill_candidate_mask(board: BoardState, candidate_masks: []u16) void {
    var col_region_candidate_masks_full: [MaxSudokuExtent]u16 = undefined;
    var row_region_candidate_masks_full: [MaxSudokuExtent]u16 = undefined;
    var box_region_candidate_masks_full: [MaxSudokuExtent]u16 = undefined;
    const col_region_candidate_masks = col_region_candidate_masks_full[0..board.extent];
    const row_region_candidate_masks = row_region_candidate_masks_full[0..board.extent];
    const box_region_candidate_masks = box_region_candidate_masks_full[0..board.extent];

    fill_candidate_mask_regions(board, col_region_candidate_masks, row_region_candidate_masks, box_region_candidate_masks);

    for (candidate_masks, 0..) |*cell_candidate_mask, cell_index| {
        if (board.numbers[cell_index] == UnsetNumber) {
            const cell_coord = board.cell_coord_from_index(cell_index);
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
    const full_mask = board.full_candidate_mask();

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
            const cell_coord = board.cell_coord_from_index(cell_index);

            const col = cell_coord[0];
            const row = cell_coord[1];
            const box = board.box_indices[cell_index];

            const mask = ~board.mask_for_number(@intCast(cell_number));

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
        .Normal => {
            apply_player_event_normal_flow(game, action);
        },
        .WaitingForHintValidation => {
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
    const toggle_index = game.board.cell_index_from_coord(toggle_coord);

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
        var current_pos: i32_2 = @intCast(game.board.cell_coord_from_index(game.selected_cells[0]));

        const extent: i32 = @intCast(game.board.extent);
        assert(all(current_pos < i32_2{ extent, extent }));

        current_pos += .{ event.x_offset, event.y_offset };

        inline for (.{ &current_pos[0], &current_pos[1] }) |coord| {
            if (coord.* < 0) {
                coord.* += extent;
            } else if (coord.* >= extent) {
                coord.* -= extent;
            }
        }

        game.selected_cells[0] = game.board.cell_index_from_coord(@intCast(current_pos));
    }
}

const PlayerSetNumberAtSelection = struct {
    number: u4,
};

fn player_set_number(game: *GameState, number: u4) void {
    const extent = game.board.extent;
    if (number < extent and game.selected_cells.len > 0) {
        solver_logical.place_number_remove_trivial_candidates(&game.board, game.candidate_masks, game.selected_cells[0], number);
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
            game.candidate_masks[cell_index] ^= game.board.mask_for_number(number);
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
    const full_mask = game.board.full_candidate_mask();

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
    solver_logical.solve_trivial_candidates(&game.board, game.candidate_masks);

    if (solver_logical.find_easiest_known_technique(game.board, game.candidate_masks)) |solver_technique| {
        game.flow = .WaitingForHintValidation;
        game.solver_event = .{ .found_technique = solver_technique };
    } else {
        game.solver_event = .{ .found_nothing = undefined }; // FIXME clear this at one point
    }
}

fn player_apply_hint(game: *GameState) void {
    if (game.solver_event) |solver_event| {
        switch (solver_event) {
            .found_technique => |technique| {
                solver_logical.apply_technique(&game.board, game.candidate_masks, technique);

                game.solver_event = null;

                push_state_to_history(game);

                game.flow = .Normal;
            },
            .found_nothing => {
                @panic("Solver event found nothing!");
            },
        }
    } else {
        @panic("Solver event not found!");
    }
}

const PlayerSolveBoard = struct {
    // Nothing yet
};

fn player_solve_board(game: *GameState) void {
    if (solver.solve(&game.board, .{ .dancing_links = .{} })) {
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

pub fn check_board_for_validation_errors(board: BoardState, candidate_masks: []const u16) ?ValidationError {
    for (0..board.extent) |number_usize| {
        const number: u4 = @intCast(number_usize);
        const number_mask = board.mask_for_number(number);

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
