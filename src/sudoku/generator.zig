const board_generic = @import("board_generic.zig");
const dancing_links = @import("generator_dancing_links.zig");
const naive = @import("generator_naive.zig");

pub const Algorithm = union(enum) {
    dancing_links: struct {
        difficulty: u32,
    },
    naive,
};

pub fn generate(extent: comptime_int, rules: board_generic.Rules, seed: u64, algorithm: Algorithm) board_generic.State(extent) {
    switch (algorithm) {
        .dancing_links => |options| {
            return dancing_links.generate(extent, rules, seed, options.difficulty);
        },
        .naive => {
            return naive.generate(extent, rules, seed);
        },
    }
}
