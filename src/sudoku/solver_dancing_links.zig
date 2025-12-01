const std = @import("std");
const assert = std.debug.assert;

const board_generic = @import("board_generic.zig");
const known_boards = @import("known_boards.zig");

pub const Options = struct {
    check_if_unique: bool = false,
};

pub const DoublyLink = struct {
    prev: u32,
    next: u32,
};

// See also:
// https://www.ocf.berkeley.edu/~jchu/publicportal/sudoku/sudoku.paper.html
// https://kychin.netlify.app/sudoku-blog/dlx/
// https://garethrees.org/2007/06/10/zendoku-generation/ (use wayback archive)
//
// FIXME rewrite
// choices (H links) never get edited AND are always 4 wide - for all types of sudoku => store next to each other
// IDEA: Keep headers sorted?
// IDEA: SoA for links?
pub fn solve(extent: comptime_int, board: *board_generic.State(extent), options: Options) bool {
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
    const choices_count = board.extent * board.extent_sqr;
    const choices_constraint_link_indices = allocator.alloc(ChoiceConstraintsIndices, choices_count) catch unreachable; // FIXME
    defer allocator.free(choices_constraint_link_indices);

    // This changes between runs only if the size of the sudoku or the box layout changes
    fill_choices_constraint_link_indices(extent, board.*, choices_constraint_link_indices, header_link_offset);

    link_matrix(choices_constraint_link_indices, links_h, links_v, choice_link_offset);

    cover_columns_for_given_clues(extent, board.*, choices_constraint_link_indices, links_h, links_v);

    if (options.check_if_unique) {
        const solution_count = solve_dancing_links_recursive_count_solutions(extent, DancingLinkContext(extent){
            .board = board,
            .links_h = links_h,
            .links_v = links_v,
            .choice_link_offset = choice_link_offset,
            .choices_constraint_link_indices = choices_constraint_link_indices,
        });

        return solution_count == 1;
    } else {
        return solve_dancing_links_recursive(extent, DancingLinkContext(extent){
            .board = board,
            .links_h = links_h,
            .links_v = links_v,
            .choice_link_offset = choice_link_offset,
            .choices_constraint_link_indices = choices_constraint_link_indices,
        });
    }
}

fn DancingLinkContext(extent: comptime_int) type {
    return struct {
        board: *board_generic.State(extent),
        links_h: []DoublyLink,
        links_v: []DoublyLink,
        choice_link_offset: u32,
        choices_constraint_link_indices: []ChoiceConstraintsIndices,
    };
}

fn solve_dancing_links_recursive(extent: comptime_int, ctx: DancingLinkContext(extent)) bool {
    if (ctx.links_h[0].next == 0) {
        return true;
    } else {
        const chosen_column_index = ctx.links_h[0].next; // FIXME choose better one

        // Iterate over choices (rows)
        var vertical_index = ctx.links_v[chosen_column_index].next;
        while (vertical_index != chosen_column_index) : (vertical_index = ctx.links_v[vertical_index].next) {
            const row_index = (vertical_index - ctx.choice_link_offset) / 4;
            const header = ctx.choices_constraint_link_indices[row_index];

            inline for (.{ header.exs_index, header.row_index, header.col_index, header.box_index }) |constraint_index| {
                cover_column(ctx.links_h, ctx.links_v, constraint_index);
            }

            if (solve_dancing_links_recursive(extent, ctx)) {
                const cell_index = row_index / ctx.board.extent;
                const number = row_index % ctx.board.extent;

                ctx.board.numbers[cell_index] = @intCast(number);

                return true;
            }

            inline for (.{ header.exs_index, header.row_index, header.col_index, header.box_index }) |constraint_index| {
                uncover_column(ctx.links_h, ctx.links_v, constraint_index);
            }
        }

        return false;
    }
}

