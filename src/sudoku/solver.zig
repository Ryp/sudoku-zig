const board_generic = @import("board_generic.zig");

const dancing_links = @import("solver_dancing_links.zig");
const backtracking = @import("solver_backtracking.zig");
const logical = @import("solver_logical.zig");

pub const Options = union(enum) {
    logical,
    dancing_links: dancing_links.Options,
    sorted_backtracking: backtracking.Options,
};

pub fn solve(extent: comptime_int, board: *board_generic.State(extent), generic_options: Options) bool {
    switch (generic_options) {
        .logical => {
            return logical.solve(extent, board);
        },
        .dancing_links => |options| {
            return dancing_links.solve(extent, board, options);
        },
        .sorted_backtracking => |options| {
            return backtracking.solve(extent, board, options);
        },
    }
}
