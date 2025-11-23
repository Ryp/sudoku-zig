const std = @import("std");
const assert = std.debug.assert;

const game = @import("sudoku/game.zig");
const board_generic = @import("sudoku/board_generic.zig");
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

    // FIXME use different format for jigsaw (like 3x3 for regular)
    const box_w = try std.fmt.parseUnsigned(u32, args[1], 0);
    const box_h = try std.fmt.parseUnsigned(u32, args[2], 0);

    const sudoku_string = if (args.len > 3) args[3] else "";

    const board_type: board_generic.BoardType = if (args.len < 5)
        .{ .regular = .{ .box_extent = .{ box_w, box_h } } }
    else
        .{ .jigsaw = .{ .extent = box_w * box_h, .box_indices_string = args[4] } };

    const board_extent = board_type.extent();

    // Scalarize extent
    inline for (board_generic.MinExtent..board_generic.MaxExtent) |comptime_extent| {
        if (board_extent == comptime_extent) {
            var game_state = try game.State(comptime_extent).init(gpa_allocator, board_type, sudoku_string);
            defer game_state.deinit(gpa_allocator);

            grader.grade_and_print_summary(comptime_extent, game_state.board);

            try sdl.execute_main_loop(comptime_extent, &game_state, gpa_allocator);

            break;
        }
    } else {
        @panic("Invalid sudoku extent!");
    }
}
