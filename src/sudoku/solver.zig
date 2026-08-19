const std = @import("std");

const board = @import("board.zig");

const dancing_links = @import("solver_dancing_links.zig");
const backtracking = @import("solver_backtracking.zig");

pub const Options = struct {
    solution_count_max: u32 = 1,
    fill_solution: bool = true,
};

// Returns the number of solutions found (capped by solution_count_max)
// Call a specific solver directly if you need more control
pub fn solve(allocator: std.mem.Allocator, board_state: *board.Board, options: Options) !u32 {
    const using_chess_rules = board_state.rules.chess_anti_king or board_state.rules.chess_anti_knight;

    if (!using_chess_rules) {
        return dancing_links.solve(allocator, board_state, .{
            .solution_count_max = options.solution_count_max,
            .fill_solution = options.fill_solution,
        }) catch |err| {
            switch (err) {
                error.UnsupportedDLXSolverChessRules => unreachable, // We just made sure this was not possible
                error.OutOfMemory => return err,
            }
        };
    } else {
        // Fallback on backtracking
        return backtracking.solve(board_state, .{
            .solution_count_max = options.solution_count_max,
            .fill_solution = options.fill_solution,
        });
    }
}
