const std = @import("std");

const common = @import("common.zig");
const u32_2 = common.u32_2;

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

pub const MinExtent: comptime_int = 2; // Minimum extent we support
pub const MaxExtent: comptime_int = 16; // Maximum extent we support
pub const MaxNumbersString = [MaxExtent]u8{ '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G' };

pub const RegionIndex = struct {
    set: RegionSet,
    sub_index: usize,
};

pub const RegionSet = enum(usize) {
    Col = 0,
    Row = 1,
    Box = 2,

    Count = 3,
};

pub fn State(extent: comptime_int) type {
    return struct {
        const Self = @This();
        const SelfExtentSqr = extent * extent;
        const SelfNumberType = u4;

        // This struct is used as a helper to iterate over regions of the board without doing index math everywhere.
        const Regions = struct {
            all: [@intFromEnum(RegionSet.Count)][extent][extent]u32,
            box_indices: [SelfExtentSqr]SelfNumberType,

            pub fn get_region_index(self: Regions, set: RegionSet, region_index: usize) RegionIndex {
                _ = self; // Unused
                return .{
                    .set = set,
                    .sub_index = region_index,
                };
            }

            pub fn get(self: Regions, region_index: RegionIndex) [extent]u32 {
                return self.all[@intFromEnum(region_index.set)][region_index.sub_index];
            }

            pub fn get_set(self: Regions, set: RegionSet) [extent][extent]u32 {
                return self.all[@intFromEnum(set)];
            }

            // Get single region
            pub fn col(self: Regions, sub_index: usize) [extent]u32 {
                return self.get(.{ .set = .Col, .sub_index = sub_index });
            }

            pub fn row(self: Regions, sub_index: usize) [extent]u32 {
                return self.get(.{ .set = .Row, .sub_index = sub_index });
            }

            pub fn box(self: Regions, sub_index: usize) [extent]u32 {
                return self.get(.{ .set = .Box, .sub_index = sub_index });
            }

            pub fn init(rules: Rules) Regions {
                var regions: Regions = undefined;

                switch (rules.type) {
                    .regular => |regular| {
                        if (extent != regular.box_extent[0] * regular.box_extent[1]) {
                            @panic("Board extent mismatch with box extents");
                        }

                        regions.box_indices = regular_box_indices(regular.box_extent);
                    },
                    .jigsaw => |jigsaw| {
                        regions.box_indices = jigsaw_box_indices(jigsaw.box_indices_string);
                    },
                }

                var box_region_slots: [extent]u32 = .{0} ** extent;

                for (regions.box_indices, 0..) |box_index, cell_index_usize| {
                    const cell_index: u32 = @intCast(cell_index_usize);
                    const cell_coords = _cell_coord_from_index(cell_index);
                    const box_slot = box_region_slots[box_index];

                    regions.all[@intFromEnum(RegionSet.Col)][cell_coords[0]][cell_coords[1]] = cell_index;
                    regions.all[@intFromEnum(RegionSet.Row)][cell_coords[1]][cell_coords[0]] = cell_index;
                    regions.all[@intFromEnum(RegionSet.Box)][box_index][box_slot] = cell_index;

                    box_region_slots[box_index] += 1;
                }

                for (box_region_slots) |box_slot| {
                    if (box_slot != extent) {
                        @panic("A box region has an invalid number of elements");
                    }
                }

                return regions;
            }

            fn regular_box_indices(box_extent: u32_2) [SelfExtentSqr]SelfNumberType {
                var box_indices: [SelfExtentSqr]SelfNumberType = undefined;

                for (&box_indices, 0..) |*box_index, cell_index| {
                    const cell_coord = _cell_coord_from_index(cell_index);
                    const box_coord_x = (cell_coord[0] / box_extent[0]);
                    const box_coord_y = (cell_coord[1] / box_extent[1]);

                    box_index.* = @intCast(box_coord_y * box_extent[1] + box_coord_x);
                }

                return box_indices;
            }

            fn jigsaw_box_indices(box_indices_string: []const u8) [SelfExtentSqr]SelfNumberType {
                var box_indices: [SelfExtentSqr]SelfNumberType = undefined;

                if (box_indices_string.len < SelfExtentSqr) {
                    @panic("Invalid box indices: string too short");
                } else if (box_indices_string.len > SelfExtentSqr) {
                    @panic("Invalid box indices: string too long");
                }

                var region_sizes: [extent]u32 = .{0} ** extent;

                for (&box_indices, box_indices_string) |*box_index, char| {
                    var number: u8 = undefined;

                    if (char >= '1' and char <= '9') {
                        number = char - '1';
                    } else if (char >= 'A' and char <= 'G') {
                        number = char - 'A' + 9;
                    } else if (char >= 'a' and char <= 'g') {
                        number = char - 'a' + 9;
                    } else {
                        @panic("Invalid character in box indices string");
                    }

                    if (number >= extent) {
                        @panic("Index out of bounds in box indices string");
                    }

                    box_index.* = @intCast(number);

                    region_sizes[number] += 1;
                }

                return box_indices;
            }
        };

        comptime Extent: comptime_int = extent,
        comptime ExtentSqr: comptime_int = extent * extent, // Total amount of elements in a board
        comptime NumbersString: [extent]u8 = MaxNumbersString[0..extent].*,
        comptime MaskType: type = MaskType(extent),

        numbers: [SelfExtentSqr]?SelfNumberType,
        regions: Regions,
        rules: Rules,

        // Creates an empty sudoku board
        pub fn init(rules: Rules) Self {
            return .{
                .numbers = .{null} ** SelfExtentSqr,
                .regions = Regions.init(rules),
                .rules = rules,
            };
        }

        fn _cell_coord_from_index(cell_index: usize) u32_2 {
            const x: u32 = @intCast(cell_index % extent);
            const y: u32 = @intCast(cell_index / extent);

            std.debug.assert(cell_index < SelfExtentSqr);
            std.debug.assert(x < extent and y < extent);

            return .{ x, y };
        }

        fn _cell_index_from_coord(position: u32_2) u32 {
            std.debug.assert(position[0] < extent);
            std.debug.assert(position[1] < extent);

            return position[0] + extent * position[1];
        }

        // FIXME Giant hack! This seems like a Zig limitation
        pub fn cell_coord_from_index(_: Self, cell_index: usize) u32_2 {
            return _cell_coord_from_index(cell_index);
        }

        pub fn cell_index_from_coord(_: Self, position: u32_2) u32 {
            return _cell_index_from_coord(position);
        }

        pub fn mask_for_number(_: Self, number: SelfNumberType) MaskType(extent) {
            return @as(MaskType(extent), 1) << number;
        }

        pub fn full_candidate_mask(self: Self) MaskType(extent) {
            return @intCast((@as(u32, 1) << @intCast(self.Extent)) - 1);
        }

        pub fn fill_board_from_string(self: *Self, sudoku_string: []const u8) void {
            std.debug.assert(sudoku_string.len == self.ExtentSqr);

            for (&self.numbers, sudoku_string) |*board_number_opt, char| {
                var number_opt: ?SelfNumberType = null;

                if (char >= '1' and char <= '9') {
                    number_opt = @intCast(char - '1');
                } else if (char >= 'A' and char <= 'G') {
                    number_opt = @intCast(char - 'A' + 9);
                } else if (char >= 'a' and char <= 'g') {
                    number_opt = @intCast(char - 'a' + 9);
                }

                if (number_opt) |number| {
                    std.debug.assert(number < self.Extent);
                }

                board_number_opt.* = number_opt;
            }
        }

        pub fn string_from_board(self: Self) [self.ExtentSqr]u8 {
            var string: [self.ExtentSqr]u8 = undefined;

            for (self.numbers, &string) |number_opt, *char| {
                char.* = if (number_opt) |number| self.NumbersString[number] else '.';
            }

            return string;
        }

        comptime {
            std.debug.assert(extent >= MinExtent);
            std.debug.assert(extent <= MaxExtent);
        }
    };
}

