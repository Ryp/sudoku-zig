const std = @import("std");
const assert = std.debug.assert;

const board_generic = @import("board_generic.zig");
const RegionSet = board_generic.RegionSet;

const known_boards = @import("known_boards.zig");

pub const Options = struct {
    recursive: bool = false,
};

pub fn solve(extent: comptime_int, board: *board_generic.State(extent), options: Options) bool {
    var free_cell_list_full: [board.extent_sqr]CellInfo = undefined;
    const free_cell_list = populate_free_list(extent, board, &free_cell_list_full);

    sort_free_cell_list(extent, board, free_cell_list);

    if (options.recursive) {
        return solve_backtracking_recursive(extent, board, free_cell_list, 0);
    } else {
        return solve_backtracking_iterative(extent, board, free_cell_list);
    }
}

const CellInfo = struct {
    index: u8,
    col: u4,
    row: u4,
};

fn solve_backtracking_recursive(extent: comptime_int, board: *board_generic.State(extent), free_cell_list: []CellInfo, list_index: u32) bool {
    if (list_index >= free_cell_list.len) {
        return true;
    }

    const free_cell: CellInfo = free_cell_list[list_index];

    const valid_candidates = cell_valid_candidates(extent, board, free_cell);

    // Now let's place a number from the list of candidates and see if it sticks
    const cell_number = &board.numbers[free_cell.index];

    for (valid_candidates, 0..) |is_valid, number| {
        if (is_valid) {
            cell_number.* = @intCast(number);

            if (solve_backtracking_recursive(extent, board, free_cell_list, list_index + 1)) {
                return true;
            }
        }
    }

    cell_number.* = null;
    return false;
}

fn solve_backtracking_iterative(extent: comptime_int, board: *board_generic.State(extent), free_cell_list: []CellInfo) bool {
    var current_guess_full = std.mem.zeroes([board.extent_sqr]u4);
    var current_guess = current_guess_full[0..free_cell_list.len];

    var list_index: u32 = 0;

    while (list_index < free_cell_list.len) main: {
        const free_cell = free_cell_list[list_index];

        const valid_candidates = cell_valid_candidates(extent, board, free_cell);

        const cell_number = &board.numbers[free_cell.index];
        const start: u32 = current_guess[list_index];

        for (valid_candidates[start..], start..) |is_valid, number| {
            if (is_valid) {
                cell_number.* = @intCast(number);
                current_guess[list_index] = @intCast(number + 1);

                list_index += 1;

                break :main;
            }
        } else {
            cell_number.* = null;
            current_guess[list_index] = 0;

            // Backtracking at index zero means we didn't find a solution
            if (list_index == 0) {
                return false;
            } else {
                list_index -= 1;
            }
        }
    }

    return true;
}

fn cell_valid_candidates(extent: comptime_int, board: *const board_generic.State(extent), cell_info: CellInfo) [board.extent]bool {
    const box = board.regions.box_indices[cell_info.index];

    var valid_candidates: [board.extent]bool = .{true} ** board.extent;

    inline for (.{ board.regions.col(cell_info.col), board.regions.row(cell_info.row), board.regions.box(box) }) |region| {
        for (region) |cell_index| {
            if (board.numbers[cell_index]) |number| {
                valid_candidates[number] = false;
            }
        }
    }

    return valid_candidates;
}

fn populate_free_list(extent: comptime_int, board: *const board_generic.State(extent), free_cell_list_full: []CellInfo) []CellInfo {
    var list_index: u8 = 0;

    for (board.numbers, 0..) |cell_number, cell_index| {
        if (cell_number == null) {
            const cell_coord = board.cell_coord_from_index(cell_index);

            free_cell_list_full[list_index] = CellInfo{
                .index = @intCast(cell_index),
                .col = @intCast(cell_coord[0]),
                .row = @intCast(cell_coord[1]),
            };
            list_index += 1;
        }
    }

    return free_cell_list_full[0..list_index];
}

fn sort_free_cell_list(extent: comptime_int, board: *const board_generic.State(extent), free_cell_list: []CellInfo) void {
    const full_mask = board.full_candidate_mask();

    var region_type_masks: [3][board.extent]u16 = undefined;

    inline for (.{ RegionSet.Col, RegionSet.Row, RegionSet.Box }) |set| {
        const set_index = @intFromEnum(set);
        for (board.regions.all[set_index], &region_type_masks[set_index]) |region, *region_mask| {
            region_mask.* = full_mask;

            for (region) |cell_index| {
                if (board.numbers[cell_index]) |number| {
                    region_mask.* &= ~board.mask_for_number(number);
                }
            }
        }
    }

    var candidate_counts: [board.extent_sqr]u8 = .{0} ** board.extent_sqr;

    for (&candidate_counts, 0..) |*candidate_count, cell_index| {
        const cell_coord = board.cell_coord_from_index(cell_index);

        const col = cell_coord[0];
        const row = cell_coord[1];
        const box = board.regions.box_indices[cell_index];

        const mask = region_type_masks[0][col] & region_type_masks[1][row] & region_type_masks[2][box];
        candidate_count.* = @popCount(mask);
    }

    // Hack to pass to comparator
    const candidate_counts_slice: []u8 = candidate_counts[0..];

    std.sort.pdq(CellInfo, free_cell_list, candidate_counts_slice, cell_info_candidate_count_compare_less);
}

fn cell_info_candidate_count_compare_less(candidate_counts: []u8, lhs: CellInfo, rhs: CellInfo) bool {
    return candidate_counts[lhs.index] < candidate_counts[rhs.index];
}

test {
    const board_type = board_generic.BoardType{ .regular = .{
        .box_extent = .{ 3, 3 },
    } };

    var solver_board = board_generic.State(board_type.extent()).init(board_type);

    const known_board = known_boards.easy_000;

    solver_board.fill_board_from_string(known_board.board);

    const solved = solve(solver_board.extent, &solver_board, .{});
    try std.testing.expect(solved);

    var solution_board = board_generic.State(9).init(solver_board.board_type);

    solution_board.fill_board_from_string(known_board.solution);

    try std.testing.expect(std.mem.eql(?u4, &solver_board.numbers, &solution_board.numbers));
}
