const std = @import("std");
const assert = std.debug.assert;

const board_generic = @import("board_generic.zig");

const dancing_links_solver = @import("solver_dancing_links.zig");
const DoublyLink = dancing_links_solver.DoublyLink;
const ChoiceConstraintsIndices = dancing_links_solver.ChoiceConstraintsIndices;

pub fn generate(extent: comptime_int, board_type: board_generic.BoardType, seed: u64, difficulty: u32) board_generic.State(extent) {
    var board = board_generic.State(extent).init(board_type);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // All links are allocated sequentially, so we're doing some math to compute relative addresses.
    const constraint_type_count = 4;
    const constraints_per_type_count = board.Extent * board.Extent;
    const constraint_count = constraints_per_type_count * constraint_type_count;
    const node_per_constraint_count = board.Extent;
    const choice_link_count = constraint_count * node_per_constraint_count;
    const link_count = 1 + constraint_count + choice_link_count;

    const links_h = allocator.alloc(DoublyLink, link_count) catch unreachable; // FIXME
    defer allocator.free(links_h);

    const links_v = allocator.alloc(DoublyLink, link_count) catch unreachable; // FIXME
    defer allocator.free(links_v);

    const root_link_offset = 0;
    const header_link_offset = root_link_offset + 1;
    const header_link_count = constraint_count;
    const choice_link_offset = header_link_offset + header_link_count;

    // Allocate an array indexed by row giving containing the header link indices for the 4 satisfied contraints
    const choices_count = board.Extent * board.Extent * board.Extent;
    const choices_constraint_link_indices = allocator.alloc(ChoiceConstraintsIndices, choices_count) catch unreachable; // FIXME
    defer allocator.free(choices_constraint_link_indices);

    const solution = allocator.alloc(SolutionClue, board.Extent * board.Extent) catch unreachable; // FIXME
    defer allocator.free(solution);

    // This changes between runs only if the size of the sudoku or the box layout changes
    dancing_links_solver.fill_choices_constraint_link_indices(extent, board, choices_constraint_link_indices, header_link_offset);

    dancing_links_solver.link_matrix(choices_constraint_link_indices, links_h, links_v, choice_link_offset);

    var rng = std.Random.Xoshiro256.init(seed);

    const clue_count = board.Extent;
    const unknown_count = board.Extent * board.Extent - clue_count;
    cover_columns_for_random_clues(extent, &board, &rng.random(), choices_constraint_link_indices, links_h, links_v);

    const found_solution = solve_dancing_links_recursive(extent, DancingLinkContext(extent){
        .board = &board,
        .links_h = links_h,
        .links_v = links_v,
        .choice_link_offset = choice_link_offset,
        .choices_constraint_link_indices = choices_constraint_link_indices,
        .solution = solution,
        .random = &rng.random(),
    }, 0);

    if (!found_solution) {
        std.debug.print("Current solution: {s}\n", .{board.string_from_board()});
        @panic("Failed to find solution for generated sudoku!");
    }

    for (solution[0..unknown_count]) |clue| {
        board.numbers[clue.cell_index] = clue.number;
    }

    var is_unique = true;
    var try_harder_count = difficulty;

    while (is_unique) {
        const random_index = rng.random().uintLessThan(u32, board.Extent * board.Extent);
        const number_at_random_index = board.numbers[random_index];

        board.numbers[random_index] = null;

        is_unique = dancing_links_solver.solve(extent, &board, .{ .check_if_unique = true });

        if (!is_unique) {
            // Whoops, we've gone one step too far - restore the number
            board.numbers[random_index] = number_at_random_index;

            if (try_harder_count > 0) {
                try_harder_count -= 1;
                is_unique = true;
                continue;
            } else {
                break;
            }
        }
    }

    return board;
}

const SolutionClue = struct {
    cell_index: u32,
    number: u4,
};

fn DancingLinkContext(extent: comptime_int) type {
    return struct {
        board: *board_generic.State(extent),
        links_h: []DoublyLink,
        links_v: []DoublyLink,
        choice_link_offset: u32,
        choices_constraint_link_indices: []ChoiceConstraintsIndices,
        solution: []SolutionClue,
        random: *const std.Random,
    };
}

fn solve_dancing_links_recursive(extent: comptime_int, ctx: DancingLinkContext(extent), depth: u32) bool {
    if (ctx.links_h[0].next == 0) {
        return true;
    } else {
        const chosen_column_index = ctx.links_h[0].next; // FIXME choose better one

        // Iterate over choices (rows)
        var vertical_index = ctx.links_v[chosen_column_index].next;
        while (vertical_index != chosen_column_index) : (vertical_index = ctx.links_v[vertical_index].next) {
            const row_index = (vertical_index - ctx.choice_link_offset) / 4;
            const header = ctx.choices_constraint_link_indices[row_index];

            // Iterate over constraints (columns)
            inline for (.{ header.exs_index, header.row_index, header.col_index, header.box_index }) |constraint_index| {
                dancing_links_solver.cover_column(ctx.links_h, ctx.links_v, constraint_index);
            }

            if (solve_dancing_links_recursive(extent, ctx, depth + 1)) {
                const cell_index = row_index / ctx.board.Extent;
                const number = row_index % ctx.board.Extent;

                ctx.solution[depth] = SolutionClue{
                    .cell_index = cell_index,
                    .number = @intCast(number),
                };

                return true;
            }

            // Iterate over constraints (columns)
            inline for (.{ header.exs_index, header.row_index, header.col_index, header.box_index }) |constraint_index| {
                dancing_links_solver.uncover_column(ctx.links_h, ctx.links_v, constraint_index);
            }
        }

        return false;
    }
}

fn cover_columns_for_random_clues(extent: comptime_int, board: *board_generic.State(extent), random: *const std.Random, choices_constraint_link_indices: []const ChoiceConstraintsIndices, links_h: []DoublyLink, links_v: []DoublyLink) void {
    var taken_numbers = std.mem.zeroes([extent]bool);

    const line_region = board.regions.row(0);

    for (line_region) |cell_index| {
        var number: u4 = undefined;
        var is_taken = true;

        while (is_taken) {
            number = random.uintLessThan(u4, @intCast(board.Extent));
            is_taken = taken_numbers[number];
        }

        taken_numbers[number] = true;

        board.numbers[cell_index] = number;

        const choice_index = dancing_links_solver.get_choice_index(@intCast(cell_index), number, board.Extent);
        const choice_constraint_link_indices = choices_constraint_link_indices[choice_index];

        dancing_links_solver.cover_column(links_h, links_v, choice_constraint_link_indices.exs_index);
        dancing_links_solver.cover_column(links_h, links_v, choice_constraint_link_indices.row_index);
        dancing_links_solver.cover_column(links_h, links_v, choice_constraint_link_indices.col_index);
        dancing_links_solver.cover_column(links_h, links_v, choice_constraint_link_indices.box_index);
    }
}
