const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const sudoku = @import("game.zig");

test "Critical path" {
    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try sudoku.create_game_state(allocator, 3, 3);
    defer sudoku.destroy_game_state(allocator, &game_state);
}
