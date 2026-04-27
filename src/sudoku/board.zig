const std = @import("std");

const common = @import("common.zig");
const u32_2 = common.u32_2;
const Rules = @import("rules.zig").Rules;

pub const MinExtent: comptime_int = 2; // Minimum extent we support
pub const MaxExtent: comptime_int = 16; // Maximum extent we support
pub const MaxExtentSqr = MaxExtent * MaxExtent;
pub const MaxNumbersString = [MaxExtent]u8{ '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G' };

pub const RegionIndex = struct {
    set: RegionSet,
    sub_index: usize,
};

pub const RegionSet = enum(usize) {
    Col = 0,
    Row = 1,
    Box = 2,
};

pub const NumberType = u4;
pub const MaskType = @Int(.unsigned, MaxExtent);

pub const Board = struct {
    const Self = @This();

    extent: u32,
    numbers_max: [MaxExtentSqr]?NumberType,
    regions: Regions,
    rules: Rules,

    // Creates an empty sudoku board
    pub fn init(rules: Rules) Self {
        return .{
            .extent = rules.type.extent(),
            .numbers_max = .{null} ** MaxExtentSqr,
            .regions = Regions.init(rules),
            .rules = rules,
        };
    }

    pub fn numbers(self: *Self) []?NumberType {
        return self.numbers_max[0 .. self.extent * self.extent];
    }

    pub fn numbers_const(self: *const Self) []const ?NumberType {
        return self.numbers_max[0 .. self.extent * self.extent];
    }

    // FIXME Giant hack! This seems like a Zig limitation
    pub fn cell_coord_from_index(self: Self, cell_index: usize) u32_2 {
        return private_cell_coord_from_index(self.extent, cell_index);
    }

    pub fn cell_index_from_coord(self: Self, position: u32_2) u32 {
        return private_cell_index_from_coord(self.extent, position);
    }

    pub fn mask_for_number(_: Self, number: NumberType) MaskType {
        return @as(MaskType, 1) << number;
    }

    pub fn full_candidate_mask(self: Self) MaskType {
        return @intCast((@as(u32, 1) << @intCast(self.extent)) - 1);
    }

    pub fn fill_board_from_string(self: *Self, sudoku_string: []const u8) void {
        std.debug.assert(sudoku_string.len == self.extent * self.extent);

        for (self.numbers(), sudoku_string) |*board_number_opt, char| {
            var number_opt: ?NumberType = null;

            if (char >= '1' and char <= '9') {
                number_opt = @intCast(char - '1');
            } else if (char >= 'A' and char <= 'G') {
                number_opt = @intCast(char - 'A' + 9);
            } else if (char >= 'a' and char <= 'g') {
                number_opt = @intCast(char - 'a' + 9);
            }

            if (number_opt) |number| {
                std.debug.assert(number < self.extent);
            }

            board_number_opt.* = number_opt;
        }
    }

    pub fn string_from_board(self: *Self) [MaxExtentSqr]u8 {
        var string_max = std.mem.zeroes([MaxExtentSqr]u8);
        const string = string_max[0 .. self.extent * self.extent];

        for (self.numbers(), string) |number_opt, *char| {
            char.* = if (number_opt) |number| MaxNumbersString[number] else '.';
        }

        return string_max;
    }
};

