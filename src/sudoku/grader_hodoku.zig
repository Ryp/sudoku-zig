// HoDoKu style grading. The puzzle score is the sum of the scores of every step
// of the solve path. The difficulty level can't be lower than the level of the
// hardest step, and a high enough total score bumps the sudoku into the
// following levels.
//
// See also:
// https://github.com/wyzelli/Hodoku2
// https://hodoku.sourceforge.net/en/docs_cre.php

const std = @import("std");

const board = @import("board.zig");
const solver_logical = @import("solver_logical.zig");

const Technique = solver_logical.Technique;

// Number of cells the reference score thresholds below are calibrated for
pub const ReferenceCellCount = 81;

// Default difficulty levels with their max score thresholds
pub const Level = enum {
    easy, // <= 800
    medium, // <= 1000
    hard, // <= 1600
    unfair, // <= 1800
    extreme,

    pub fn max_score(level: Level) u64 {
        return switch (level) {
            .easy => 800,
            .medium => 1000,
            .hard => 1600,
            .unfair => 1800,
            .extreme => std.math.maxInt(u64),
        };
    }
};

pub const Grade = struct {
    score: u64, // If not solved, this is a lower bound
    level: Level,
};

pub const ScoreWindow = struct {
    min: f64,
    max: f64,
};

// Score window of a difficulty level, in reference score units
pub fn score_window(level: Level) ScoreWindow {
    return .{
        .min = if (level == .easy) 0 else @floatFromInt(@as(Level, @enumFromInt(@intFromEnum(level) - 1)).max_score() + 1),
        .max = if (level == .extreme) std.math.inf(f64) else @floatFromInt(level.max_score()),
    };
}

pub fn any_score_window() ScoreWindow {
    return .{
        .min = 0,
        .max = std.math.inf(f64),
    };
}

// The original code is only really valid for 3x3 boards, so try to normalize the score for different extents
pub fn normalized_score(score: u64, cell_count: u32) f64 {
    return @as(f64, @floatFromInt(score * ReferenceCellCount)) / @as(f64, @floatFromInt(cell_count));
}

pub fn grade(const_board: *const board.Board) !Grade {
    var board_state = const_board.*; // Board is POD

    var candidate_masks_max = solver_logical.trivial_candidate_masks_max(&board_state);
    const candidate_masks = candidate_masks_max[0 .. board_state.extent * board_state.extent];

    var score: u64 = 0;
    var level: Level = .easy;

    // Our default technique order matches HoDoKu's cheapest-first score order
    while (solver_logical.find_easiest_known_technique(board_state, candidate_masks)) |technique| {
        score += technique_score(technique);
        level = @enumFromInt(@max(@intFromEnum(level), @intFromEnum(technique_level(technique))));

        solver_logical.apply_technique(&board_state, candidate_masks, technique);
    }

    // The level can't be lower than the hardest step, but a high enough total
    // score bumps the sudoku into the following levels
    while (score > level.max_score()) {
        level = @enumFromInt(@intFromEnum(level) + 1);
    }

    if (!board_state.is_full()) {
        return error.GraderNoSolutionFound;
    }

    return .{ .score = score, .level = level };
}

fn technique_score(technique: Technique) u32 {
    return switch (technique) {
        .naked_single => 4,
        .hidden_single => 14,
        .pointing_line => 50, // HoDoKu calls this Locked Candidates Type 1 (Pointing)
        .box_line_reduction => 50, // HoDoKu calls this Locked Candidates Type 2 (Claiming)
        .naked_pair => 60,
        .hidden_pair => 70,
    };
}

fn technique_level(technique: Technique) Level {
    return switch (technique) {
        .naked_single, .hidden_single => .easy,
        .pointing_line, .box_line_reduction, .naked_pair, .hidden_pair => .medium,
    };
}

test "score windows" {
    try std.testing.expectEqual(ScoreWindow{ .min = 0, .max = 800 }, score_window(.easy));
    try std.testing.expectEqual(ScoreWindow{ .min = 801, .max = 1000 }, score_window(.medium));
    try std.testing.expectEqual(ScoreWindow{ .min = 1801, .max = std.math.inf(f64) }, score_window(.extreme));
    try std.testing.expectEqual(@as(f64, 1000), normalized_score(1000, 81));
    try std.testing.expectEqual(@as(f64, 1000), normalized_score(2000, 162));
}
