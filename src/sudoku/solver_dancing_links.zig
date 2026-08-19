const std = @import("std");
const assert = std.debug.assert;

const board = @import("board.zig");
const known_boards = @import("known_boards.zig");
const validator = @import("validator.zig");

pub const Options = struct {
    solution_count_max: u32 = 1,
    fill_solution: bool = true,
};

pub const DoublyLink = struct {
    prev: u32,
    next: u32,
};

// Cell, row, column and box. Also the number of nodes in a choice, since a choice
// satisfies exactly one constraint of each type.
const ConstraintTypeCount = 4;

// See also:
// https://www.ocf.berkeley.edu/~jchu/publicportal/sudoku/sudoku.paper.html
// https://kychin.netlify.app/sudoku-blog/dlx/
// https://garethrees.org/2007/06/10/zendoku-generation/ (use wayback archive)
//
// FIXME rewrite
// choices (H links) never get edited AND are always 4 wide - for all types of sudoku => store next to each other
// IDEA: Keep headers sorted?
// IDEA: SoA for links?
// FIXME use SoAoS?
//
// Returns the number of solutions found (capped by solution_count_max)
pub fn solve(allocator: std.mem.Allocator, board_state: *board.Board, options: Options) !u32 {
    if (board_state.rules.chess_anti_king or board_state.rules.chess_anti_knight) {
        std.debug.print("error: solving puzzles with chess constraints isn't supported yet\n", .{});
        return error.UnsupportedDLXSolverChessRules;
    }

    // Conflicting clues would cover the same constraint column twice and corrupt the links
    if (validator.check_board_for_errors(board_state, null) != null) {
        return 0;
    }

    var matrix: Matrix = try .init(allocator, board_state);
    defer matrix.deinit(allocator);

    matrix.cover_choices_for_given_clues();

    return matrix.solve_recursive(options.solution_count_max, options.fill_solution);
}

