const std = @import("std");
const assert = std.debug.assert;

const board_generic = @import("board_generic.zig");
const RegionSet = board_generic.RegionSet;

const solver = @import("solver.zig");
const solver_logical = @import("solver_logical.zig");
const generator = @import("generator.zig");

const common = @import("common.zig");
const u32_2 = common.u32_2;
const i32_2 = common.i32_2;
const all = common.all;

const MaxHistorySize = 512;

const GameFlow = enum {
    Normal,
    WaitingForHintValidation,
};

pub fn State(extent: comptime_int) type {
    return struct {
        const Self = @This();
        const MaskType = board_generic.MaskType(extent);
        pub const SolverEvent = union(enum) {
            found_technique: solver_logical.Technique,
            found_nothing,
        };

        board: board_generic.State(extent),
        candidate_masks: []MaskType, // Should be set to zero when setting number
        selected_cells_full: []u32, // Full allocated array, we usually don't use it directly
        selected_cells: []u32, // Code handles this as a list but only a single cell is supported
        flow: GameFlow,
        board_history: []?u4,
        candidate_masks_history: []MaskType,
        history_index: u32 = 0,
        max_history_index: u32 = 0,
        validation_error: ?ValidationError,
        solver_event: ?SolverEvent,

        pub fn init(allocator: std.mem.Allocator, board_type: board_generic.BoardType, sudoku_string_opt: ?[]const u8) !Self {
            var board = board_generic.State(extent).init(board_type);

            if (sudoku_string_opt) |sudoku_string| {
                board.fill_board_from_string(sudoku_string);
            } else {
                var random_buffer: [8]u8 = undefined;
                std.crypto.random.bytes(&random_buffer);

                const seed = std.mem.readInt(u64, &random_buffer, .little);

                board = generator.generate(extent, board_type, seed, .{ .dancing_links = .{ .difficulty = 200 } });
            }

            std.debug.print("Board: {s}\n", .{&board.string_from_board()});

            const candidate_masks = try allocator.alloc(MaskType, board.numbers.len);
            errdefer allocator.free(candidate_masks);

            for (candidate_masks) |*candidate_mask| {
                candidate_mask.* = 0;
            }

            const selected_cells_full = try allocator.alloc(u32, board.ExtentSqr);
            errdefer allocator.free(selected_cells_full);

            // Allocate history stack
            const board_history = try allocator.alloc(?u4, board.ExtentSqr * MaxHistorySize);
            errdefer allocator.free(board_history);

            const candidate_masks_history = try allocator.alloc(MaskType, board.numbers.len * MaxHistorySize);
            errdefer allocator.free(candidate_masks_history);

            var game = Self{
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

            game.save_state_to_history(0);

            return game;
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.board_history);
            allocator.free(self.candidate_masks_history);
            allocator.free(self.selected_cells_full);
            allocator.free(self.candidate_masks);
        }

        fn get_board_history_slice(self: Self, history_index: u32) []?u4 {
            const cell_count = self.board.numbers.len;
            const start = cell_count * history_index;
            const stop = start + cell_count;

            return self.board_history[start..stop];
        }

        fn get_candidate_masks_history_slice(self: Self, history_index: u32) []MaskType {
            const cell_count = self.board.numbers.len;
            const start = cell_count * history_index;
            const stop = start + cell_count;

            return self.candidate_masks_history[start..stop];
        }

        fn push_state_to_history(self: *Self) void {
            if (self.history_index + 1 < MaxHistorySize) {
                self.history_index += 1;
                self.max_history_index = self.history_index;

                self.save_state_to_history(self.history_index);
            }
        }

        fn save_state_to_history(self: *Self, index: u32) void {
            @memcpy(self.get_board_history_slice(index), &self.board.numbers);
            @memcpy(self.get_candidate_masks_history_slice(index), self.candidate_masks);
        }

        fn load_state_from_history(self: *Self, index: u32) void {
            @memcpy(&self.board.numbers, self.get_board_history_slice(index));
            @memcpy(self.candidate_masks, self.get_candidate_masks_history_slice(index));
        }

        pub fn apply_player_event(self: *Self, action: PlayerAction) void {
            switch (self.flow) {
                .Normal => {
                    self.apply_player_event_normal_flow(action);
                },
                .WaitingForHintValidation => {
                    switch (action) {
                        .get_hint => |_| {
                            self.player_apply_hint();
                        },
                        else => {},
                    }
                },
            }

            self.validation_error = check_board_for_validation_errors(extent, &self.board, self.candidate_masks);
        }

        fn apply_player_event_normal_flow(self: *Self, action: PlayerAction) void {
            switch (action) {
                .toggle_select => |toggle_select| {
                    self.player_toggle_select(toggle_select.coord);
                },
                .move_selection => |move_selection| {
                    self.player_move_selection(move_selection);
                },
                .set_number => |set_number| {
                    self.player_set_number(set_number.number);
                },
                .toggle_candidate => |toggle_candidate| {
                    self.player_toggle_candidate(toggle_candidate.number);
                },
                .clear_selected_cell => |_| {
                    self.player_clear_selected_cell();
                },
                .undo => |_| {
                    self.player_undo();
                },
                .redo => |_| {
                    self.player_redo();
                },
                .fill_candidates => |_| {
                    self.player_fill_candidates();
                },
                .fill_all_candidates => |_| {
                    self.player_fill_candidates_all();
                },
                .clear_all_candidates => |_| {
                    self.player_clear_candidates();
                },
                .get_hint => |_| {
                    self.player_get_hint();
                },
                .solve_board => |_| {
                    self.player_solve_board();
                },
            }
        }

        fn player_toggle_select(self: *Self, toggle_coord: u32_2) void {
            const toggle_index = self.board.cell_index_from_coord(toggle_coord);

            if (self.selected_cells.len > 0 and toggle_index == self.selected_cells[0]) {
                self.selected_cells = self.selected_cells_full[0..0];
            } else {
                self.selected_cells = self.selected_cells_full[0..1];
                self.selected_cells[0] = toggle_index;
            }
        }

        fn player_move_selection(self: *Self, event: PlayerMoveSelection) void {
            if (self.selected_cells.len > 0) {
                var current_pos: i32_2 = @intCast(self.board.cell_coord_from_index(self.selected_cells[0]));

                assert(all(current_pos < i32_2{ extent, extent }));

                current_pos += .{ event.x_offset, event.y_offset };

                inline for (.{ &current_pos[0], &current_pos[1] }) |coord| {
                    if (coord.* < 0) {
                        coord.* += extent;
                    } else if (coord.* >= extent) {
                        coord.* -= extent;
                    }
                }

                self.selected_cells[0] = self.board.cell_index_from_coord(@intCast(current_pos));
            }
        }

        fn player_set_number(self: *Self, number: u4) void {
            if (number < self.board.Extent and self.selected_cells.len > 0) {
                solver_logical.place_number_remove_trivial_candidates(extent, &self.board, self.candidate_masks, self.selected_cells[0], number);
                self.push_state_to_history();
            }
        }

        fn player_toggle_candidate(self: *Self, number: u4) void {
            if (number < self.board.Extent and self.selected_cells.len > 0) {
                const cell_index = self.selected_cells[0];

                if (self.board.numbers[cell_index] == null) {
                    self.candidate_masks[cell_index] ^= self.board.mask_for_number(number);
                }

                self.push_state_to_history();
            }
        }

        fn player_clear_selected_cell(self: *Self) void {
            if (self.selected_cells.len > 0) {
                const cell_index = self.selected_cells[0];

                self.board.numbers[cell_index] = null;
                self.candidate_masks[cell_index] = 0;

                self.push_state_to_history();
            }
        }

        fn player_undo(self: *Self) void {
            if (self.history_index > 0) {
                self.history_index -= 1;

                self.load_state_from_history(self.history_index);
            }
        }

        fn player_redo(self: *Self) void {
            if (self.history_index < self.max_history_index) {
                self.history_index += 1;

                self.load_state_from_history(self.history_index);
            }
        }

        fn player_fill_candidates(self: *Self) void {
            self.board.fill_candidate_mask(self.candidate_masks);

            self.push_state_to_history();
        }

        fn player_fill_candidates_all(self: *Self) void {
            const full_mask = self.board.full_candidate_mask();

            for (self.candidate_masks, 0..) |*cell_candidate_mask, cell_index| {
                if (self.board.numbers[cell_index] == null) {
                    cell_candidate_mask.* = full_mask;
                }
            }

            self.push_state_to_history();
        }

        fn player_clear_candidates(self: *Self) void {
            for (self.candidate_masks) |*candidate_mask| {
                candidate_mask.* = 0;
            }

            self.push_state_to_history();
        }

        fn player_get_hint(self: *Self) void {
            solver_logical.solve_trivial_candidates(extent, &self.board, self.candidate_masks);

            if (solver_logical.find_easiest_known_technique(extent, self.board, self.candidate_masks)) |solver_technique| {
                self.flow = .WaitingForHintValidation;
                self.solver_event = .{ .found_technique = solver_technique };
            } else {
                self.solver_event = .{ .found_nothing = undefined }; // FIXME clear this at one point
            }
        }

        fn player_apply_hint(self: *Self) void {
            if (self.solver_event) |solver_event| {
                switch (solver_event) {
                    .found_technique => |technique| {
                        solver_logical.apply_technique(extent, &self.board, self.candidate_masks, technique);

                        self.solver_event = null;

                        self.push_state_to_history();

                        self.flow = .Normal;
                    },
                    .found_nothing => {
                        @panic("Solver event found nothing!");
                    },
                }
            } else {
                @panic("Solver event not found!");
            }
        }

        fn player_solve_board(self: *Self) void {
            if (solver.solve(extent, &self.board, .{ .dancing_links = .{} })) {
                self.player_clear_candidates();
                // NOTE: Already done in the body of clear_candidates.
                // push_state_to_history(game);
            } else {
                // We didn't manage to solve the puzzle
                // FIXME tell the player somehow
            }
        }
    };
}

