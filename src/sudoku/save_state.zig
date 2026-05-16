const std = @import("std");

const board = @import("board.zig");
const game = @import("game.zig");

const SupportedSaveStateVersion = 1;

const SaveMagic = packed struct {
    b0: u8 = 'S',
    b1: u8 = 'U',
    b2: u8 = 'D',
    b3: u8 = 'O',
};

const SaveHeader = packed struct {
    magic: SaveMagic = .{},
    version: u32 = SupportedSaveStateVersion,
};

pub fn save(game_state: *const game.State, writer: *std.Io.Writer) !void {
    try writer.writeStruct(SaveHeader{}, .little);
    try game_state.save(writer);
    try writer.flush();
}

pub fn load(reader: *std.Io.Reader, allocator: std.mem.Allocator) !game.State {
    const header = try reader.takeStruct(SaveHeader, .little);

    std.debug.assert(header.magic == SaveMagic{});
    std.debug.assert(header.version == SupportedSaveStateVersion);

    return try game.State.load(reader, allocator);
}

const known_boards = @import("known_boards.zig");

test "State serialization" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    inline for (known_boards.TestBacktrackingSolver) |known_board| {
        const game_1: game.State = try .init(io, allocator, known_board.rules, known_board.start_string);
        defer game_1.deinit(allocator);

        var allocating_writer = std.Io.Writer.Allocating.init(allocator);
        defer allocating_writer.deinit();

        try save(&game_1, &allocating_writer.writer);

        var reader: std.Io.Reader = .fixed(allocating_writer.writer.buffer[0..allocating_writer.writer.end]);

        const game_2 = try load(&reader, allocator);
        defer game_2.deinit(allocator);

        try std.testing.expectEqual(allocating_writer.writer.end, reader.end);

        const extent_sqr = known_board.rules.type.extent() * known_board.rules.type.extent();

        try std.testing.expectEqualSlices(?board.NumberType, game_1.board.numbers_const(), game_2.board.numbers_const());
        try std.testing.expectEqualSlices(board.MaskType, game_1.candidate_masks[0..extent_sqr], game_2.candidate_masks[0..extent_sqr]);
        try std.testing.expectEqual(game_1.history_index, game_2.history_index);
        try std.testing.expectEqual(game_1.max_history_index, game_2.max_history_index);

        const history_entry_count = game_1.max_history_index + 1;
        for (0..history_entry_count) |i| {
            const start = extent_sqr * i;
            try std.testing.expectEqualSlices(?board.NumberType, game_1.board_history[start .. start + extent_sqr], game_2.board_history[start .. start + extent_sqr]);
            try std.testing.expectEqualSlices(board.MaskType, game_1.candidate_masks_history[start .. start + extent_sqr], game_2.candidate_masks_history[start .. start + extent_sqr]);
        }
    }
}
