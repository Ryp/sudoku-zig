const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const game = @import("../sudoku/game.zig");
const GameState = game.GameState;

const NumbersString = [_][*:0]const u8{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "G" };
const SpriteSheetTileExtent = 19;
const SpriteScreenExtent = 57;
const InvalidMoveTimeSecs: f32 = 0.3;
const font_size: u32 = 50;
const font_size_small: u32 = 16;

const GfxState = struct {
    invalid_move_time_secs: f32 = 0.0,
    is_hovered: bool = false,
    is_exploded: bool = false,
};

// Soon to be deprecated in zig 0.11 for 0..x style ranges
fn range(len: usize) []const void {
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
    const width = game_state.extent * SpriteScreenExtent;
    const height = game_state.extent * SpriteScreenExtent;
    const bg_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const text_color = c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

    if (c.SDL_Init(c.SDL_INIT_EVERYTHING) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    if (c.TTF_Init() != 0) {
        c.SDL_Log("Unable to initialize TTF: %s", c.TTF_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.TTF_Quit();

    var font = c.TTF_OpenFont("./res/FreeSans.ttf", font_size) orelse {
        c.SDL_Log("TTF error: %s", c.TTF_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.TTF_CloseFont(font);

    var font_small = c.TTF_OpenFont("./res/FreeSansBold.ttf", font_size_small) orelse {
        c.SDL_Log("TTF error: %s", c.TTF_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.TTF_CloseFont(font_small);

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

    var text_surfaces = try allocator.alloc(*c.SDL_Surface, game_state.extent);
    defer allocator.free(text_surfaces);

    var text_textures = try allocator.alloc(*c.SDL_Texture, game_state.extent);
    defer allocator.free(text_textures);

    for (range(game_state.extent)) |_, i| {
        text_surfaces[i] = c.TTF_RenderText_LCD(font, NumbersString[i], text_color, bg_color);
        text_textures[i] = c.SDL_CreateTextureFromSurface(ren, text_surfaces[i]) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
    }

    var text_small_surfaces = try allocator.alloc(*c.SDL_Surface, game_state.extent);
    defer allocator.free(text_small_surfaces);

    var text_small_textures = try allocator.alloc(*c.SDL_Texture, game_state.extent);
    defer allocator.free(text_small_textures);

    for (range(game_state.extent)) |_, i| {
        text_small_surfaces[i] = c.TTF_RenderText_LCD(font_small, NumbersString[i], text_color, bg_color);
        text_small_textures[i] = c.SDL_CreateTextureFromSurface(ren, text_small_surfaces[i]) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
    }

    var shouldExit = false;

    var gfx_board = try allocate_2d_array_default_init(GfxState, allocator, game_state.extent, game_state.extent);
    var last_frame_time_ms: u32 = c.SDL_GetTicks();

    while (!shouldExit) {
        const current_frame_time_ms: u32 = c.SDL_GetTicks();
        const frame_delta_secs = @intToFloat(f32, current_frame_time_ms - last_frame_time_ms) * 0.001;

        // Poll events
        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent) > 0) {
            const mods = c.SDL_GetModState();
            const is_any_ctrl_pressed = (mods & c.KMOD_CTRL) != 0;
            const is_any_shift_pressed = (mods & c.KMOD_SHIFT) != 0;

            switch (sdlEvent.type) {
                c.SDL_QUIT => {
                    shouldExit = true;
                },
                c.SDL_KEYDOWN => {
                    if (sdlEvent.key.keysym.sym == c.SDLK_ESCAPE) {
                        shouldExit = true;
                    } else if (sdlEvent.key.keysym.sym >= c.SDLK_1 and sdlEvent.key.keysym.sym <= c.SDLK_9) {
                        const number_index = @intCast(u5, sdlEvent.key.keysym.sym - c.SDLK_1);

                        if (is_any_shift_pressed) {
                            game.player_toggle_guess(game_state, number_index);
                        } else {
                            game.player_input_number(game_state, number_index);
                        }
                    } else if (sdlEvent.key.keysym.sym == c.SDLK_z and is_any_ctrl_pressed) {
                        if (is_any_shift_pressed) {
                            game.player_redo(game_state);
                        } else {
                            game.player_undo(game_state);
                        }
                    } else if (sdlEvent.key.keysym.sym == c.SDLK_RETURN) {
                        game.solve_basic_rules(game_state);
                    } else if (sdlEvent.key.keysym.sym == c.SDLK_BACKSPACE) {
                        game.solve_extra(game_state);
                    }
                },
                c.SDL_MOUSEBUTTONUP => {
                    const x = @intCast(u32, @divTrunc(sdlEvent.button.x, SpriteScreenExtent));
                    const y = @intCast(u32, @divTrunc(sdlEvent.button.y, SpriteScreenExtent));
                    if (sdlEvent.button.button == c.SDL_BUTTON_LEFT) {
                        game.player_select(game_state, .{ x, y });
                    }
                },
                else => {},
            }
        }

        const string = try std.fmt.allocPrintZ(allocator, "Sudoku {d}x{d}", .{ game_state.extent, game_state.extent });
        defer allocator.free(string);

        c.SDL_SetWindowTitle(window, string.ptr);

        var mouse_x: c_int = undefined;
        var mouse_y: c_int = undefined;
        _ = c.SDL_GetMouseState(&mouse_x, &mouse_y);
        const hovered_cell_x = @intCast(u16, std.math.max(0, std.math.min(game_state.extent, @divTrunc(mouse_x, SpriteScreenExtent))));
        const hovered_cell_y = @intCast(u16, std.math.max(0, std.math.min(game_state.extent, @divTrunc(mouse_y, SpriteScreenExtent))));

        for (gfx_board) |column| {
            for (column) |*cell| {
                cell.is_hovered = false;
                cell.invalid_move_time_secs = std.math.max(0.0, cell.invalid_move_time_secs - frame_delta_secs);
            }
        }
        gfx_board[hovered_cell_x][hovered_cell_y].is_hovered = true;

        // Render game
        _ = c.SDL_SetRenderDrawColor(ren, bg_color.r, bg_color.g, bg_color.b, bg_color.a);
        _ = c.SDL_RenderClear(ren);

        for (game_state.board) |cell, flat_index| {
            const cell_index = game.flat_index_to_2d(game_state.extent, flat_index);

            const cell_rect = c.SDL_Rect{
                .x = @intCast(c_int, cell_index[0] * SpriteScreenExtent),
                .y = @intCast(c_int, cell_index[1] * SpriteScreenExtent),
                .w = SpriteScreenExtent,
                .h = SpriteScreenExtent,
            };

            // Draw base cell sprite
            {
                if (cell.set_number != 0) {
                    const number_index: u32 = cell.set_number - 1;
                    var glyph_rect = std.mem.zeroes(c.SDL_Rect);

                    if (c.TTF_SizeText(font, NumbersString[number_index], &glyph_rect.w, &glyph_rect.h) != 0) {
                        c.SDL_Log("TTF error: %s", c.TTF_GetError());
                        return error.SDLInitializationFailed;
                    }

                    var glyph_out_rect = glyph_rect;
                    glyph_out_rect.x += cell_rect.x + @divTrunc((cell_rect.w - glyph_rect.w), 2);
                    glyph_out_rect.y += cell_rect.y + @divTrunc((cell_rect.h - glyph_rect.h), 2);

                    _ = c.SDL_RenderCopy(ren, text_textures[number_index], &glyph_rect, &glyph_out_rect);
                }

                if (cell.set_number == 0) {
                    for (range(game_state.extent)) |_, index| {
                        const hint_mask = @intCast(u9, @as(u32, 1) << @intCast(u5, index));

                        if ((cell.hint_mask & hint_mask) > 0) {
                            var candidate_rect = cell_rect;
                            candidate_rect.x += @intCast(c_int, @rem(index, 3) * SpriteScreenExtent / 3);
                            candidate_rect.y += @intCast(c_int, @divTrunc(index, 3) * SpriteScreenExtent / 3);
                            candidate_rect.w = @divTrunc(cell_rect.w, 3);
                            candidate_rect.h = @divTrunc(cell_rect.h, 3);

                            var glyph_rect = std.mem.zeroes(c.SDL_Rect);

                            if (c.TTF_SizeText(font_small, NumbersString[index], &glyph_rect.w, &glyph_rect.h) != 0) {
                                c.SDL_Log("TTF error: %s", c.TTF_GetError());
                                return error.SDLInitializationFailed;
                            }

                            var glyph_out_rect = glyph_rect;
                            glyph_out_rect.x += candidate_rect.x + @divTrunc((candidate_rect.w - glyph_rect.w), 2);
                            glyph_out_rect.y += candidate_rect.y + @divTrunc((candidate_rect.h - glyph_rect.h), 2);

                            _ = c.SDL_RenderCopy(ren, text_small_textures[index], &glyph_rect, &glyph_out_rect);
                        }
                    }
                }
            }
        }

        _ = c.SDL_SetRenderDrawColor(ren, text_color.r, text_color.g, text_color.b, text_color.a);

        // Draw thin grid
        for (range(game_state.extent + 1)) |_, index| {
            const horizontal_rect = c.SDL_Rect{
                .x = @intCast(c_int, index * SpriteScreenExtent),
                .y = 0,
                .w = 1,
                .h = @intCast(c_int, game_state.extent * SpriteScreenExtent),
            };

            const vertical_rect = c.SDL_Rect{
                .x = 0,
                .y = @intCast(c_int, index * SpriteScreenExtent),
                .w = @intCast(c_int, game_state.extent * SpriteScreenExtent),
                .h = 1,
            };

            _ = c.SDL_RenderFillRect(ren, &vertical_rect);
            _ = c.SDL_RenderFillRect(ren, &horizontal_rect);
        }

        // Draw horizontal lines
        for (range(game_state.box_h + 1)) |_, index| {
            const rect = c.SDL_Rect{
                .x = @intCast(c_int, index * game_state.box_w * SpriteScreenExtent) - 1,
                .y = 0,
                .w = 3,
                .h = @intCast(c_int, game_state.extent * SpriteScreenExtent),
            };

            _ = c.SDL_RenderFillRect(ren, &rect);
        }

        // Draw vertical lines
        for (range(game_state.box_w + 1)) |_, index| {
            const rect = c.SDL_Rect{
                .x = 0,
                .y = @intCast(c_int, index * game_state.box_h * SpriteScreenExtent) - 1,
                .w = @intCast(c_int, game_state.extent * SpriteScreenExtent),
                .h = 3,
            };

            _ = c.SDL_RenderFillRect(ren, &rect);
        }

        // Present
        c.SDL_RenderPresent(ren);

        last_frame_time_ms = current_frame_time_ms;
    }

    for (range(game_state.extent)) |_, i| {
        c.SDL_DestroyTexture(text_textures[i]);
        c.SDL_FreeSurface(text_surfaces[i]);
        c.SDL_DestroyTexture(text_small_textures[i]);
        c.SDL_FreeSurface(text_small_surfaces[i]);
    }

    deallocate_2d_array(GfxState, allocator, gfx_board);
}
