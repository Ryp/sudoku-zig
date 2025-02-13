const std = @import("std");
const assert = std.debug.assert;

const sudoku = @import("game.zig");
const BoardState = sudoku.BoardState;
const UnsetNumber = sudoku.UnsetNumber;

const dancing_links_solver = @import("solver_dancing_links.zig");

const DoublyLink = struct {
    prev: u32,
    next: u32,
};

pub fn generate(board: *BoardState, seed: u64) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // All links are allocated sequentially, so we're doing some math to compute relative addresses.
    const constraint_type_count = 4;
    const constraints_per_type_count = board.extent * board.extent;
    const constraint_count = constraints_per_type_count * constraint_type_count;
    const node_per_constraint_count = board.extent;
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
    const choices_count = board.extent * board.extent * board.extent;
    const choices_constraint_link_indices = allocator.alloc(ChoiceConstraintsIndices, choices_count) catch unreachable; // FIXME
    defer allocator.free(choices_constraint_link_indices);

    const solution = allocator.alloc(SolutionClue, board.extent * board.extent) catch unreachable; // FIXME
    defer allocator.free(solution);

    // This changes between runs only if the size of the sudoku or the box layout changes
    fill_choices_constraint_link_indices(choices_constraint_link_indices, board.*, header_link_offset);

    link_matrix(choices_constraint_link_indices, links_h, links_v, choice_link_offset);

    var rng = std.Random.Xoshiro256.init(seed);

    const clue_count = board.extent;
    const unknown_count = board.extent * board.extent - clue_count;
    cover_columns_for_given_clues(board, &rng.random(), choices_constraint_link_indices, links_h, links_v);

    // for (0..10) |_| {
    //     const h_link_index = rng.random().uintLessThan(u32, choice_link_offset - 1) + 1;
    //     remove_link_from_list(links_h, h_link_index);

    //     insert_link_to_end(links_h, 0, h_link_index);
    // }

    const found_solution = solve_dancing_links_recursive(DancingLinkContext{
        .board = board,
        .links_h = links_h,
        .links_v = links_v,
        .choice_link_offset = choice_link_offset,
        .choices_constraint_link_indices = choices_constraint_link_indices,
        .solution = solution,
        .random = &rng.random(),
    }, 0);

    std.debug.assert(found_solution);

    for (solution[0..unknown_count]) |clue| {
        board.numbers[clue.cell_index] = clue.number;
    }

    var is_unique = true;
    var try_harder_count: u32 = 500;

    while (is_unique) {
        const random_index = rng.random().uintLessThan(u32, board.extent * board.extent);
        const number_at_random_index = board.numbers[random_index];

        board.numbers[random_index] = UnsetNumber;

        is_unique = dancing_links_solver.solve(board, .{ .check_if_unique = true });

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
}

const SolutionClue = struct {
    cell_index: u32,
    number: u4,
};

const DancingLinkContext = struct {
    board: *BoardState,
    links_h: []DoublyLink,
    links_v: []DoublyLink,
    choice_link_offset: u32,
    choices_constraint_link_indices: []ChoiceConstraintsIndices,
    solution: []SolutionClue,
    random: *const std.Random,
};

