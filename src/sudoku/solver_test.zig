const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const sudoku = @import("game.zig");
const solver = @import("solver.zig");
const solver_logical = @import("solver_logical.zig");
const boards = @import("boards.zig");

test "Box-line removal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Create game board
    var board = try sudoku.BoardState.create(allocator, .{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } });
    defer board.destroy(allocator);

    // Start with an empty board
    sudoku.fill_empty_board(board.numbers);

    const candidate_masks = try allocator.alloc(u16, board.numbers.len);
    defer allocator.free(candidate_masks);

    const full_mask = board.full_candidate_mask();

    // Fill candidate masks fully
    for (candidate_masks) |*cell_candidate_mask| {
        cell_candidate_mask.* = full_mask;
    }

    // Make sure that there's no hit for the initial board
    if (solver_logical.find_box_line_reduction(board, candidate_masks)) |_| {
        try expect(false);
    }

    const number: u4 = 0;

    // Remove candidates until we can apply the box-line solver
    for (3..9) |row_index| {
        const mask = board.mask_for_number(number);
        const cell_index = board.cell_index_from_coord(sudoku.u32_2{ 0, @intCast(row_index) });
        candidate_masks[cell_index] &= ~mask;
    }

    // Make sure we get a hit
    if (solver_logical.find_box_line_reduction(board, candidate_masks)) |box_line_reduction| {
        try expectEqual(number, box_line_reduction.number);

        // Apply the solver event
        solver_logical.apply_technique(&board, candidate_masks, .{ .box_line_reduction = box_line_reduction });

        // Make sure we don't hit again after applying the solver event
        if (solver_logical.find_box_line_reduction(board, candidate_masks)) |_| {
            try expect(false);
        }
    } else {
        try expect(false);
    }

    // Re-Fill candidate masks fully
    for (candidate_masks) |*cell_candidate_mask| {
        cell_candidate_mask.* = full_mask;
    }

    // Remove candidates until we can apply the box-line solver
    for (3..9) |col_index| {
        const mask = board.mask_for_number(number);
        const cell_index = board.cell_index_from_coord(sudoku.u32_2{ @intCast(col_index), 0 });
        candidate_masks[cell_index] &= ~mask;
    }

    if (solver_logical.find_box_line_reduction(board, candidate_masks)) |box_line_reduction| {
        try expectEqual(number, box_line_reduction.number);
    } else {
        try expect(false);
    }
}

test "Solver critical path" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Create game board
    var board = try sudoku.BoardState.create(allocator, .{ .regular = .{
        .box_w = 3,
        .box_h = 3,
    } });
    defer board.destroy(allocator);

    sudoku.fill_board_from_string(board.numbers, boards.easy_000.board, board.extent);

    try expectEqual(board.extent, 9);

    const solved = solver.solve(&board, .{ .dancing_links = .{} });
    try expect(solved);

    // Compare with solution
    const solution_board = try allocator.alloc(u5, board.extent * board.extent);
    defer allocator.free(solution_board);

    sudoku.fill_board_from_string(solution_board, boards.easy_000.solution, board.extent);

    try expect(std.mem.eql(u5, board.numbers, solution_board));
}
