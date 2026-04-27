const board = @import("board.zig");

const dancing_links = @import("solver_dancing_links.zig");
const backtracking = @import("solver_backtracking.zig");
const logical = @import("solver_logical.zig");

pub const Options = union(enum) {
    logical,
    dancing_links: dancing_links.Options,
    sorted_backtracking: backtracking.Options,
};

pub fn solve(board_state: *board.Board, generic_options: Options) bool {
    switch (generic_options) {
        .logical => {
            return logical.solve(board_state);
        },
        .dancing_links => |options| {
            return dancing_links.solve(board_state, options);
        },
        .sorted_backtracking => |options| {
            return backtracking.solve(board_state, options);
        },
    }
}
