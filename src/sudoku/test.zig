const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const game = @import("game.zig");
const @"u32_2" = game.u32_2;
const @"u16_2" = game.u16_2;
const event = @import("event.zig");

const test_seed: u64 = 0xC0FFEE42DEADBEEF;

test "Critical path" {
    const extent = u32_2{ 9, 9 };

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try game.create_game_state(allocator, extent, test_seed);
    defer game.destroy_game_state(allocator, &game_state);
}