pub const PlayerAction = union(enum) {
    toggle_select: PlayerToggleSelect,
    move_selection: PlayerMoveSelection,
    set_number: PlayerSetNumberAtSelection,
    toggle_candidate: PlayerToggleCandidateAtSelection,
    clear_selected_cell,
    undo,
    redo,
    fill_candidates,
    fill_all_candidates,
    clear_all_candidates,
    get_hint,
    solve_board,
};

const PlayerToggleSelect = struct {
    coord: u32_2,
};
const PlayerMoveSelection = struct {
    x_offset: i32,
    y_offset: i32,
};

const PlayerSetNumberAtSelection = struct {
    number: u4,
};

const PlayerToggleCandidateAtSelection = struct {
    number: u4,
};

pub const ValidationError = struct {
    number: u4,
    is_candidate: bool,
    invalid_cell_index: u32,
    reference_cell_index: u32,
    region_index: board_generic.RegionIndex,
};

pub fn check_board_for_validation_errors(extent: comptime_int, board: *const board_generic.State(extent), candidate_masks: []const board_generic.MaskType(extent)) ?ValidationError {
    for (0..board.Extent) |number_usize| {
        const number: u4 = @intCast(number_usize);
        const number_mask = board.mask_for_number(number);

        inline for (.{ RegionSet.Col, RegionSet.Row, RegionSet.Box }) |set| {
            for (0..board.Extent) |sub_index| {
                const region_index = board.regions.get_region_index(set, sub_index);
                const region = board.regions.get(region_index);

                var last_cell_index: u32 = undefined;
                var found = false;

                for (region) |cell_index| {
                    if (found and candidate_masks[cell_index] & number_mask != 0) {
                        return .{
                            .number = number,
                            .is_candidate = true,
                            .invalid_cell_index = cell_index,
                            .reference_cell_index = last_cell_index,
                            .region_index = region_index,
                        };
                    }

                    if (board.numbers[cell_index] == number) {
                        if (found) {
                            return .{
                                .number = number,
                                .is_candidate = false,
                                .invalid_cell_index = cell_index,
                                .reference_cell_index = last_cell_index,
                                .region_index = region_index,
                            };
                        }

                        found = true;
                        last_cell_index = cell_index;
                    }
                }
            }
        }
    }

    return null;
}
