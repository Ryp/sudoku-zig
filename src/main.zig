const std = @import("std");
const assert = std.debug.assert;

const sdl2 = @import("sdl2/sdl2_backend.zig");
const sudoku = @import("sudoku/game.zig");

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
        sudoku.GameType{ .regular = .{
            .box_w = box_w,
            .box_h = box_h,
        } }
    else
        sudoku.GameType{
            .jigsaw = .{
                .size = box_w * box_h, // FIXME use different format like 3x3 for regular
                .box_indices_string = args[4],
            },
        };

    const sudoku_string = if (args.len > 3) args[3] else "";

    // Create game state
    var game = try sudoku.create_game_state(gpa_allocator, game_type, sudoku_string);
    defer sudoku.destroy_game_state(gpa_allocator, &game);

    try sdl2.execute_main_loop(gpa_allocator, &game);
}
