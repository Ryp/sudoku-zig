const board_generic = @import("board_generic.zig");

pub const KnownBoard = struct {
    board_type: board_generic.BoardType,
    start_string: []const u8,
    solution_string: []const u8,
};

pub const TestLogicalSolver = .{
    easy,
    hidden_pair,
    // with_pointing_line, // Too hard for logical solver alone
    // box_line_reduction, // Too hard for logical solver alone
    // skyscraper, // Too hard for logical solver alone
    jigsaw9,
    backtracking_killer,
    naive_backtracking_killer_1,
    naive_backtracking_killer_2,
    // dancing_links_killer,
};

pub const TestDancingLinksSolver = .{
    easy,
    hidden_pair,
    pointing_line,
    box_line_reduction,
    skyscraper,
    // jigsaw9 FIXME!
    backtracking_killer,
    naive_backtracking_killer_1,
    naive_backtracking_killer_2,
    dancing_links_killer,
};

pub const TestBacktrackingSolver = .{
    easy,
    hidden_pair,
    pointing_line,
    box_line_reduction,
    skyscraper,
    jigsaw9,
    backtracking_killer,
    naive_backtracking_killer_1,
    naive_backtracking_killer_2,
    dancing_links_killer,
};

pub const easy = KnownBoard{
    .board_type = .{ .regular = .{ .box_extent = .{ 3, 3 } } },
    .start_string = "58.1....7...5...26..27.4..3.....1..41..........42...........6.87.1..3.....54..9..",
    .solution_string = "586132497437598126912764583629871354158349762374256819243915678791683245865427931",
};

pub const hidden_pair = KnownBoard{
    .board_type = .{ .regular = .{ .box_extent = .{ 3, 3 } } },
    .start_string = ".........9.46.7....768.41..3.97.1.8...8...3...5.3.87.2..75.261....4.32.8.........",
    .solution_string = "583219467914637825276854139349721586728965341651348792497582613165493278832176954",
};

pub const pointing_line = KnownBoard{
    .board_type = .{ .regular = .{ .box_extent = .{ 3, 3 } } },
    .start_string = ".179.36......8....9.....5.7.72.1.43....4.2.7..6437.25.7.1....65....3......56.172.",
    .solution_string = "417953682256187943983246517872519436539462871164378259791824365628735194345691728",
};

pub const box_line_reduction = KnownBoard{
    .board_type = .{ .regular = .{ .box_extent = .{ 3, 3 } } },
    .start_string = ".16..78.3.928.....87...126..48...3..65...9.82.39...65..6.9...2..8...29369246..51.",
    .solution_string = "416527893592836147873491265148265379657319482239784651361958724785142936924673518",
};

pub const skyscraper = KnownBoard{
    .board_type = .{ .regular = .{ .box_extent = .{ 3, 3 } } },
    .start_string = "...7...5.1.4...6......4.2.8..3..5.964........7..2.6......5......7.9..58..8..2.74.",
    .solution_string = "839762154124358679567149238213475896456891327798236415341587962672914583985623741",
};

pub const jigsaw9 = KnownBoard{
    .board_type = .{ .jigsaw = .{ .extent = 9, .box_indices_string = "111111222113444422133455442334455222366657777366559997366659977386858997888888997" } },
    .start_string = ".38.4.1...6.9532......6....97......54..........5..2......6..8...57....6.34.8.....",
    .solution_string = "238549176761953248123465789976184325492318657685792431514627893857231964349876512",
};

pub const backtracking_killer = KnownBoard{
    .board_type = .{ .regular = .{ .box_extent = .{ 3, 3 } } },
    .start_string = "...8.1..........435............7.8........1...2..3....6......75..34........2..6..",
    .solution_string = "237841569186795243594326718315674892469582137728139456642918375853467921971253684",
};

// NOTE: See https://stackoverflow.com/questions/24682039/whats-the-worst-case-valid-sudoku-puzzle-for-simple-backtracking-brute-force-al
pub const naive_backtracking_killer_1 = KnownBoard{
    .board_type = .{ .regular = .{ .box_extent = .{ 3, 3 } } },
    .start_string = "..............3.85..1.2.......5.7.....4...1...9.......5......73..2.1........4...9",
    .solution_string = "987654321246173985351928746128537694634892157795461832519286473472319568863745219",
};

pub const naive_backtracking_killer_2 = KnownBoard{
    .board_type = .{ .regular = .{ .box_extent = .{ 3, 3 } } },
    .start_string = "9..8...........5............2..1...3.1.....6....4...7.7.86.........3.1..4.....2..",
    .solution_string = "972853614146279538583146729624718953817395462359462871798621345265934187431587296",
};

pub const dancing_links_killer = KnownBoard{
    .board_type = .{ .regular = .{ .box_extent = .{ 3, 3 } } },
    .start_string = "........1.....2..3.45.............1...6.....237..6.......1..4.....2.35...8.......",
    .solution_string = "823694751697512843145738269958327614416859372372461985539186427761243598284975136",
};
