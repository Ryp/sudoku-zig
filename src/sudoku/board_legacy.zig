const std = @import("std");
const assert = std.debug.assert;

const game = @import("game.zig");

pub const MaxSudokuExtent = 16;
pub const UnsetNumber: u5 = 0x1F;

const u32_2 = @Vector(2, u32);

pub const RegularSudoku = struct {
    box_w: u32,
    box_h: u32,
};

pub const JigsawSudoku = struct {
    size: u32,
    box_indices_string: []const u8,
};

pub const GameType = union(enum) {
    regular: RegularSudoku,
    jigsaw: JigsawSudoku,
};

pub const BoardState = struct {
    const Self = @This();

    numbers: []u5,
    extent: u32,
    game_type: GameType,
    // Helpers to iterate over regions
    region_offsets: []u32, // Raw memory, shouldn't be used directly
    all_regions: [][]u32,
    col_regions: [][]u32,
    row_regions: [][]u32,
    box_regions: [][]u32,
    box_indices: []u4,

    pub fn create(allocator: std.mem.Allocator, game_type: GameType) !BoardState {
        const extent = switch (game_type) {
            .regular => |regular| regular.box_w * regular.box_h,
            .jigsaw => |jigsaw| jigsaw.size,
        };

        assert(extent > 1);
        assert(extent <= MaxSudokuExtent);

        const board = try allocator.alloc(u5, extent * extent);
        errdefer allocator.free(board);

        for (board) |*cell_number| {
            cell_number.* = UnsetNumber;
        }

        const region_offsets = try allocator.alloc(u32, board.len * 3);
        errdefer allocator.free(region_offsets);

        const all_regions = try allocator.alloc([]u32, extent * 3);
        errdefer allocator.free(all_regions);

        const box_indices = try allocator.alloc(u4, board.len);
        errdefer allocator.free(box_indices);

        // Map regions to raw offset slices
        for (all_regions, 0..) |*region, region_index| {
            const slice_start = region_index * extent;

            region.* = region_offsets[slice_start .. slice_start + extent];
        }

        const col_regions = all_regions[0 * extent .. 1 * extent];
        const row_regions = all_regions[1 * extent .. 2 * extent];
        const box_regions = all_regions[2 * extent .. 3 * extent];

        const board_state = BoardState{
            .numbers = board,
            .extent = extent,
            .game_type = game_type,
            .region_offsets = region_offsets,
            .all_regions = all_regions,
            .col_regions = col_regions,
            .row_regions = row_regions,
            .box_regions = box_regions,
            .box_indices = box_indices,
        };

        switch (game_type) {
            .regular => |regular| {
                board_state.fill_region_indices_regular(regular.box_w, regular.box_h);
            },
            .jigsaw => |jigsaw| {
                board_state.fill_region_indices_from_string(jigsaw.box_indices_string);
            },
        }

        board_state.fill_regions();

        return board_state;
    }

    pub fn destroy(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.numbers);
        allocator.free(self.region_offsets);
        allocator.free(self.all_regions);
        allocator.free(self.box_indices);
    }

    pub fn cell_coord_from_index(self: Self, cell_index: usize) u32_2 {
        const x: u32 = @intCast(cell_index % self.extent);
        const y: u32 = @intCast(cell_index / self.extent);

        assert(x < self.extent and y < self.extent);

        return .{ x, y };
    }

    pub fn cell_index_from_coord(self: Self, position: u32_2) u32 {
        assert(game.all(position < u32_2{ self.extent, self.extent }));
        return position[0] + self.extent * position[1];
    }

    fn fill_regions(self: Self) void {
        for (0..self.extent) |region_index_usize| {
            const col_region = self.col_regions[region_index_usize];
            const row_region = self.row_regions[region_index_usize];

            assert(col_region.len == self.extent);
            assert(row_region.len == self.extent);

            const region_index: u32 = @intCast(region_index_usize);

            for (col_region, row_region, 0..) |*col_cell, *row_cell, cell_index_usize| {
                const cell_index: u32 = @intCast(cell_index_usize);
                col_cell.* = self.cell_index_from_coord(.{ region_index, cell_index });
                row_cell.* = self.cell_index_from_coord(.{ cell_index, region_index });
            }
        }

        var region_slot_full = std.mem.zeroes([MaxSudokuExtent]u32);
        var region_slot = region_slot_full[0..self.extent];

        for (self.box_indices, 0..) |box_index, cell_index| {
            const slot = region_slot[box_index];

            var box_region = self.box_regions[box_index];
            box_region[slot] = @intCast(cell_index);

            region_slot[box_index] += 1;
        }

        for (region_slot) |slot| {
            assert(slot == self.extent);
        }
    }

    fn fill_region_indices_regular(self: Self, box_w: u32, box_h: u32) void {
        for (self.box_indices, 0..) |*box_index, i| {
            const cell_coord = self.cell_coord_from_index(i);
            const box_coord_x = (cell_coord[0] / box_w);
            const box_coord_y = (cell_coord[1] / box_h);

            box_index.* = @intCast(box_coord_x + box_coord_y * box_h);
        }
    }

    fn fill_region_indices_from_string(self: Self, box_indices_string: []const u8) void {
        assert(box_indices_string.len == self.extent * self.extent);

        var region_sizes_full = std.mem.zeroes([MaxSudokuExtent]u32);
        var region_sizes = region_sizes_full[0..self.extent];

        for (self.box_indices, box_indices_string) |*box_index, char| {
            var number: u8 = undefined;

            if (char >= '1' and char <= '9') {
                number = char - '1';
            } else if (char >= 'A' and char <= 'G') {
                number = char - 'A' + 9;
            } else if (char >= 'a' and char <= 'g') {
                number = char - 'a' + 9;
            }

            assert(number < self.extent);

            box_index.* = @intCast(number);

            region_sizes[number] += 1;
        }

        for (region_sizes) |region_size| {
            assert(region_size == self.extent);
        }
    }
};
