const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("sudoku/game.zig");
const board_legacy = @import("sudoku/board_legacy.zig");
const grader = @import("sudoku/grader.zig");

const sdl = @import("frontend/sdl.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const gpa_allocator = gpa.allocator();
    // const allocator = std.heap.page_allocator;

    // Parse arguments
    const args = try std.process.argsAlloc(gpa_allocator);
    defer std.process.argsFree(gpa_allocator, args);

    assert(args.len >= 3);

    const box_w = try std.fmt.parseUnsigned(u32, args[1], 0);
    const box_h = try std.fmt.parseUnsigned(u32, args[2], 0);

    const game_type = if (args.len < 5)
        board_legacy.GameType{ .regular = .{
            .box_extent = .{ box_w, box_h },
        } }
    else
        board_legacy.GameType{
            .jigsaw = .{
                .size = box_w * box_h, // FIXME use different format like 3x3 for regular
                .box_indices_string = args[4],
            },
        };

    const sudoku_string = if (args.len > 3) args[3] else "";

    // Create game state
    var game = try sudoku.create_game_state(gpa_allocator, game_type, sudoku_string);
    defer sudoku.destroy_game_state(gpa_allocator, &game);

    try grader.grade_and_print_summary(gpa_allocator, game.board);

    try sdl.execute_main_loop(gpa_allocator, &game);
}
