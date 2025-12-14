const common = @import("common.zig");
const u32_2 = common.u32_2;
const i32_2 = common.i32_2;

pub const RegularSudoku = struct {
    box_extent: u32_2,
};

pub const JigsawSudoku = struct {
    extent: u32,
    box_indices_string: []const u8,
};

pub const Type = union(enum) {
    regular: RegularSudoku,
    jigsaw: JigsawSudoku,

    pub fn extent(self: @This()) u32 {
        return switch (self) {
            .regular => |regular| regular.box_extent[0] * regular.box_extent[1],
            .jigsaw => |jigsaw| jigsaw.extent,
        };
    }
};

pub const Rules = struct {
    type: Type,
    chess_anti_king: bool = false,
    chess_anti_knight: bool = false,
};

pub const Regular3x3 = Rules{ .type = .{ .regular = .{
    .box_extent = .{ 3, 3 },
} } };

// NOTE: Anti-king mean all offsets from the king's move but for sudoku that just means immediate diagonals since the rest is covered by row/col rules
pub const AntiKingOffsets = [_]i32_2{
    .{ -1, -1 },
    .{ 1, -1 },
    .{ -1, 1 },
    .{ 1, 1 },
};

pub const AntiKnightOffsets = [_]i32_2{
    .{ -2, -1 },
    .{ 2, -1 },
    .{ -2, 1 },
    .{ 2, 1 },
    .{ -1, -2 },
    .{ 1, -2 },
    .{ -1, 2 },
    .{ 1, 2 },
};
