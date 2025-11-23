const std = @import("std");

const common = @import("common.zig");
const u32_2 = common.u32_2;

pub const RegularSudoku = struct {
    box_extent: u32_2,
};

pub const JigsawSudoku = struct {
    size: u32,
    box_indices_string: []const u8,
};

pub const BoardType = union(enum) {
    regular: RegularSudoku,
    jigsaw: JigsawSudoku,
};

const MinExtent: comptime_int = 2; // Minimum extent we support
const MaxExtent: comptime_int = 16; // Maximum extent we support

pub fn board_state(extent: comptime_int) type {
    return struct {
        const Self = @This();
        const NumberType = u4;

        const Extent: comptime_int = extent; // Boards are always square, extent is the length of one side
        const ExtentSqr: comptime_int = Extent * Extent; // Total amount of elements in a board

        // This struct is used as a helper to iterate over regions of the board without doing index math everywhere.
        const Regions = struct {
            col: [Extent][Extent]u32,
            row: [Extent][Extent]u32,
            box: [Extent][Extent]u32,
            box_indices: [ExtentSqr]NumberType,

            pub fn init(board_type: BoardType) Regions {
                var regions: Regions = undefined;

                switch (board_type) {
                    .regular => |regular| {
                        if (Extent != regular.box_extent[0] * regular.box_extent[1]) {
                            @panic("Board extent mismatch with box extents");
                        }

                        regions.box_indices = regular_box_indices(regular.box_extent);
                    },
                    .jigsaw => |jigsaw| {
                        regions.box_indices = jigsaw_box_indices(jigsaw.box_indices_string);
                    },
                }

                for (0..Extent) |region_index_usize| {
                    const col_region = &regions.col[region_index_usize];
                    const row_region = &regions.row[region_index_usize];

                    const region_index: u32 = @intCast(region_index_usize);

                    for (col_region, row_region, 0..) |*col_cell, *row_cell, cell_index_usize| {
                        const cell_index: u32 = @intCast(cell_index_usize);
                        col_cell.* = cell_index_from_coord(.{ region_index, cell_index });
                        row_cell.* = cell_index_from_coord(.{ cell_index, region_index });
                    }
                }

                var box_region_slots: [Extent]u32 = .{0} ** Extent;

                for (regions.box_indices, 0..) |box_index, cell_index| {
                    const slot = box_region_slots[box_index];

                    regions.box[box_index][slot] = @intCast(cell_index);

                    box_region_slots[box_index] += 1;
                }

                for (box_region_slots) |box_slot| {
                    if (box_slot != Extent) {
                        @panic("A box region has an invalid number of elements");
                    }
                }

                return regions;
            }

            fn regular_box_indices(box_extent: u32_2) [ExtentSqr]NumberType {
                var box_indices: [ExtentSqr]NumberType = undefined;

                for (&box_indices, 0..) |*box_index, cell_index| {
                    const cell_coord = cell_coord_from_index(cell_index);
                    const box_coord_x = (cell_coord[0] / box_extent[0]);
                    const box_coord_y = (cell_coord[1] / box_extent[1]);

                    box_index.* = @intCast(box_coord_y * box_extent[1] + box_coord_x);
                }

                return box_indices;
            }

            fn jigsaw_box_indices(box_indices_string: []const u8) [ExtentSqr]NumberType {
                var box_indices: [ExtentSqr]NumberType = undefined;

                if (box_indices_string.len < ExtentSqr) {
                    @panic("Invalid box indices: string too short");
                } else if (box_indices_string.len > ExtentSqr) {
                    @panic("Invalid box indices: string too long");
                }

                var region_sizes: [Extent]u32 = .{0} ** Extent;

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

                    if (number >= Extent) {
                        @panic("Index out of bounds in box indices string");
                    }

                    box_index.* = @intCast(number);

                    region_sizes[number] += 1;
                }

                return box_indices;
            }
        };

        numbers: [ExtentSqr]?NumberType,
        regions: Regions,

        // Creates an empty sudoku board
        pub fn init(board_type: BoardType) Self {
            return .{
                .numbers = .{null} ** ExtentSqr,
                .regions = Regions.init(board_type),
            };
        }

        pub fn cell_coord_from_index(cell_index: usize) u32_2 {
            std.debug.assert(cell_index < ExtentSqr);

            const x: u32 = @intCast(cell_index % Extent);
            const y: u32 = @intCast(cell_index / Extent);

            std.debug.assert(x < Extent and y < Extent);

            return .{ x, y };
        }

        pub fn cell_index_from_coord(position: u32_2) u32 {
            std.debug.assert(position[0] < Extent);
            std.debug.assert(position[1] < Extent);

            return position[0] + Extent * position[1];
        }

        comptime {
            std.debug.assert(Extent >= MinExtent);
            std.debug.assert(Extent <= MaxExtent);
        }
    };
}

test "Basic" {
    const board = board_state(16).init(.{ .regular = .{ .box_extent = .{ 4, 4 } } });
    _ = board;
}

test "Ergonomics" {
    var random_buffer: [8]u8 = undefined;
    std.crypto.random.bytes(&random_buffer);

    const seed = std.mem.readInt(u64, &random_buffer, .little);

    var rng = std.Random.Xoroshiro128.init(seed);

    const box_w: u32 = if (rng.random().uintLessThan(u32, 2) == 1) 3 else 4;
    const box_h: u32 = if (rng.random().uintLessThan(u32, 2) == 1) 3 else 4;
    const extent = box_w * box_h;
    const board_type = BoardType{ .regular = .{ .box_extent = .{ box_w, box_h } } };

    // Scalarize extent
    inline for (.{ 9, 12, 16 }) |comptime_extent| {
        if (extent == comptime_extent) {
            const board = board_state(comptime_extent).init(board_type);
            _ = board;

            break;
        }
    } else {
        @panic("Invalid sudoku extent!");
    }
}