pub fn MaskType(extent: comptime_int) type {
    if (false) {
        return @Type(.{
            .int = .{
                .signedness = .unsigned,
                .bits = extent,
            },
        });
    } else {
        return u16; // FIXME!!!!
    }
}

test "Basic" {
    const board = State(16).init(.{ .type = .{ .regular = .{ .box_extent = .{ 4, 4 } } } });
    _ = board;
}

test "Ergonomics" {
    var random_buffer: [8]u8 = undefined;
    std.crypto.random.bytes(&random_buffer);

    const seed = std.mem.readInt(u64, &random_buffer, .little);

    var rng = std.Random.Xoroshiro128.init(seed);

    const box_w: u32 = if (rng.random().uintLessThan(u32, 2) == 1) 3 else 4;
    const box_h: u32 = if (rng.random().uintLessThan(u32, 2) == 1) 3 else 4;
    const rules = Rules{ .type = .{ .regular = .{ .box_extent = .{ box_w, box_h } } } };
    const extent = rules.type.extent();

    // Scalarize extent
    inline for (.{ 9, 12, 16 }) |comptime_extent| {
        if (extent == comptime_extent) {
            const board = State(comptime_extent).init(rules);
            _ = board;

            break;
        }
    } else {
        @panic("Invalid sudoku extent!");
    }
}
