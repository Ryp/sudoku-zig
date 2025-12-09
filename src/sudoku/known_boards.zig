const board_generic = @import("board_generic.zig");
const Regular3x3 = board_generic.Regular3x3;

pub const KnownBoard = struct {
    rules: board_generic.Rules,
    start_string: []const u8,
    solution_string: []const u8,
};

pub const TestLogicalSolver = .{
    easy,
    hidden_pair,
    pointing_line,
    // box_line_reduction, // Too hard for logical solver to finish
    // skyscraper, // Too hard for logical solver to finish
    easy4x3,
    jigsaw9,
    backtracking_killer,
    naive_backtracking_killer_1,
    naive_backtracking_killer_2,
    // dancing_links_killer, // Too hard for logical solver to finish
    chess_anti_king,
    // chess_anti_king_hard, // Too hard for logical solver to finish
    chess_anti_knight,
};

pub const TestDancingLinksSolver = .{
    easy,
    hidden_pair,
    pointing_line,
    box_line_reduction,
    skyscraper,
    easy4x3,
    jigsaw9,
    backtracking_killer,
    naive_backtracking_killer_1,
    naive_backtracking_killer_2,
    dancing_links_killer,
    // chess_anti_king, // FIXME Unsupported
    // chess_anti_king_hard, // FIXME Unsupported
    // chess_anti_knight, // FIXME Unsupported
};

pub const TestBacktrackingSolver = .{
    easy,
    hidden_pair,
    pointing_line,
    box_line_reduction,
    skyscraper,
    // easy4x3, // NOTE: Too slow in debug mode but should work
    jigsaw9,
    backtracking_killer,
    naive_backtracking_killer_1,
    naive_backtracking_killer_2,
    // dancing_links_killer, // NOTE: Too slow in debug mode but should work
    // chess_anti_king, // FIXME Unsupported
    // chess_anti_king_hard, // FIXME Unsupported
    // chess_anti_knight, // FIXME Unsupported
};

pub const easy = KnownBoard{
    .rules = Regular3x3,
    .start_string = "58.1....7...5...26..27.4..3.....1..41..........42...........6.87.1..3.....54..9..",
    .solution_string = "586132497437598126912764583629871354158349762374256819243915678791683245865427931",
};

pub const hidden_pair = KnownBoard{
    .rules = Regular3x3,
    .start_string = ".........9.46.7....768.41..3.97.1.8...8...3...5.3.87.2..75.261....4.32.8.........",
    .solution_string = "583219467914637825276854139349721586728965341651348792497582613165493278832176954",
};

pub const pointing_line = KnownBoard{
    .rules = Regular3x3,
    .start_string = "..47...5.1.3..9.7............5.4.8..3.......2..8215.4....67..8..5.......9...834..",
    .solution_string = "684732159123459678579168234215346897346897512798215346432671985851924763967583421",
};

pub const box_line_reduction = KnownBoard{
    .rules = Regular3x3,
    .start_string = ".16..78.3.928.....87...126..48...3..65...9.82.39...65..6.9...2..8...29369246..51.",
    .solution_string = "416527893592836147873491265148265379657319482239784651361958724785142936924673518",
};

pub const skyscraper = KnownBoard{
    .rules = Regular3x3,
    .start_string = "...7...5.1.4...6......4.2.8..3..5.964........7..2.6......5......7.9..58..8..2.74.",
    .solution_string = "839762154124358679567149238213475896456891327798236415341587962672914583985623741",
};

pub const easy4x3 = KnownBoard{
    .rules = .{ .type = .{ .regular = .{ .box_extent = .{ 4, 3 } } } },
    .start_string = "8.9....B.4C.C......3.B9...B5..A8.2...2.4..5........9........7...1B69...32...C47A...B........5........1..A.7...5.87..13...8A.3......2.14.5....8.C",
    .solution_string = "839A721B64C5C72165438B9A64B59CA872311234A85C96B75B694327CA187AC81B6925432516C47A398BAC73B9865124498B2135AC76B65287C413A998AC36B1475231475A92B86C",
};

pub const jigsaw9 = KnownBoard{
    .rules = .{ .type = .{ .jigsaw = .{ .extent = 9, .box_indices_string = "111111222113444422133455442334455222366657777366559997366659977386858997888888997" } } },
    .start_string = ".38.4.1...6.9532......6....97......54..........5..2......6..8...57....6.34.8.....",
    .solution_string = "238549176761953248123465789976184325492318657685792431514627893857231964349876512",
};

pub const backtracking_killer = KnownBoard{
    .rules = Regular3x3,
    .start_string = "...8.1..........435............7.8........1...2..3....6......75..34........2..6..",
    .solution_string = "237841569186795243594326718315674892469582137728139456642918375853467921971253684",
};

// NOTE: See https://stackoverflow.com/questions/24682039/whats-the-worst-case-valid-sudoku-puzzle-for-simple-backtracking-brute-force-al
pub const naive_backtracking_killer_1 = KnownBoard{
    .rules = Regular3x3,
    .start_string = "..............3.85..1.2.......5.7.....4...1...9.......5......73..2.1........4...9",
    .solution_string = "987654321246173985351928746128537694634892157795461832519286473472319568863745219",
};

pub const naive_backtracking_killer_2 = KnownBoard{
    .rules = Regular3x3,
    .start_string = "9..8...........5............2..1...3.1.....6....4...7.7.86.........3.1..4.....2..",
    .solution_string = "972853614146279538583146729624718953817395462359462871798621345265934187431587296",
};

pub const dancing_links_killer = KnownBoard{
    .rules = Regular3x3,
    .start_string = "........1.....2..3.45.............1...6.....237..6.......1..4.....2.35...8.......",
    .solution_string = "823694751697512843145738269958327614416859372372461985539186427761243598284975136",
};

pub const chess_anti_king = KnownBoard{
    .rules = .{ .type = .{ .regular = .{ .box_extent = .{ 3, 3 } } }, .chess_anti_king = true },
    .start_string = "..2.7.5.3.5.968..........8.4.3.9..1...9..5..8.....2...825....69.....6..7...38....",
    .solution_string = "682174593354968721197523486463897215279415638518632974825741369931256847746389152",
};

pub const chess_anti_king_hard = KnownBoard{
    .rules = .{ .type = .{ .regular = .{ .box_extent = .{ 3, 3 } } }, .chess_anti_king = true },
    .start_string = "...628.....9...3...6.....1.7.......84.......56.......3.8.....9...5...7.....971...",
    .solution_string = "173628549529147386864395217732514968498736125651289473287453691915862734346971852",
};

pub const chess_anti_knight = KnownBoard{
    .rules = .{ .type = .{ .regular = .{ .box_extent = .{ 3, 3 } } }, .chess_anti_knight = true },
    .start_string = "........9.3.9........167..4...6....8.73.51.62........16.5..24....45.....7.....68.",
    .solution_string = "546238179137945826829167534251679348473851962968324751685792413314586297792413685",
};
