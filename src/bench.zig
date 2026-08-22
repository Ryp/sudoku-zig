const std = @import("std");

const board = @import("sudoku/board.zig");
const rules = @import("sudoku/rules.zig");
const solver = @import("sudoku/solver.zig");
const known_boards = @import("sudoku/known_boards.zig");
const generator = @import("sudoku/generator.zig");
const grader_hodoku = @import("sudoku/grader_hodoku.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const Iterations = 2;
    const Seed: u64 = 0xDEAD_BEEF_CAFE_BABE;

    std.debug.print("Generator, best/average of {} runs:\n", .{Iterations});

    inline for (.{
        rules.Regular3x3,
        rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 4, 3 } } } },
        rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 4, 4 } } } },
        known_boards.jigsaw9.rules,
    }, 0..) |board_rules, rules_index| {
        for ([_]struct { label: []const u8, target: grader_hodoku.ScoreWindow }{
            .{ .label = "any", .target = .{ .min = 0, .max = std.math.inf(f64) } },
            .{ .label = "medium", .target = grader_hodoku.score_window(.medium) },
            .{ .label = "hard", .target = grader_hodoku.score_window(.hard) },
        }) |entry| {
            var best_ns: u64 = std.math.maxInt(u64);
            var total_ns: u64 = 0;

            for (0..Iterations) |_| {
                const time_start = std.Io.Timestamp.now(io, .awake);

                _ = try generator.generate(allocator, board_rules, Seed, .{ .dancing_links = .{ .target = entry.target } });

                const time_end = std.Io.Timestamp.now(io, .awake);
                const elapsed_ns: u64 = @intCast(time_start.durationTo(time_end).nanoseconds);

                best_ns = @min(best_ns, elapsed_ns);
                total_ns += elapsed_ns;
            }

            const best_ms = @as(f64, @floatFromInt(best_ns)) / std.time.ns_per_ms;
            const average_ms = @as(f64, @floatFromInt(total_ns / Iterations)) / std.time.ns_per_ms;

            std.debug.print("{}: {s:>7} best {d:>8.3} ms, average {d:>8.3} ms\n", .{
                rules_index,
                entry.label,
                best_ms,
                average_ms,
            });
        }
    }
}
