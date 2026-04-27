const std = @import("std");

const board = @import("board.zig");
const common = @import("common.zig");
const u32_2 = common.u32_2;
const i32_2 = common.i32_2;

pub const RegularSudoku = struct {
    box_extent: u32_2,
};

pub const JigsawSudoku = struct {
    extent: u32,
    box_indices_max: [board.MaxExtentSqr]u4,
};

pub const Type = union(enum(u8)) {
    regular: RegularSudoku,
    jigsaw: JigsawSudoku,

    pub fn extent(self: @This()) u32 {
        return switch (self) {
            .regular => |regular| regular.box_extent[0] * regular.box_extent[1],
            .jigsaw => |jigsaw| jigsaw.extent,
        };
    }

    pub fn save(self: @This(), writer: *std.Io.Writer) !void {
        try writer.writeByte(@intFromEnum(self));

        switch (self) {
            .regular => |regular| {
                try writer.writeInt(@TypeOf(regular.box_extent[0]), regular.box_extent[0], .little);
                try writer.writeInt(@TypeOf(regular.box_extent[1]), regular.box_extent[1], .little);
            },
            .jigsaw => |jigsaw| {
                try writer.writeInt(@TypeOf(jigsaw.extent), jigsaw.extent, .little);

                for (jigsaw.box_indices_max[0 .. jigsaw.extent * jigsaw.extent]) |index| {
                    try writer.writeByte(index);
                }
            },
        }
    }

    pub fn load(self: *@This(), reader: *std.Io.Reader) !void {
        const Tag = @typeInfo(@This()).@"union".tag_type.?;
        const tag: Tag = @enumFromInt(try reader.takeByte());

        switch (tag) {
            .regular => {
                var regular: RegularSudoku = undefined;
                regular.box_extent[0] = try reader.takeInt(u32, .little);
                regular.box_extent[1] = try reader.takeInt(u32, .little);

                self.* = .{ .regular = regular };
            },
            .jigsaw => {
                var jigsaw: JigsawSudoku = undefined;

                jigsaw.extent = try reader.takeInt(u32, .little);

                for (jigsaw.box_indices_max[0 .. jigsaw.extent * jigsaw.extent]) |*index| {
                    index.* = @intCast(try reader.takeByte());
                }

                self.* = .{ .jigsaw = jigsaw };
            },
        }
    }
};

pub const Rules = struct {
    type: Type,
    chess_anti_king: bool = false,
    chess_anti_knight: bool = false,

    pub fn save(self: @This(), writer: *std.Io.Writer) !void {
        try self.type.save(writer);
        try writer.writeByte(if (self.chess_anti_king) 1 else 0);
        try writer.writeByte(if (self.chess_anti_knight) 1 else 0);
    }

    pub fn load(self: *@This(), reader: *std.Io.Reader) !void {
        try self.type.load(reader);
        self.chess_anti_king = try reader.takeByte() != 0;
        self.chess_anti_knight = try reader.takeByte() != 0;
    }
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

pub fn parse_jigsaw_box_indices(extent: u32, box_indices_string: []const u8) ![board.MaxExtentSqr]u4 {
    const extent_sqr = extent * extent;

    var box_indices_max = std.mem.zeroes([board.MaxExtentSqr]u4);
    const box_indices = box_indices_max[0..extent_sqr];

    if (box_indices_string.len < extent_sqr) {
        @panic("Invalid box indices: string too short");
    } else if (box_indices_string.len > extent_sqr) {
        @panic("Invalid box indices: string too long");
    }

    var region_sizes_max = std.mem.zeroes([board.MaxExtent]u32);
    const region_sizes = region_sizes_max[0..extent];

    for (box_indices, box_indices_string, 0..) |*box_index, char, position| {
        var number: u8 = undefined;

        if (char >= '1' and char <= '9') {
            number = char - '1';
        } else if (char >= 'A' and char <= 'G') {
            number = char - 'A' + 9;
        } else if (char >= 'a' and char <= 'g') {
            number = char - 'a' + 9;
        } else {
            std.debug.print("Invalid character '{c}' in box indices string at position {}\n", .{ char, position });
            return error.IndexInvalid;
        }

        if (number >= extent) {
            std.debug.print("Character '{c}' out of bounds in box indices string at position {}, max is '{c}'\n", .{ char, position, board.MaxNumbersString[number] });
            return error.IndexOutOfBounds;
        }

        box_index.* = @intCast(number);

        region_sizes[number] += 1;
    }

    for (region_sizes, 0..) |region_size, region_index| {
        if (region_size != extent) {
            std.debug.print("Invalid jigsaw region count {} for region '{c}', expected {}\n", .{ region_size, board.MaxNumbersString[region_index], extent });
            return error.InvalidJigsawRegionCount;
        }
    }

    return box_indices_max;
}
