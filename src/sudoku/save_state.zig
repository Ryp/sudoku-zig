const std = @import("std");

const game_state = @import("game.zig");

const SupportedSaveStateVersion = 1;
const StaticSudokuExtent = 9;

const GameState = game_state.State(StaticSudokuExtent);

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

pub fn save(game: *const GameState, writer: *std.Io.Writer) !void {
    const header = SaveHeader{};
    try writer.writeStruct(header, .little);

    try game.board.rules.save(writer);

    try writer.flush();
}

pub fn load(game: *GameState, reader: *std.Io.Reader) !void {
    const header = try reader.takeStruct(SaveHeader, .little);

    std.debug.assert(header.magic == SaveMagic{});
    std.debug.assert(header.version == SupportedSaveStateVersion);

    try game.board.rules.load(reader);
}

const known_boards = @import("known_boards.zig");

test "State serialization" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    inline for (known_boards.TestBacktrackingSolver) |known_board| {
        const extent = comptime known_board.rules.type.extent();

        const game_1 = try game_state.State(extent).init(io, allocator, known_board.rules, known_board.start_string);
        defer game_1.deinit(allocator);

        var allocating_writer = std.Io.Writer.Allocating.init(allocator);
        defer allocating_writer.deinit();

        try save(&game_1, &allocating_writer.writer);

        var game_2 = try game_state.State(extent).init_empty_board(allocator);
        defer game_2.deinit(allocator);

        var reader: std.Io.Reader = .fixed(allocating_writer.writer.buffer[0..allocating_writer.writer.end]);

        try load(&game_2, &reader);

        try std.testing.expectEqual(allocating_writer.writer.end, reader.end);
        try std.testing.expectEqual(game_1.board.rules.type.extent(), game_2.board.rules.type.extent());
        // try std.testing.expectEqualSlices(u8, &psx.bios, &psx_2.bios);
    }
}
