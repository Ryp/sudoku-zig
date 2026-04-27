const rules = @import("rules.zig");
const board = @import("board.zig");
const dancing_links = @import("generator_dancing_links.zig");

pub const Algorithm = union(enum) {
    dancing_links: struct {
        difficulty: u32,
    },
};

pub fn generate(board_rules: rules.Rules, seed: u64, algorithm: Algorithm) board.Board {
    switch (algorithm) {
        .dancing_links => |options| {
            return dancing_links.generate(board_rules, seed, options.difficulty);
        },
    }
}
