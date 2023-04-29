const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const game = @import("../sudoku/game.zig");
const GameState = game.GameState;
const event = @import("../sudoku/event.zig");
const GameEventTag = event.GameEventTag;

const SpriteSheetTileExtent = 19;
const SpriteScreenExtent = 57;
const InvalidMoveTimeSecs: f32 = 0.3;

const GfxState = struct {
    invalid_move_time_secs: f32 = 0.0,
    is_hovered: bool = false,
    is_exploded: bool = false,
};

pub fn range(len: usize) []const void {
    return @as([*]void, undefined)[0..len];
}

fn get_tile_index(number: u8, gfx_cell: GfxState) [2]u8 {
    _ = gfx_cell; // FIXME

    if (number == 9)
        return .{ 6, 1 };

    return .{ number, 0 };
}

fn get_sprite_sheet_rect(position: [2]u8) c.SDL_Rect {
    return c.SDL_Rect{
        .x = position[0] * SpriteSheetTileExtent,
        .y = position[1] * SpriteSheetTileExtent,
        .w = SpriteSheetTileExtent,
        .h = SpriteSheetTileExtent,
    };
}

fn allocate_2d_array_default_init(comptime T: type, allocator: std.mem.Allocator, x: usize, y: usize) ![][]T {
    var array = try allocator.alloc([]T, x);
    errdefer allocator.free(array);

    for (array) |*column| {
        column.* = try allocator.alloc(T, y);
        errdefer allocator.free(column);

        for (column.*) |*cell| {
            cell.* = .{};
        }
    }

    return array;
}

fn deallocate_2d_array(comptime T: type, allocator: std.mem.Allocator, array: [][]T) void {
    for (array) |column| {
        allocator.free(column);
    }

    allocator.free(array);
}