// The exact cover matrix. Links are allocated as one flat array laid out as
// [root][headers...][choice nodes...], so relative addresses are plain index math.
// links_h chains the nodes of a choice together (and the headers to the root),
// links_v chains the choices that satisfy a given constraint.
pub const Matrix = struct {
    board_state: *board.Board,
    links_h: []DoublyLink,
    links_v: []DoublyLink,
    // Indexed by choice, giving the header link indices of the constraints it satisfies
    choices: []ChoiceConstraintsIndices,
    header_link_offset: u32,
    choice_link_offset: u32,

    pub fn init(allocator: std.mem.Allocator, board_state: *board.Board) !Matrix {
        const extent = board_state.extent;
        const extent_sqr = extent * extent;

        const constraint_count = ConstraintTypeCount * extent_sqr;
        const link_count = 1 + constraint_count * (1 + extent);
        const choice_count = extent * extent_sqr;

        const links_h = try allocator.alloc(DoublyLink, link_count);
        errdefer allocator.free(links_h);

        const links_v = try allocator.alloc(DoublyLink, link_count);
        errdefer allocator.free(links_v);

        const choices = try allocator.alloc(ChoiceConstraintsIndices, choice_count);
        errdefer allocator.free(choices);

        var matrix = Matrix{
            .board_state = board_state,
            .links_h = links_h,
            .links_v = links_v,
            .choices = choices,
            .header_link_offset = 1, // Right after the root link
            .choice_link_offset = 1 + constraint_count,
        };

        // This only changes between runs if the size of the sudoku or the box layout changes
        matrix.fill_choices_constraint_link_indices();
        matrix.link_matrix();

        return matrix;
    }

    pub fn deinit(self: *Matrix, allocator: std.mem.Allocator) void {
        allocator.free(self.choices);
        allocator.free(self.links_v);
        allocator.free(self.links_h);
    }

    // Cover every constraint satisfied by this choice.
    // NOTE: this and uncover_choice are the only places that know how wide a choice is.
    pub fn cover_choice(self: *Matrix, choice_index: usize) void {
        const header = self.choices[choice_index];

        inline for (.{ header.exs_index, header.row_index, header.col_index, header.box_index }) |constraint_index| {
            cover_column(self.links_h, self.links_v, constraint_index);
        }
    }

    pub fn uncover_choice(self: *Matrix, choice_index: usize) void {
        const header = self.choices[choice_index];

        // Uncover in the exact reverse order of covering
        inline for (.{ header.box_index, header.col_index, header.row_index, header.exs_index }) |constraint_index| {
            uncover_column(self.links_h, self.links_v, constraint_index);
        }
    }

    pub fn choice_index_from_link_index(self: Matrix, link_index: u32) u32 {
        return (link_index - self.choice_link_offset) / ConstraintTypeCount;
    }

    pub fn solve_recursive(self: *Matrix, solution_count_max: u32, fill_solution: bool) u32 {
        if (self.links_h[0].next == 0) {
            return 1;
        } else {
            var solution_count: u32 = 0;
            const chosen_column_index = choose_best_column_index(self.links_h, self.links_v);

            // Iterate over choices (rows)
            var vertical_index = self.links_v[chosen_column_index].next;

            while (vertical_index != chosen_column_index) : (vertical_index = self.links_v[vertical_index].next) {
                const choice_index = self.choice_index_from_link_index(vertical_index);

                self.cover_choice(choice_index);

                solution_count += self.solve_recursive(solution_count_max - solution_count, fill_solution);

                self.uncover_choice(choice_index);

                if (solution_count >= solution_count_max) {
                    // FIXME if we request a large max count but the board has only 1, fill solution will never run.
                    if (fill_solution) {
                        const cell_index = choice_index / self.board_state.extent;
                        const number = choice_index % self.board_state.extent;

                        self.board_state.numbers()[cell_index] = @intCast(number);
                    }

                    return solution_count;
                }
            }

            return solution_count;
        }
    }

    // We now have the initial fully connected matrix
    // Let's remove the choices we already have a clue for
    pub fn cover_choices_for_given_clues(self: *Matrix) void {
        for (self.board_state.numbers(), 0..) |number_opt, cell_index| {
            if (number_opt) |number| {
                self.cover_choice(get_choice_index(cell_index, number, self.board_state.extent));
            }
        }
    }

    fn fill_choices_constraint_link_indices(self: *Matrix) void {
        const extent = self.board_state.extent;
        const constraint_exs_headers_offset = self.header_link_offset + 0 * extent * extent;
        const constraint_row_headers_offset = self.header_link_offset + 1 * extent * extent;
        const constraint_col_headers_offset = self.header_link_offset + 2 * extent * extent;
        const constraint_box_headers_offset = self.header_link_offset + 3 * extent * extent;

        for (0..extent * extent) |cell_index| {
            const cell_coord = self.board_state.cell_coord_from_index(cell_index);
            const cell_col = cell_coord[0];
            const cell_row = cell_coord[1];
            const cell_box = self.board_state.regions.box_indices()[cell_index];

            for (0..extent) |number_usize| {
                const number: u32 = @intCast(number_usize);
                const choice_index = get_choice_index(cell_index, number, extent);

                // Get indices for each four constraints we satisfy
                self.choices[choice_index] = ChoiceConstraintsIndices{
                    .exs_index = constraint_exs_headers_offset + @as(u32, @intCast(cell_index)),
                    .row_index = constraint_row_headers_offset + cell_row * @as(u32, extent) + number,
                    .col_index = constraint_col_headers_offset + cell_col * @as(u32, extent) + number,
                    .box_index = constraint_box_headers_offset + cell_box * @as(u32, extent) + number,
                };
            }
        }
    }

    fn link_matrix(self: *Matrix) void {
        // Chain all horizontal header and root link together
        link_together(self.links_h, 0, self.choice_link_offset);

        // Make all vertical header and root links point to themselves
        for (self.links_v[0..self.choice_link_offset], 0..) |*link, index| {
            link.prev = @intCast(index);
            link.next = @intCast(index);
        }

        // Connect the rest of the matrix
        var free_choice_link_index = self.choice_link_offset;

        for (self.choices) |constraint_indices| {
            // Attach the new choice nodes to the end of the header vertical lists
            insert_link_to_end(self.links_v, constraint_indices.exs_index, free_choice_link_index + 0);
            insert_link_to_end(self.links_v, constraint_indices.row_index, free_choice_link_index + 1);
            insert_link_to_end(self.links_v, constraint_indices.col_index, free_choice_link_index + 2);
            insert_link_to_end(self.links_v, constraint_indices.box_index, free_choice_link_index + 3);

            link_together(self.links_h, free_choice_link_index, ConstraintTypeCount);

            free_choice_link_index += ConstraintTypeCount;
        }
    }
};

