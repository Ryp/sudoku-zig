const board_state = @import("board_legacy.zig");
const dancing_links = @import("generator_dancing_links.zig");
const naive = @import("generator_naive.zig");

pub const Algorithm = union(enum) {
    dancing_links: struct {
        difficulty: u32,
    },
    naive,
};

pub fn generate(board: *board_state.BoardState, algorithm: Algorithm, seed: u64) void {
    switch (algorithm) {
        .dancing_links => |options| {
            dancing_links.generate(board, seed, options.difficulty);
        },
        .naive => {
            naive.generate(board, seed);
        },
    }
}
