const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const GameState = sudoku.GameState;

pub const HiddenSingleEvent = struct {
    cell_index: u32,
    deletion_mask: u16,
    number: u4,
};

pub const NakedPairEvent = struct {
    number: u4,
};

pub const SolverEventTag = enum {
    hidden_single,
    naked_pair,
};

pub const SolverEvent = union(SolverEventTag) {
    hidden_single: HiddenSingleEvent,
    naked_pair: NakedPairEvent,
};

fn allocate_event(game: *GameState) *SolverEvent {
    const new_event = &game.solver_events[game.solver_event_index];
    game.solver_event_index += 1;

    assert(game.solver_event_index < game.solver_events.len);

    return new_event;
}

pub fn allocate_hidden_single_event(game: *GameState) *HiddenSingleEvent {
    var new_event = allocate_event(game);
    new_event.* = .{
        .hidden_single = undefined,
    };
    return &new_event.hidden_single;
}

pub fn allocate_naked_pair_event(game: *GameState) *NakedPairEvent {
    var new_event = allocate_event(game);
    new_event.* = .{
        .naked_pair = undefined,
    };
    return &new_event.naked_pair;
}