fn choose_best_column_index(links_h: []const DoublyLink, links_v: []const DoublyLink) u32 {
    const root_index: u32 = 0;

    // Pick column with smallest row count (Algorithm X heuristic)
    var best_col = links_h[root_index].next;
    var best_count: u32 = std.math.maxInt(u32);

    // NOTE: Care when walking header links, the root link is in the same list
    var col = links_h[root_index].next;
    while (col != root_index) : (col = links_h[col].next) {
        // Count rows in this column
        const count = list_size_inclusive(links_v, col);

        if (count < best_count) {
            best_col = col;
            best_count = count;

            if (best_count <= 1) {
                break;
            }
        }
    }

    return best_col;
}

pub fn get_choice_index(cell_index: usize, number: usize, extent: u32) usize {
    return cell_index * extent + number;
}

// Gives us an index to the header link of the constraints of that choice
pub const ChoiceConstraintsIndices = struct {
    exs_index: u32,
    row_index: u32,
    col_index: u32,
    box_index: u32,
};

// NOTE: only feed a header index to this function!
fn cover_column(links_h: []DoublyLink, links_v: []DoublyLink, column_index: u32) void {
    assert(links_h[column_index].next != column_index); // Covering an empty column

    remove_link_from_list(links_h, column_index);

    var vertical_index = links_v[column_index].next;
    while (vertical_index != column_index) : (vertical_index = links_v[vertical_index].next) {
        // FIXME we know all 4 nodes are next to each other
        // but we don't always start at the same one
        var h_index: u32 = vertical_index;
        for (0..ConstraintTypeCount - 1) |_| {
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
        for (0..ConstraintTypeCount - 1) |_| {
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

fn list_size_inclusive(links: []const DoublyLink, start_index: u32) u32 {
    var count: u32 = 1;
    var next_index = links[start_index].next;

    while (next_index != start_index) : (next_index = links[next_index].next) {
        count += 1;
    }

    return count;
}

test "Conflicting clues" {
    // Duplicate clues in a region used to double-cover constraint columns,
    // corrupt the link matrix and can hang the search forever
    var board_state: board.Board = try .init(known_boards.easy.rules);
    try board_state.fill_board_from_string("..................11.3.....1.....................................................");

    try std.testing.expectEqual(0, try solve(std.testing.allocator, &board_state, .{}));
    try std.testing.expectEqual(0, try solve(std.testing.allocator, &board_state, .{}));
}

test "Board Fill" {
    // Duplicate clues in a region used to double-cover constraint columns,
    // corrupt the link matrix and can hang the search forever
    var board_state: board.Board = try .init(known_boards.easy.rules);
    try board_state.fill_board_from_string("..................11.3.....1.....................................................");

    try std.testing.expectEqual(0, try solve(std.testing.allocator, &board_state, .{ .solution_count_max = 2, .fill_solution = true }));

    var solution_board: board.Board = try .init(board_state.rules);
    try solution_board.fill_board_from_string(known_boards.easy.solution_string);

    try std.testing.expect(std.mem.eql(?board.NumberType, solution_board.numbers(), board_state.numbers()));
}

test {
    inline for (known_boards.TestDancingLinksSolver) |known_board| {
        var board_state: board.Board = try .init(known_board.rules);
        try board_state.fill_board_from_string(known_board.start_string);

        try std.testing.expectEqual(1, try solve(std.testing.allocator, &board_state, .{}));

        var solution_board: board.Board = try .init(known_board.rules);
        try solution_board.fill_board_from_string(known_board.solution_string);

        try std.testing.expect(std.mem.eql(?board.NumberType, solution_board.numbers(), board_state.numbers()));
    }
}
