const board_state = @import("board_legacy.zig");

const dancing_links = @import("solver_dancing_links.zig");
const backtracking = @import("solver_backtracking.zig");

pub const Algorithm = union(enum) {
    dancing_links: dancing_links.Options,
    sorted_backtracking: struct {
        recursive: bool = true,
    },
};

pub fn solve(board: *board_state.BoardState, algorithm: Algorithm) bool {
    switch (algorithm) {
        .dancing_links => |options| {
            return dancing_links.solve(board, options);
        },
        .sorted_backtracking => |sorted_backtracking| {
            return backtracking.solve(board, sorted_backtracking.recursive);
        },
    }
}
