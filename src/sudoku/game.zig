const std = @import("std");
const assert = std.debug.assert;

const rules = @import("rules.zig");
const board = @import("board.zig");

const solver = @import("solver.zig");
const solver_logical = @import("solver_logical.zig");
const generator = @import("generator.zig");
const validator = @import("validator.zig");

const common = @import("common.zig");
const u32_2 = common.u32_2;
const i32_2 = common.i32_2;
const all = common.all;

const MaxHistorySize = 512;

const GameFlow = enum {
    Normal,
    WaitingForHintValidation,
};

pub const State = struct {
    const Self = @This();
    const MaskType = board.MaskType;
    pub const SolverEvent = union(enum) {
        found_technique: solver_logical.Technique,
        found_nothing,
    };

    allocator: std.mem.Allocator,
    board: board.Board,
    candidate_masks: []MaskType, // Should be set to zero when setting number
    selected_cells_full: []u32, // Full allocated array, we usually don't use it directly
    selected_cells: []u32, // Code handles this as a list but only a single cell is supported
    flow: GameFlow,
    board_history: []?u4,
    candidate_masks_history: []MaskType,
    history_index: u32 = 0,
    max_history_index: u32 = 0,
    validation_error: ?validator.ValidationError,
    solver_event: ?SolverEvent,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, board_rules: rules.Rules, sudoku_string_opt: ?[]const u8) !Self {
        var game = try Self.init_empty_board(allocator, board_rules.type.extent());
        errdefer game.deinit();

        var board_state: board.Board = try .init(board_rules);

        if (sudoku_string_opt) |sudoku_string| {
            try board_state.fill_board_from_string(sudoku_string);
        } else {
            var seed_buffer: [8]u8 = undefined;
            io.random(&seed_buffer);

            const seed = std.mem.readInt(u64, &seed_buffer, .little);

            board_state = try generator.generate(allocator, board_rules, seed, .{ .dancing_links = .{} });
        }

        game.board = board_state;

        game.save_state_to_history(0);

        return game;
    }

    pub fn init_empty_board(allocator: std.mem.Allocator, extent: u32) !Self {
        const extent_sqr = extent * extent;

        const candidate_masks = try allocator.alloc(MaskType, extent_sqr);
        errdefer allocator.free(candidate_masks);

        for (candidate_masks) |*candidate_mask| {
            candidate_mask.* = 0;
        }

        const selected_cells_full = try allocator.alloc(u32, extent_sqr);
        errdefer allocator.free(selected_cells_full);

        // Allocate history stack
        const board_history = try allocator.alloc(?u4, extent_sqr * MaxHistorySize);
        errdefer allocator.free(board_history);

        const candidate_masks_history = try allocator.alloc(MaskType, extent_sqr * MaxHistorySize);
        errdefer allocator.free(candidate_masks_history);

        return .{
            .allocator = allocator,
            .board = undefined, // Not set yet!
            .candidate_masks = candidate_masks,
            .selected_cells_full = selected_cells_full,
            .selected_cells = selected_cells_full[0..0],
            .flow = .Normal,
            .board_history = board_history,
            .candidate_masks_history = candidate_masks_history,
            .validation_error = null,
            .solver_event = null,
        };
    }

    pub fn save(self: *const Self, writer: *std.Io.Writer) !void {
        // Write extent first to be able to allocate the state
        try writer.writeInt(u32, self.board.extent, .little);

        try self.board.save(writer);

        const extent_sqr = self.board.extent * self.board.extent;

        for (self.candidate_masks[0..extent_sqr]) |mask| {
            try writer.writeInt(MaskType, mask, .little);
        }

        try writer.writeInt(u32, self.history_index, .little);
        try writer.writeInt(u32, self.max_history_index, .little);

        const history_entry_count = self.max_history_index + 1;
        for (0..history_entry_count) |i| {
            const start = extent_sqr * i;
            for (self.board_history[start .. start + extent_sqr]) |number_opt| {
                try writer.writeByte(if (number_opt) |n| n else 0xff);
            }
            for (self.candidate_masks_history[start .. start + extent_sqr]) |mask| {
                try writer.writeInt(MaskType, mask, .little);
            }
        }
    }

    pub fn load(reader: *std.Io.Reader, allocator: std.mem.Allocator) !Self {
        const extent = try reader.takeInt(u32, .little);

        var self: Self = try .init_empty_board(allocator, extent);
        errdefer self.deinit();

        try self.board.load(reader);

        const extent_sqr = self.board.extent * self.board.extent;

        for (self.candidate_masks[0..extent_sqr]) |*mask| {
            mask.* = try reader.takeInt(MaskType, .little);
        }

        self.history_index = try reader.takeInt(u32, .little);
        self.max_history_index = try reader.takeInt(u32, .little);

        const history_entry_count = self.max_history_index + 1;
        for (0..history_entry_count) |i| {
            const start = extent_sqr * i;
            for (self.board_history[start .. start + extent_sqr]) |*number_opt| {
                const byte = try reader.takeByte();
                number_opt.* = if (byte == 0xff) null else @intCast(byte);
            }
            for (self.candidate_masks_history[start .. start + extent_sqr]) |*mask| {
                mask.* = try reader.takeInt(MaskType, .little);
            }
        }

        return self;
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.board_history);
        self.allocator.free(self.candidate_masks_history);
        self.allocator.free(self.selected_cells_full);
        self.allocator.free(self.candidate_masks);
    }

    fn get_board_history_slice(self: Self, history_index: u32) []?u4 {
        const cell_count = self.board.extent * self.board.extent;
        const start = cell_count * history_index;
        const stop = start + cell_count;

        return self.board_history[start..stop];
    }

    fn get_candidate_masks_history_slice(self: Self, history_index: u32) []MaskType {
        const cell_count = self.board.extent * self.board.extent;
        const start = cell_count * history_index;
        const stop = start + cell_count;

        return self.candidate_masks_history[start..stop];
    }

    fn push_state_to_history(self: *Self) void {
        const board_unchanged = std.mem.eql(?u4, self.get_board_history_slice(self.history_index), self.board.numbers());
        const candidate_masks_unchanged = std.mem.eql(MaskType, self.get_candidate_masks_history_slice(self.history_index), self.candidate_masks);

        // Don't record noop actions
        if (board_unchanged and candidate_masks_unchanged) {
            return;
        }

        if (self.history_index + 1 < MaxHistorySize) {
            // History has space
            self.history_index += 1;
            self.max_history_index = self.history_index;

            self.save_state_to_history(self.history_index);
        } else {
            // History is full, drop the oldest entry
            const cell_count = self.board.extent * self.board.extent;
            const kept_cell_count = (MaxHistorySize - 1) * cell_count;

            std.mem.copyForwards(?u4, self.board_history[0..kept_cell_count], self.board_history[cell_count..]);
            std.mem.copyForwards(MaskType, self.candidate_masks_history[0..kept_cell_count], self.candidate_masks_history[cell_count..]);

            self.max_history_index = self.history_index;

            self.save_state_to_history(self.history_index);
        }
    }

    fn save_state_to_history(self: *Self, index: u32) void {
        @memcpy(self.get_board_history_slice(index), self.board.numbers());
        @memcpy(self.get_candidate_masks_history_slice(index), self.candidate_masks);
    }

    fn load_state_from_history(self: *Self, index: u32) void {
        @memcpy(self.board.numbers(), self.get_board_history_slice(index));
        @memcpy(self.candidate_masks, self.get_candidate_masks_history_slice(index));
    }

    pub fn apply_player_event(self: *Self, action: PlayerAction) void {
        switch (self.flow) {
            .Normal => {
                self.apply_player_event_normal_flow(action);
            },
            .WaitingForHintValidation => {
                switch (action) {
                    .get_hint => {
                        self.player_apply_hint();
                    },
                    .discard_hint => {
                        self.player_discard_hint();
                    },
                    else => {
                        @panic("Invalid action while waiting for hint validation");
                    },
                }
            },
        }

        self.validation_error = validator.check_board_for_errors(&self.board, self.candidate_masks);
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
            .clear_selected_cell => {
                self.player_clear_selected_cell();
            },
            .undo => {
                self.player_undo();
            },
            .redo => {
                self.player_redo();
            },
            .fill_candidates => {
                self.player_fill_candidates();
            },
            .fill_all_candidates => {
                self.player_fill_candidates_all();
            },
            .clear_all_candidates => {
                self.player_clear_candidates();
            },
            .get_hint => {
                self.player_get_hint();
            },
            .solve_board => {
                self.player_solve_board();
            },
            else => {
                @panic("Unexpected player event in normal flow!");
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

            const extent = self.board.rules.type.extent();
            assert(all(current_pos < i32_2{ @intCast(extent), @intCast(extent) }));

            current_pos += .{ event.x_offset, event.y_offset };

            const extent_i32: i32 = @intCast(extent);
            inline for (.{ &current_pos[0], &current_pos[1] }) |coord| {
                if (coord.* < 0) {
                    coord.* += extent_i32;
                } else if (coord.* >= extent_i32) {
                    coord.* -= extent_i32;
                }
            }

            self.selected_cells[0] = self.board.cell_index_from_coord(@intCast(current_pos));
        }
    }

    fn player_set_number(self: *Self, number: u4) void {
        if (number < self.board.extent and self.selected_cells.len > 0) {
            solver_logical.place_number_remove_trivial_candidates(&self.board, self.candidate_masks, self.selected_cells[0], number);
            self.push_state_to_history();
        }
    }

    fn player_toggle_candidate(self: *Self, number: u4) void {
        if (number < self.board.extent and self.selected_cells.len > 0) {
            const cell_index = self.selected_cells[0];

            if (self.board.numbers()[cell_index] == null) {
                self.candidate_masks[cell_index] ^= self.board.mask_for_number(number);
            }

            self.push_state_to_history();
        }
    }

    fn player_clear_selected_cell(self: *Self) void {
        if (self.selected_cells.len > 0) {
            const cell_index = self.selected_cells[0];

            self.board.numbers()[cell_index] = null;
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
        const extent_sqr = self.board.extent * self.board.extent;
        @memcpy(self.candidate_masks, solver_logical.trivial_candidate_masks_max(&self.board)[0..extent_sqr]);

        self.push_state_to_history();
    }

    fn player_fill_candidates_all(self: *Self) void {
        const full_mask = self.board.full_candidate_mask();

        for (self.candidate_masks, 0..) |*cell_candidate_mask, cell_index| {
            if (self.board.numbers()[cell_index] == null) {
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
        if (solver_logical.find_easiest_known_technique(self.board, self.candidate_masks)) |solver_technique| {
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
                    solver_logical.apply_technique(&self.board, self.candidate_masks, technique);

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

    fn player_discard_hint(self: *Self) void {
        if (self.solver_event != null) {
            self.solver_event = null;
            self.flow = .Normal;
        } else {
            @panic("Solver event not found!");
        }
    }

    fn player_solve_board(self: *Self) void {
        const solution_count = solver.solve(self.allocator, &self.board, .{}) catch |err| {
            switch (err) {
                error.UnsupportedMaxSolutionCount, // This shouldn't happen as we're passing default flags
                error.UnsupportedDLXSolverChessRules, // FIXME The compiler can't prove that this doesn't happen apparently
                error.OutOfMemory,
                => {
                    return; // FIXME solve failed with an error, tell the player somehow
                },
            }
        };

        if (solution_count > 0) {
            self.player_clear_candidates();
            // NOTE: Already done in the body of clear_candidates.
            // push_state_to_history(game);
        } else {
            // FIXME solve was not possible, tell the player somehow
        }
    }
};

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
    discard_hint,
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