fn solve_dancing_links_recursive(ctx: DancingLinkContext, depth: u32) bool {
    if (ctx.links_h[0].next == 0) {
        return true;
    } else {
        const chosen_column_index = ctx.links_h[0].next; // FIXME choose better one

        // const jumps = ctx.rng.random().uintLessThan(usize, ctx.links_h.len);

        // for (0..jumps) |_| {
        //     chosen_column_index = ctx.links_h[chosen_column_index].next;
        // }

        // if (chosen_column_index == 0) {
        //     chosen_column_index = ctx.links_h[0].prev;
        // }

        // cover_column(ctx.links_h, ctx.links_v, chosen_column_index);

        // Iterate over choices (rows)
        var vertical_index = ctx.links_v[chosen_column_index].next;
        while (vertical_index != chosen_column_index) : (vertical_index = ctx.links_v[vertical_index].next) {
            const row_index = (vertical_index - ctx.choice_link_offset) / 4;
            const header_links = ctx.choices_constraint_link_indices[row_index];

            // Iterate over constraints (columns)
            cover_column(ctx.links_h, ctx.links_v, header_links.exs_index);
            cover_column(ctx.links_h, ctx.links_v, header_links.row_index);
            cover_column(ctx.links_h, ctx.links_v, header_links.col_index);
            cover_column(ctx.links_h, ctx.links_v, header_links.box_index);

            if (solve_dancing_links_recursive(ctx, depth + 1)) {
                const cell_index = row_index / ctx.board.extent;
                const number = row_index % ctx.board.extent;

                ctx.solution[depth] = SolutionClue{
                    .cell_index = cell_index,
                    .number = @intCast(number),
                };

                return true;
            }

            // Iterate over constraints (columns)
            uncover_column(ctx.links_h, ctx.links_v, header_links.box_index);
            uncover_column(ctx.links_h, ctx.links_v, header_links.col_index);
            uncover_column(ctx.links_h, ctx.links_v, header_links.row_index);
            uncover_column(ctx.links_h, ctx.links_v, header_links.exs_index);
        }

        // uncover_column(ctx.links_h, ctx.links_v, chosen_column_index);

        return false;
    }
}

fn get_choice_index(cell_index: u32, number: u32, extent: u32) u32 {
    return cell_index * extent + number;
}

// Gives us an index to the header link of the constraints of that choice
const ChoiceConstraintsIndices = struct {
    exs_index: u32,
    row_index: u32,
    col_index: u32,
    box_index: u32,
};

fn fill_choices_constraint_link_indices(choices_constraint_link_indices: []ChoiceConstraintsIndices, board: BoardState, header_link_offset: u32) void {
    const constraints_per_type_count = board.extent * board.extent;

    const constraint_exs_headers_offset = header_link_offset + 0 * constraints_per_type_count;
    const constraint_row_headers_offset = header_link_offset + 1 * constraints_per_type_count;
    const constraint_col_headers_offset = header_link_offset + 2 * constraints_per_type_count;
    const constraint_box_headers_offset = header_link_offset + 3 * constraints_per_type_count;

    for (0..board.extent) |cell_row_usize| {
        const cell_row: u32 = @intCast(cell_row_usize);

        for (0..board.extent) |cell_col_usize| {
            const cell_col: u32 = @intCast(cell_col_usize);

            const cell_index = cell_row * board.extent + cell_col;
            const cell_box = board.box_indices[cell_index];

            for (0..board.extent) |number_usize| {
                const number: u32 = @intCast(number_usize);
                const choice_index = get_choice_index(cell_index, number, board.extent);

                // Get indices for each four constraints we satisfy
                choices_constraint_link_indices[choice_index] = ChoiceConstraintsIndices{
                    .exs_index = constraint_exs_headers_offset + cell_index,
                    .row_index = constraint_row_headers_offset + cell_row * board.extent + number,
                    .col_index = constraint_col_headers_offset + cell_col * board.extent + number,
                    .box_index = constraint_box_headers_offset + cell_box * board.extent + number,
                };
            }
        }
    }
}

fn link_matrix(choices_constraint_link_indices: []const ChoiceConstraintsIndices, links_h: []DoublyLink, links_v: []DoublyLink, choice_link_offset: u32) void {
    // Chain all horizontal header and root link together
    link_together(links_h, 0, choice_link_offset);

    // Make all vertical header and root links point to themselves
    for (links_v[0..choice_link_offset], 0..) |*link, index| {
        link.prev = @intCast(index);
        link.next = @intCast(index);
    }

    // Connect the rest of the matrix
    var free_choice_link_index = choice_link_offset;

    for (choices_constraint_link_indices) |constraint_indices| {
        // Attach the new choice nodes to the end of the header vertical lists
        insert_link_to_end(links_v, constraint_indices.exs_index, free_choice_link_index + 0);
        insert_link_to_end(links_v, constraint_indices.row_index, free_choice_link_index + 1);
        insert_link_to_end(links_v, constraint_indices.col_index, free_choice_link_index + 2);
        insert_link_to_end(links_v, constraint_indices.box_index, free_choice_link_index + 3);

        link_together(links_h, free_choice_link_index, 4);

        free_choice_link_index += 4;
    }
}

