pub const SudokuString = struct {
    board: []const u8,
    solution: []const u8,
};

pub const easy_000 = SudokuString{
    .board = "58.1....7...5...26..27.4..3.....1..41..........42...........6.87.1..3.....54..9..",
    .solution = "586132497437598126912764583629871354158349762374256819243915678791683245865427931",
};

// Takes long to solve on pure backtracking solvers
pub const special_17_clues = SudokuString{
    .board = "...8.1..........435............7.8........1...2..3....6......75..34........2..6..",
    .solution = "237841569186795243594326718315674892469582137728139456642918375853467921971253684",
};

// NOTE: See https://stackoverflow.com/questions/24682039/whats-the-worst-case-valid-sudoku-puzzle-for-simple-backtracking-brute-force-al
pub const naive_backtracking_killer = "..............3.85..1.2.......5.7.....4...1...9.......5......73..2.1........4...9";
pub const naive_backtracking_killer_2 = "9..8...........5............2..1...3.1.....6....4...7.7.86.........3.1..4.....2..";
