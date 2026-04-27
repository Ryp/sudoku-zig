const std = @import("std");
const assert = std.debug.assert;

const rules = @import("rules.zig");
const board = @import("board.zig");
const known_boards = @import("known_boards.zig");

const dancing_links_solver = @import("solver_dancing_links.zig");
const DoublyLink = dancing_links_solver.DoublyLink;
const ChoiceConstraintsIndices = dancing_links_solver.ChoiceConstraintsIndices;

pub fn generate(board_rules: rules.Rules, seed: u64, difficulty: u32) board.Board {
    std.debug.assert(!board_rules.chess_anti_king);
    std.debug.assert(!board_rules.chess_anti_knight);

    const extent = board_rules.type.extent();
    const extent_sqr = extent * extent;

    var board_state: board.Board = .init(board_rules);

    // All links are allocated sequentially, so we're doing some math to compute relative addresses.
    const constraint_type_count = 4;

    // Actual size version
    const constraints_per_type_count = extent_sqr;
    const constraint_count = constraints_per_type_count * constraint_type_count;
    const node_per_constraint_count = extent;
    const choice_link_count = constraint_count * node_per_constraint_count;
    const link_count = 1 + constraint_count + choice_link_count;

    // Max size version
    const constraints_per_type_count_max = board.MaxExtentSqr;
    const constraint_count_max = constraints_per_type_count_max * constraint_type_count;
    const node_per_constraint_count_max = board.MaxExtent;
    const choice_link_count_max = constraint_count_max * node_per_constraint_count_max;
    const link_count_max = 1 + constraint_count_max + choice_link_count_max;

    var links_h_max: [link_count_max]DoublyLink = undefined;
    const links_h = links_h_max[0..link_count];

    var links_v_max: [link_count_max]DoublyLink = undefined;
    const links_v = links_v_max[0..link_count];

    const root_link_offset = 0;
    const header_link_offset = root_link_offset + 1;
    const header_link_count = constraint_count;
    const choice_link_offset = header_link_offset + header_link_count;

    // Array indexed by row giving containing the header link indices for the 4 satisfied contraints
    const choices_count = extent * extent_sqr;
    const choices_count_max = board.MaxExtent * board.MaxExtentSqr;

    var choices_constraint_link_indices_max: [choices_count_max]ChoiceConstraintsIndices = undefined;
    const choices_constraint_link_indices = choices_constraint_link_indices_max[0..choices_count];

    var solution_max: [board.MaxExtentSqr]SolutionClue = undefined;
    const solution = solution_max[0 .. extent * extent];

    // This changes between runs only if the size of the sudoku or the box layout changes
    dancing_links_solver.fill_choices_constraint_link_indices(&board_state, choices_constraint_link_indices, header_link_offset);

    dancing_links_solver.link_matrix(choices_constraint_link_indices, links_h, links_v, choice_link_offset);

    var rng = std.Random.Xoshiro256.init(seed);

    const clue_count = extent;
    const unknown_count = extent_sqr - clue_count;
    cover_columns_for_random_clues(&board_state, &rng.random(), choices_constraint_link_indices, links_h, links_v);

    const found_solution = solve_dancing_links_recursive(DancingLinkContext{
        .board_state = &board_state,
        .links_h = links_h,
        .links_v = links_v,
        .choice_link_offset = choice_link_offset,
        .choices_constraint_link_indices = choices_constraint_link_indices,
        .solution = solution,
    }, 0);

    if (!found_solution) {
        std.debug.print("Current solution: {s}\n", .{board_state.string_from_board()});
        @panic("Failed to find solution for generated sudoku!");
    }

    for (solution[0..unknown_count]) |clue| {
        board_state.numbers()[clue.cell_index] = clue.number;
    }

    var is_unique = true;
    var try_harder_count = difficulty;

    while (is_unique) {
        const random_index = rng.random().uintLessThan(u32, extent_sqr);
        const number_at_random_index = board_state.numbers()[random_index];

        board_state.numbers()[random_index] = null;

        is_unique = dancing_links_solver.solve(&board_state, .{ .check_if_unique = true });

        if (!is_unique) {
            // Whoops, we've gone one step too far - restore the number
            board_state.numbers()[random_index] = number_at_random_index;

            if (try_harder_count > 0) {
                try_harder_count -= 1;
                is_unique = true;
                continue;
            } else {
                break;
            }
        }
    }

    return board_state;
}

const SolutionClue = struct {
    cell_index: u32,
    number: u4,
};

const DancingLinkContext = struct {
    board_state: *board.Board,
    links_h: []DoublyLink,
    links_v: []DoublyLink,
    choice_link_offset: u32,
    choices_constraint_link_indices: []ChoiceConstraintsIndices,

    solution: []SolutionClue,
};

fn solve_dancing_links_recursive(ctx: DancingLinkContext, depth: u32) bool {
    if (ctx.links_h[0].next == 0) {
        return true;
    } else {
        const chosen_column_index = dancing_links_solver.choose_best_column_index(ctx.links_h, ctx.links_v);

        // Iterate over choices (rows)
        var vertical_index = ctx.links_v[chosen_column_index].next;
        while (vertical_index != chosen_column_index) : (vertical_index = ctx.links_v[vertical_index].next) {
            const row_index = (vertical_index - ctx.choice_link_offset) / 4;
            const header = ctx.choices_constraint_link_indices[row_index];

            // Iterate over constraints (columns)
            inline for (.{ header.exs_index, header.row_index, header.col_index, header.box_index }) |constraint_index| {
                dancing_links_solver.cover_column(ctx.links_h, ctx.links_v, constraint_index);
            }

            if (solve_dancing_links_recursive(ctx, depth + 1)) {
                const cell_index = row_index / ctx.board_state.extent;
                const number = row_index % ctx.board_state.extent;

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

fn cover_columns_for_random_clues(board_state: *board.Board, random: *const std.Random, choices_constraint_link_indices: []const ChoiceConstraintsIndices, links_h: []DoublyLink, links_v: []DoublyLink) void {
    const extent = board_state.extent;

    var taken_numbers_max = std.mem.zeroes([board.MaxExtent]bool);
    const taken_numbers = taken_numbers_max[0..extent];

    const line_region = board_state.regions.row(0);

    for (line_region) |cell_index| {
        var number: u4 = undefined;
        var is_taken = true;

        while (is_taken) {
            number = @intCast(random.uintLessThan(usize, board_state.extent));
            is_taken = taken_numbers[number];
        }

        taken_numbers[number] = true;

        board_state.numbers()[cell_index] = number;

        const choice_index = dancing_links_solver.get_choice_index(@intCast(cell_index), number, board_state.extent);
        const header = choices_constraint_link_indices[choice_index];

        inline for (.{ header.exs_index, header.row_index, header.col_index, header.box_index }) |constraint_index| {
            dancing_links_solver.cover_column(links_h, links_v, constraint_index);
        }
    }
}

test {
    const Seed: u64 = 0xDEAD_BEEF_CAFE_BABE;
    const Difficulty: u32 = 200;

    inline for (.{
        rules.Regular3x3,
        rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 4, 3 } } } },
        // rules.Rules{ .type = .{ .regular = .{ .box_extent = .{ 4, 4 } } } }, // FIXME crashes
        // known_boards.jigsaw9.rules, // FIXME Can't make a board
    }) |board_rules| {
        _ = generate(board_rules, Seed, Difficulty);
    }
}
