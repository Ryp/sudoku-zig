const std = @import("std");

const solver_logical = @import("solver_logical.zig");
const board = @import("board.zig");
const validator = @import("validator.zig");

pub fn grade_and_print_summary(const_board: board.Board) void {
    // Create a dummy board we can modify
    var board_state: board.Board = .init(const_board.rules);

    @memcpy(board_state.numbers(), const_board.numbers_const());

    var candidate_masks_max = solver_logical.trivial_candidate_masks_max(&board_state);
    const candidate_masks = candidate_masks_max[0 .. const_board.extent * const_board.extent];

    const TechniqueUnionTypeInfo = @typeInfo(solver_logical.Technique).@"union";
    var technique_histogram = [_]u32{0} ** TechniqueUnionTypeInfo.fields.len;

    while (solver_logical.find_easiest_known_technique(board_state, candidate_masks)) |technique| {
        const technique_index = @intFromEnum(technique);
        technique_histogram[technique_index] += 1;

        solver_logical.apply_technique(&board_state, candidate_masks, technique);

        if (validator.check_board_for_errors(&board_state, null)) |validation_error| {
            std.debug.print("The board has a validation error: {}\n", .{validation_error});
            return;
        }
    }

    std.debug.print("Grading summary:\n", .{});

    for (technique_histogram, 0..) |count, bucket_index| {
        if (count > 0) {
            const Tag = TechniqueUnionTypeInfo.tag_type.?;
            const technique = @as(Tag, @enumFromInt(bucket_index));
            std.debug.print("   '{s}' was applied {} times\n", .{ @tagName(technique), count });
        }
    }

    for (board_state.numbers()) |number_opt| {
        if (number_opt == null) {
            std.debug.print("WARNING: Couldn't fully solve this board with logic!\n", .{});
            break;
        }
    }
}
