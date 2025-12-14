const rules = @import("rules.zig");
const board_generic = @import("board_generic.zig");
const dancing_links = @import("generator_dancing_links.zig");
const naive = @import("generator_naive.zig");

pub const Algorithm = union(enum) {
    dancing_links: struct {
        difficulty: u32,
    },
    naive,
};

pub fn generate(extent: comptime_int, board_rules: rules.Rules, seed: u64, algorithm: Algorithm) board_generic.State(extent) {
    switch (algorithm) {
        .dancing_links => |options| {
            return dancing_links.generate(extent, board_rules, seed, options.difficulty);
        },
        .naive => {
            return naive.generate(extent, board_rules, seed);
        },
    }
}
