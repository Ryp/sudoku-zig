const std = @import("std");

const solver_logical = @import("solver_logical.zig");
const board_generic = @import("board_generic.zig");
const validator = @import("validator.zig");

pub fn grade_and_print_summary(extent: comptime_int, const_board: board_generic.State(extent)) void {
    // Create a dummy board we can modify
    var board = board_generic.State(extent).init(const_board.rules);

    @memcpy(&board.numbers, &const_board.numbers);

    var candidate_masks = solver_logical.trivial_candidate_masks(extent, &board);
    var technique_histogram = [_]u32{0} ** 8;

    while (solver_logical.find_easiest_known_technique(extent, board, &candidate_masks)) |technique| {
        const technique_index = @intFromEnum(technique);
        technique_histogram[technique_index] += 1;

        solver_logical.apply_technique(extent, &board, &candidate_masks, technique);

        if (validator.check_board_for_errors(extent, &board, null)) |validation_error| {
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
