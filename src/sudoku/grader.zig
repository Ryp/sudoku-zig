const std = @import("std");

const game = @import("game.zig");
const solver_logical = @import("solver_logical.zig");

pub fn grade_and_print_summary(allocator: std.mem.Allocator, const_board: game.BoardState) !void {
    // Create a dummy board we can modify
    var board = try game.BoardState.create(allocator, const_board.game_type);
    defer board.destroy(allocator);

    @memcpy(board.numbers, const_board.numbers);

    const candidate_masks = try allocator.alloc(u16, board.numbers.len);
    defer allocator.free(candidate_masks);

    for (candidate_masks) |*candidate_mask| {
        candidate_mask.* = 0;
    }

    var technique_histogram = [_]u32{0} ** 8;

    game.fill_candidate_mask(board, candidate_masks);

    while (true) {
        solver_logical.solve_trivial_candidates(&board, candidate_masks);

        if (solver_logical.find_easiest_known_technique(board, candidate_masks)) |technique| {
            const technique_index = @intFromEnum(technique);
            technique_histogram[technique_index] += 1;

            solver_logical.apply_technique(&board, candidate_masks, technique);
        } else {
            break;
        }

        if (game.check_board_for_validation_errors(board, candidate_masks)) |validation_error| {
            std.debug.print("The board has a validation error: {}\n", .{validation_error});
            return;
        }
    }

    std.debug.print("Grading summary:\n", .{});

    for (technique_histogram, 0..) |count, bucket_index| {
        if (count > 0) {
            const Tag = @typeInfo(solver_logical.Technique).@"union".tag_type.?;
            const technique = @as(Tag, @enumFromInt(bucket_index));
            std.debug.print("   '{s}' was applied {} times\n", .{ @tagName(technique), count });
        }
    }

    for (board.numbers) |number_opt| {
        if (number_opt == null) {
            std.debug.print("WARNING: Couldn't fully solve this board with logic!\n", .{});
            break;
        }
    }
}