pub fn execute_main_loop(allocator: std.mem.Allocator, game_state: *GameState) !void {
    const width = game_state.extent[0] * SpriteScreenExtent;
    const height = game_state.extent[1] * SpriteScreenExtent;

    if (c.SDL_Init(c.SDL_INIT_EVERYTHING) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Sudoku", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @intCast(c_int, width), @intCast(c_int, height), c.SDL_WINDOW_SHOWN) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    if (c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1") == c.SDL_FALSE) {
        c.SDL_Log("Unable to set hint: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const ren = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(ren);

    // Create sprite sheet
    // Using relative path for now
    const sprite_sheet_surface = c.SDL_LoadBMP("res/tile.bmp") orelse {
        c.SDL_Log("Unable to create BMP surface from file: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };

    defer c.SDL_FreeSurface(sprite_sheet_surface);

    const sprite_sheet_texture = c.SDL_CreateTextureFromSurface(ren, sprite_sheet_surface) orelse {
        c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(sprite_sheet_texture);

    var shouldExit = false;

    var gfx_board = try allocate_2d_array_default_init(GfxState, allocator, game_state.extent[0], game_state.extent[1]);
    var gfx_event_index: usize = 0;
    var last_frame_time_ms: u32 = c.SDL_GetTicks();

    while (!shouldExit) {
        const current_frame_time_ms: u32 = c.SDL_GetTicks();
        const frame_delta_secs = @intToFloat(f32, current_frame_time_ms - last_frame_time_ms) * 0.001;

        // Poll events
        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent) > 0) {
            switch (sdlEvent.type) {
                c.SDL_QUIT => {
                    shouldExit = true;
                },
                c.SDL_KEYDOWN => {
                    if (sdlEvent.key.keysym.sym == c.SDLK_ESCAPE) {
                        shouldExit = true;
                    } else if (sdlEvent.key.keysym.sym >= c.SDLK_1 and sdlEvent.key.keysym.sym <= c.SDLK_9) {
                        const mods = c.SDL_GetModState();
                        const number_index = @intCast(u5, sdlEvent.key.keysym.sym - c.SDLK_1);

                        if ((mods & c.KMOD_SHIFT) != 0) {
                            game.toggle_guess(game_state, number_index);
                        } else {
                            game.input_number(game_state, number_index);
                        }
                    } else if (sdlEvent.key.keysym.sym == c.SDLK_RETURN) {
                        game.solve_basic_rules(game_state);
                    } else if (sdlEvent.key.keysym.sym == c.SDLK_BACKSPACE) {
                        game.solve_extra(game_state);
                    }
                },
                c.SDL_MOUSEBUTTONUP => {
                    const x = @intCast(u16, @divTrunc(sdlEvent.button.x, SpriteScreenExtent));
                    const y = @intCast(u16, @divTrunc(sdlEvent.button.y, SpriteScreenExtent));
                    if (sdlEvent.button.button == c.SDL_BUTTON_LEFT) {
                        game.select(game_state, .{ x, y });
                    } else if (sdlEvent.button.button == c.SDL_BUTTON_RIGHT) {}
                },
                else => {},
            }
        }

        const string = try std.fmt.allocPrintZ(allocator, "Sudoku {d}x{d}", .{ game_state.extent[0], game_state.extent[1] });
        defer allocator.free(string);

        c.SDL_SetWindowTitle(window, string.ptr);

        var mouse_x: c_int = undefined;
        var mouse_y: c_int = undefined;
        _ = c.SDL_GetMouseState(&mouse_x, &mouse_y);
        const hovered_cell_x = @intCast(u16, std.math.max(0, std.math.min(game_state.extent[0], @divTrunc(mouse_x, SpriteScreenExtent))));
        const hovered_cell_y = @intCast(u16, std.math.max(0, std.math.min(game_state.extent[1], @divTrunc(mouse_y, SpriteScreenExtent))));

        for (gfx_board) |column| {
            for (column) |*cell| {
                cell.is_hovered = false;
                cell.invalid_move_time_secs = std.math.max(0.0, cell.invalid_move_time_secs - frame_delta_secs);
            }
        }
        gfx_board[hovered_cell_x][hovered_cell_y].is_hovered = true;

        // Process game events for the gfx side
        for (game_state.event_history[gfx_event_index..game_state.event_history_index]) |game_event| {
            switch (game_event) {
                GameEventTag.discover_number => |e| {
                    if (e.children.len == 0) {
                        gfx_board[e.location[0]][e.location[1]].invalid_move_time_secs = InvalidMoveTimeSecs;
                    }
                },
                GameEventTag.game_end => |e| {
                    for (e.exploded_mines) |mine_location| {
                        gfx_board[mine_location[0]][mine_location[1]].is_exploded = true;
                    }
                },
                else => {},
            }
        }

        // Advance event index since we processed the rest
        gfx_event_index = game_state.event_history_index;

        // Render game
        _ = c.SDL_RenderClear(ren);

        for (game_state.board) |column, i| {
            for (column) |cell, j| {
                const gfx_cell = gfx_board[i][j];

                const sprite_output_pos_rect = c.SDL_Rect{
                    .x = @intCast(c_int, i * SpriteScreenExtent),
                    .y = @intCast(c_int, j * SpriteScreenExtent),
                    .w = SpriteScreenExtent,
                    .h = SpriteScreenExtent,
                };

                // Draw base cell sprite
                {
                    const sprite_sheet_pos = get_tile_index(cell.set_number, gfx_cell);
                    const sprite_sheet_rect = get_sprite_sheet_rect(sprite_sheet_pos);

                    _ = c.SDL_RenderCopy(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_output_pos_rect);

                    if (cell.set_number == 0) {
                        for (range(9)) |_, index| {
                            const hint_mask = @intCast(u9, @as(u32, 1) << @intCast(u5, index));

                            if ((cell.hint_mask & hint_mask) > 0) {
                                var mini_sprite_output_pos_rect = sprite_output_pos_rect;
                                mini_sprite_output_pos_rect.x += @intCast(c_int, @rem(index, 3) * SpriteScreenExtent / 3);
                                mini_sprite_output_pos_rect.y += @intCast(c_int, @divTrunc(index, 3) * SpriteScreenExtent / 3);
                                mini_sprite_output_pos_rect.w = @divTrunc(mini_sprite_output_pos_rect.w, 3);
                                mini_sprite_output_pos_rect.h = @divTrunc(mini_sprite_output_pos_rect.h, 3);

                                const mini_sprite_sheet_pos = get_tile_index(@intCast(u8, index + 1), gfx_cell);
                                const mini_sprite_sheet_rect = get_sprite_sheet_rect(mini_sprite_sheet_pos);

                                _ = c.SDL_RenderCopy(ren, sprite_sheet_texture, &mini_sprite_sheet_rect, &mini_sprite_output_pos_rect);
                            }
                        }
                    }
                }

                // Draw overlay on invalid move
                if (gfx_cell.invalid_move_time_secs > 0.0) {
                    const alpha = gfx_cell.invalid_move_time_secs / InvalidMoveTimeSecs;
                    const sprite_sheet_rect = get_sprite_sheet_rect(.{ 8, 1 });

                    _ = c.SDL_SetTextureAlphaMod(sprite_sheet_texture, @floatToInt(u8, alpha * 255.0));
                    _ = c.SDL_RenderCopy(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_output_pos_rect);
                    _ = c.SDL_SetTextureAlphaMod(sprite_sheet_texture, 255);
                }
            }
        }

        // Present
        c.SDL_RenderPresent(ren);

        last_frame_time_ms = current_frame_time_ms;
    }

    deallocate_2d_array(GfxState, allocator, gfx_board);
}