// This struct is used as a helper to iterate over regions of the board without doing index math everywhere.
const Regions = struct {
    extent: u32,
    cols_max: [MaxExtent][MaxExtent]u32,
    rows_max: [MaxExtent][MaxExtent]u32,
    boxes_max: [MaxExtent][MaxExtent]u32,
    box_indices_max: [MaxExtentSqr]NumberType,

    pub fn get_region_index(self: Regions, set: RegionSet, region_index: usize) RegionIndex {
        _ = self; // Unused
        return .{
            .set = set,
            .sub_index = region_index,
        };
    }

    pub fn get(self: *const Regions, region_index: RegionIndex) []const u32 {
        switch (region_index.set) {
            .Col => return self.cols_max[region_index.sub_index][0..self.extent],
            .Row => return self.rows_max[region_index.sub_index][0..self.extent],
            .Box => return self.boxes_max[region_index.sub_index][0..self.extent],
        }
    }

    // Get single region
    pub fn col(self: *const Regions, sub_index: usize) []const u32 {
        return self.get(.{ .set = .Col, .sub_index = sub_index });
    }

    pub fn row(self: *const Regions, sub_index: usize) []const u32 {
        return self.get(.{ .set = .Row, .sub_index = sub_index });
    }

    pub fn box(self: *const Regions, sub_index: usize) []const u32 {
        return self.get(.{ .set = .Box, .sub_index = sub_index });
    }

    pub fn box_indices(self: *const Regions) []const NumberType {
        return self.box_indices_max[0 .. self.extent * self.extent];
    }

    pub fn init(rules: Rules) Regions {
        const extent = rules.type.extent();

        std.debug.assert(extent >= MinExtent);
        std.debug.assert(extent <= MaxExtent);

        var regions: Regions = undefined;

        regions.extent = extent;

        switch (rules.type) {
            .regular => |regular| {
                if (extent != regular.box_extent[0] * regular.box_extent[1]) {
                    @panic("Board extent mismatch with box extents");
                }

                regions.box_indices_max = regular_box_indices(extent, regular.box_extent);
            },
            .jigsaw => |jigsaw| {
                regions.box_indices_max = jigsaw.box_indices_max;
            },
        }

        var box_region_slots_max = std.mem.zeroes([MaxExtent]u32);
        const box_region_slots = box_region_slots_max[0..extent];

        const extent_sqr = extent * extent;

        for (regions.box_indices_max[0..extent_sqr], 0..) |box_index, cell_index_usize| {
            const cell_index: u32 = @intCast(cell_index_usize);
            const cell_coords = private_cell_coord_from_index(extent, cell_index);
            const box_slot = box_region_slots[box_index];

            regions.cols_max[cell_coords[0]][cell_coords[1]] = cell_index;
            regions.rows_max[cell_coords[1]][cell_coords[0]] = cell_index;
            regions.boxes_max[box_index][box_slot] = cell_index;

            box_region_slots[box_index] += 1;
        }

        for (box_region_slots) |box_slot| {
            if (box_slot != extent) {
                @panic("A box region has an invalid number of elements");
            }
        }

        return regions;
    }

    fn regular_box_indices(extent: u32, box_extent: u32_2) [MaxExtentSqr]NumberType {
        var box_indices_max = std.mem.zeroes([MaxExtentSqr]NumberType);
        const indices = box_indices_max[0 .. extent * extent];

        for (indices, 0..) |*box_index, cell_index| {
            const cell_coord = private_cell_coord_from_index(box_extent[0] * box_extent[1], cell_index);
            const box_coord_x = (cell_coord[0] / box_extent[0]);
            const box_coord_y = (cell_coord[1] / box_extent[1]);

            box_index.* = @intCast(box_coord_y * box_extent[1] + box_coord_x);
        }

        return box_indices_max;
    }
};

fn private_cell_coord_from_index(extent: u32, cell_index: usize) u32_2 {
    const x: u32 = @intCast(cell_index % extent);
    const y: u32 = @intCast(cell_index / extent);

    std.debug.assert(cell_index < extent * extent);
    std.debug.assert(x < extent and y < extent);

    return .{ x, y };
}

fn private_cell_index_from_coord(extent: u32, position: u32_2) u32 {
    std.debug.assert(position[0] < extent);
    std.debug.assert(position[1] < extent);

    return position[0] + extent * position[1];
}

test "Basic" {
    const board: Board = .init(.{ .type = .{ .regular = .{ .box_extent = .{ 4, 4 } } } });
    _ = board;
}

test "Ergonomics" {
    var seed_buffer: [8]u8 = undefined;
    std.testing.io.random(&seed_buffer);

    const seed = std.mem.readInt(u64, &seed_buffer, .little);

    var rng = std.Random.Xoroshiro128.init(seed);

    const box_w: u32 = if (rng.random().uintLessThan(u32, 2) == 1) 3 else 4;
    const box_h: u32 = if (rng.random().uintLessThan(u32, 2) == 1) 3 else 4;
    const rules = Rules{ .type = .{ .regular = .{ .box_extent = .{ box_w, box_h } } } };

    const board: Board = .init(rules);
    _ = board;
}