fn solve_dancing_links_recursive_count_solutions(extent: comptime_int, ctx: DancingLinkContext(extent)) u32 {
    if (ctx.links_h[0].next == 0) {
        return 1;
    } else {
        var solution_count: u32 = 0;

        const chosen_column_index = ctx.links_h[0].next; // FIXME choose better one

        // Iterate over choices (rows)
        var vertical_index = ctx.links_v[chosen_column_index].next;

        while (vertical_index != chosen_column_index) : (vertical_index = ctx.links_v[vertical_index].next) {
            const row_index = (vertical_index - ctx.choice_link_offset) / 4;
            const header = ctx.choices_constraint_link_indices[row_index];

            inline for (.{ header.exs_index, header.row_index, header.col_index, header.box_index }) |constraint_index| {
                cover_column(ctx.links_h, ctx.links_v, constraint_index);
            }

            solution_count += solve_dancing_links_recursive_count_solutions(extent, ctx);

            inline for (.{ header.exs_index, header.row_index, header.col_index, header.box_index }) |constraint_index| {
                uncover_column(ctx.links_h, ctx.links_v, constraint_index);
            }
        }

        return solution_count;
    }
}

pub fn get_choice_index(cell_index: usize, number: usize, extent: comptime_int) usize {
    return cell_index * extent + number;
}

// Gives us an index to the header link of the constraints of that choice
pub const ChoiceConstraintsIndices = struct {
    exs_index: u32,
    row_index: u32,
    col_index: u32,
    box_index: u32,
};

pub fn fill_choices_constraint_link_indices(extent: comptime_int, board: board_generic.State(extent), choices_constraint_link_indices: []ChoiceConstraintsIndices, header_link_offset: u32) void {
    const constraint_exs_headers_offset = header_link_offset + 0 * board.extent_sqr;
    const constraint_row_headers_offset = header_link_offset + 1 * board.extent_sqr;
    const constraint_col_headers_offset = header_link_offset + 2 * board.extent_sqr;
    const constraint_box_headers_offset = header_link_offset + 3 * board.extent_sqr;

    for (0..board.extent_sqr) |cell_index| {
        const cell_coord = board.cell_coord_from_index(cell_index);
        const cell_col = cell_coord[0];
        const cell_row = cell_coord[1];
        const cell_box = board.regions.box_indices[cell_index];

        for (0..board.extent) |number_usize| {
            const number: u32 = @intCast(number_usize);
            const choice_index = get_choice_index(cell_index, number, board.extent);

            // Get indices for each four constraints we satisfy
            choices_constraint_link_indices[choice_index] = ChoiceConstraintsIndices{
                .exs_index = constraint_exs_headers_offset + @as(u32, @intCast(cell_index)),
                .row_index = constraint_row_headers_offset + cell_row * @as(u32, board.extent) + number,
                .col_index = constraint_col_headers_offset + cell_col * @as(u32, board.extent) + number,
                .box_index = constraint_box_headers_offset + cell_box * @as(u32, board.extent) + number,
            };
        }
    }
}

pub fn link_matrix(choices_constraint_link_indices: []const ChoiceConstraintsIndices, links_h: []DoublyLink, links_v: []DoublyLink, choice_link_offset: u32) void {
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

fn cover_columns_for_given_clues(extent: comptime_int, board: board_generic.State(extent), choices_constraint_link_indices: []const ChoiceConstraintsIndices, links_h: []DoublyLink, links_v: []DoublyLink) void {
    // We now have the initial fully connected matrix
    // Let's remove the rows we already have a clue for
    for (board.numbers, 0..) |number_opt, cell_index| {
        if (number_opt) |number| {
            const choice_index = get_choice_index(@intCast(cell_index), number, board.extent);
            const choice_constraint_link_indices = choices_constraint_link_indices[choice_index];

            cover_column(links_h, links_v, choice_constraint_link_indices.exs_index);
            cover_column(links_h, links_v, choice_constraint_link_indices.row_index);
            cover_column(links_h, links_v, choice_constraint_link_indices.col_index);
            cover_column(links_h, links_v, choice_constraint_link_indices.box_index);
        }
    }
}

// NOTE: only feed a header index to this function!
pub fn cover_column(links_h: []DoublyLink, links_v: []DoublyLink, column_index: u32) void {
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
pub fn uncover_column(links_h: []DoublyLink, links_v: []DoublyLink, column_index: u32) void {
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

test {
    inline for (known_boards.TestDancingLinksSolver) |known_board| {
        const board_extent = comptime known_board.board_type.extent();

        var board = board_generic.State(board_extent).init(known_board.board_type);
        board.fill_board_from_string(known_board.start_string);

        try std.testing.expect(solve(board_extent, &board, .{}));

        var solution_board = board_generic.State(board_extent).init(known_board.board_type);
        solution_board.fill_board_from_string(known_board.solution_string);

        try std.testing.expectEqual(solution_board.numbers, board.numbers);
    }
}