fn cover_columns_for_given_clues(board: *BoardState, random: *const std.Random, choices_constraint_link_indices: []const ChoiceConstraintsIndices, links_h: []DoublyLink, links_v: []DoublyLink) void {
    var taken_numbers: [16]bool = undefined; // FIXME
    for (&taken_numbers) |*i| {
        i.* = false;
    }

    for (0..board.extent) |cell_index| {
        var number: u4 = undefined;
        var is_taken = true;

        while (is_taken) {
            number = random.uintLessThan(u4, @intCast(board.extent));
            is_taken = taken_numbers[number];
        }

        taken_numbers[number] = true;

        board.numbers[cell_index] = number;

        const choice_index = get_choice_index(@intCast(cell_index), number, board.extent);
        const choice_constraint_link_indices = choices_constraint_link_indices[choice_index];

        cover_column(links_h, links_v, choice_constraint_link_indices.exs_index);
        cover_column(links_h, links_v, choice_constraint_link_indices.row_index);
        cover_column(links_h, links_v, choice_constraint_link_indices.col_index);
        cover_column(links_h, links_v, choice_constraint_link_indices.box_index);
    }
}

// NOTE: only feed a header index to this function!
fn cover_column(links_h: []DoublyLink, links_v: []DoublyLink, column_index: u32) void {
    assert(links_h[column_index].next != column_index); // Covering an empty column

    remove_link_from_list(links_h, column_index);

    var vertical_index = links_v[column_index].next;
    while (vertical_index != column_index) : (vertical_index = links_v[vertical_index].next) {
        // FIXME we know all 4 nodes are next to each other
        // but we don't always start at the same one
        var h_index: u32 = vertical_index;
        for (0..3) |_| {
            h_index = links_h[h_index].next;
            remove_link_from_list(links_v, h_index);
        }
    }
}

// NOTE: only feed a header index to this function!
fn uncover_column(links_h: []DoublyLink, links_v: []DoublyLink, column_index: u32) void {
    assert(links_h[column_index].prev != column_index); // Covering an empty column

    relink_prev_and_next_to_us(links_h, column_index);

    var vertical_index = links_v[column_index].prev;
    while (vertical_index != column_index) : (vertical_index = links_v[vertical_index].prev) {
        // FIXME we know all 4 nodes are next to each other
        // but we don't always start at the same one
        var h_index: u32 = vertical_index;
        for (0..3) |_| {
            h_index = links_h[h_index].prev;
            relink_prev_and_next_to_us(links_v, h_index);
        }
    }
}

fn relink_prev_and_next_to_us(links: []DoublyLink, index: u32) void {
    const link = links[index];

    links[link.prev].next = index;
    links[link.next].prev = index;
}

fn remove_link_from_list(links: []DoublyLink, index: u32) void {
    const link = links[index];

    links[link.prev].next = link.next;
    links[link.next].prev = link.prev;
}

fn insert_link_to_end(links: []DoublyLink, start_index: u32, inserted_index: u32) void {
    const prev_index = links[start_index].prev;

    links[prev_index].next = inserted_index;
    links[start_index].prev = inserted_index;
    links[inserted_index].prev = prev_index;
    links[inserted_index].next = start_index;
}

fn link_together(links: []DoublyLink, start_index: u32, count: u32) void {
    const end_index = start_index + count;

    for (start_index..end_index - 1) |link_index| {
        links[link_index].next = @intCast(link_index + 1);
        links[link_index + 1].prev = @intCast(link_index);
    }

    links[start_index].prev = end_index - 1;
    links[end_index - 1].next = start_index;
}
