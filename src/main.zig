const std = @import("std");
const assert = std.debug.assert;

const game = @import("sudoku/game.zig");
const board_generic = @import("sudoku/board_generic.zig");

const clap = @import("clap.zig");
const sdl = @import("frontend/sdl.zig");

pub fn main_with_allocator(allocator: std.mem.Allocator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-W, --box_width <u32>   Box width for regular sudokus (default: 3)
        \\-H, --box_height <u32>  Box height for regular sudokus (default: 3)
        \\-j, --jigsaw <str>      Region indices string for jigsaw sudokus
        \\<str>                   Sudoku string (you can use '.' for empty cells).
        \\                        Unset this if you want to have a sudoku board generated for you.
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.helpToFile(.stderr(), clap.Help, &params, .{});
    }

    var board_type: board_generic.BoardType = undefined;

    if (res.args.jigsaw) |jigsaw_string| {
        const jigsaw_extent = try get_extent_from_jigsaw_string(jigsaw_string);

        board_type = .{
            .jigsaw = .{
                .extent = jigsaw_extent,
                .box_indices_string = jigsaw_string,
            },
        };
    } else {
        const box_w = res.args.box_width orelse 3;
        const box_h = res.args.box_height orelse 3;

        board_type = .{ .regular = .{
            .box_extent = .{ box_w, box_h },
        } };
    }

    const board_extent = board_type.extent();

    // Scalarize extent
    inline for (board_generic.MinExtent..board_generic.MaxExtent + 1) |comptime_extent| {
        if (board_extent == comptime_extent) {
            var game_state = try game.State(comptime_extent).init(allocator, board_type, res.positionals[0]);
            defer game_state.deinit(allocator);

            try sdl.execute_main_loop(comptime_extent, &game_state, allocator);

            break;
        }
    } else {
        @panic("Invalid sudoku extent!");
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    // const allocator = std.heap.page_allocator;

    try main_with_allocator(allocator);
}

fn get_extent_from_jigsaw_string(jigsaw_string: []const u8) !u32 {
    const string_len = jigsaw_string.len;

    for (board_generic.MinExtent..board_generic.MaxExtent + 1) |extent| {
        if (string_len == extent * extent) {
            return @intCast(extent);
        }
    }

    return error.InvalidJigsawStringLength;
}
