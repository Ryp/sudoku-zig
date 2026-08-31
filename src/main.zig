const std = @import("std");
const assert = std.debug.assert;

const game = @import("sudoku/game.zig");
const board = @import("sudoku/board.zig");
const grader = @import("sudoku/grader.zig");
const rules = @import("sudoku/rules.zig");
const save_state = @import("sudoku/save_state.zig");

const clap = @import("clap.zig");
const sdl = @import("frontend/sdl.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-W, --box_width <u32>   Box width for regular sudokus (default: 3)
        \\-H, --box_height <u32>  Box height for regular sudokus (default: 3)
        \\-j, --jigsaw <str>      Region indices string for jigsaw sudokus
        \\--king                  Chess anti-king's constraint
        \\--knight                Chess anti-knight's constraint
        \\--load <str>            Load save file
        \\<str>                   Sudoku string (use '.' for empty cells).
        \\                        Unset this if you want to have a sudoku board generated for you.
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        return;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.helpToFile(io, .stderr(), clap.Help, &params, .{});
    }

    var game_state: game.State = undefined;

    if (res.args.load) |save_state_path| {
        var save_state_file = if (std.Io.Dir.cwd().openFile(io, save_state_path, .{})) |f| f else |err| {
            std.debug.print("Failed to open save state file '{s}': ", .{save_state_path});
            return err;
        };
        defer save_state_file.close(io);

        var reader_buffer: [4096]u8 = undefined;
        var reader = save_state_file.reader(io, &reader_buffer);

        game_state = save_state.load(&reader.interface, allocator) catch |err| {
            std.debug.print("Failed to load save file: {}\n", .{err});
            return err;
        };
    } else {
        var board_rules: rules.Rules = .{ .type = undefined };

        if (res.args.jigsaw) |jigsaw_string| {
            const jigsaw_extent = get_extent_from_jigsaw_string(jigsaw_string) catch {
                return; // We already printed a helpful message, just return
            };

            board_rules.type = .{
                .jigsaw = .{
                    .extent = jigsaw_extent,
                    .box_indices_max = rules.fill_jigsaw_box_indices_from_string_max(jigsaw_extent, jigsaw_string) catch {
                        return; // We already printed a helpful message, just return
                    },
                },
            };
        } else {
            const box_w = res.args.box_width orelse 3;
            const box_h = res.args.box_height orelse 3;

            board_rules.type = .{ .regular = .{
                .box_extent = .{ box_w, box_h },
            } };
        }

        board_rules.chess_anti_king = res.args.king != 0;
        board_rules.chess_anti_knight = res.args.knight != 0;

        game_state = game.State.init(io, allocator, board_rules, res.positionals[0]) catch |err| {
            switch (err) {
                error.InvalidSudokuBoardExtent,
                error.InvalidSudokuStringLength,
                error.InvalidSudokuStringCharacter,
                error.InvalidSudokuClue,
                error.InvalidSudokuGeneratorRules,
                error.UnsupportedDLXGeneratorChessRules,
                => {
                    return; // We already printed a helpful message, just return
                },
                error.OutOfMemory => {
                    return err;
                },
            }
        };
    }
    defer game_state.deinit();

    const board_string_max = game_state.board.string_from_board_max();
    const board_string = board_string_max[0 .. game_state.board.extent * game_state.board.extent];

    std.debug.print("Board: {s}\n", .{board_string});

    grader.grade_and_print_summary(allocator, &game_state.board) catch |err| switch (err) {
        else => {
            return err; // FIXME Catch-all
        },
    };

    sdl.execute_main_loop(&game_state, allocator) catch |err| switch (err) {
        else => {
            return err; // FIXME Catch-all, as there's way more errors that can happen here
        },
    };

    const exit_board_string_max = game_state.board.string_from_board_max();
    const exit_board_string = exit_board_string_max[0 .. game_state.board.extent * game_state.board.extent];

    std.debug.print("Board at exit: {s}\n", .{exit_board_string});

    if (true) {
        const output_path = "latest.sdku";
        const output_file = std.Io.Dir.cwd().createFile(io, output_path, .{}) catch |err| {
            std.debug.print("Error creating output file: {s}\n", .{output_path});
            return err;
        };
        errdefer std.Io.Dir.cwd().deleteFile(io, output_path) catch {}; // If we encounter an error, just delete the file and ignore failures
        defer output_file.close(io);

        var writer_buffer: [4096]u8 = undefined;
        var writer = output_file.writer(io, &writer_buffer);
        const io_writer = &writer.interface;

        try save_state.save(&game_state, io_writer);
    }
}

fn get_extent_from_jigsaw_string(jigsaw_string: []const u8) !u32 {
    const string_len = jigsaw_string.len;

    for (board.MinExtent..board.MaxExtent + 1) |extent| {
        if (string_len == extent * extent) {
            return @intCast(extent);
        }
    }

    std.debug.print("error: invalid jigsaw string length {}, only perfect squares are valid\n", .{jigsaw_string.len});
    return error.InvalidJigsawStringLength;
}
