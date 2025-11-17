pub const NumbersString = [_]u8{ '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G' };

pub const SudokuString = struct {
    board: []const u8,
    solution: []const u8,
};

pub const easy_000 = SudokuString{
    .board = "58.1....7...5...26..27.4..3.....1..41..........42...........6.87.1..3.....54..9..",
    .solution = "586132497437598126912764583629871354158349762374256819243915678791683245865427931",
};

pub const solver_hidden_pair = SudokuString{
    .board = ".........9.46.7....768.41..3.97.1.8...8...3...5.3.87.2..75.261....4.32.8.........",
    .solution = "", // FIXME
};

pub const solver_pointing_line = SudokuString{
    .board = ".179.36......8....9.....5.7.72.1.43....4.2.7..6437.25.7.1....65....3......56.172.",
    .solution = "", // FIXME
};

pub const solver_box_line_reduction = SudokuString{
    .board = ".16..78.3.928.....87...126..48...3..65...9.82.39...65..6.9...2..8...29369246..51.",
    .solution = "", // FIXME
};

pub const solver_skyscraper = SudokuString{
    .board = "...7...5.1.4...6......4.2.8..3..5.964........7..2.6......5......7.9..58..8..2.74.",
    .solution = "", // FIXME
};

// Takes long to solve on pure backtracking solvers
pub const special_17_clues = SudokuString{
    .board = "...8.1..........435............7.8........1...2..3....6......75..34........2..6..",
    .solution = "237841569186795243594326718315674892469582137728139456642918375853467921971253684",
};

// Slow on dancing links
pub const special_dancing_links = SudokuString{
    .board = "........1.....2..3.45.............1...6.....237..6.......1..4.....2.35...8.......",
    .solution = "", // FIXME
};

// NOTE: See https://stackoverflow.com/questions/24682039/whats-the-worst-case-valid-sudoku-puzzle-for-simple-backtracking-brute-force-al
pub const naive_backtracking_killer = "..............3.85..1.2.......5.7.....4...1...9.......5......73..2.1........4...9";
pub const naive_backtracking_killer_2 = "9..8...........5............2..1...3.1.....6....4...7.7.86.........3.1..4.....2..";
