const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const sudoku = @import("../sudoku/game.zig");
const GameState = sudoku.GameState;
const UnsetNumber = sudoku.UnsetNumber;
const u32_2 = sudoku.u32_2;
const all = sudoku.all;
const event = @import("../sudoku/event.zig");

const NumbersString = [_][*:0]const u8{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "G" };
const SpriteScreenExtent = 80;
const FontSize: u32 = SpriteScreenExtent - 10;
const FontSizeSmall: u32 = SpriteScreenExtent / 4;
const BgColor = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
const HighlightColor = c.SDL_Color{ .r = 250, .g = 243, .b = 57, .a = 255 };
const HighlightRegionColor = c.SDL_Color{ .r = 130, .g = 188, .b = 232, .a = 255 };
const SameNumberHighlightColor = c.SDL_Color{ .r = 250, .g = 57, .b = 243, .a = 255 };
const BoxBgColor = c.SDL_Color{ .r = 220, .g = 220, .b = 220, .a = 255 };
const TextColor = c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

// NOTE: This only works for regular sudokus (regular rectangle regions)
fn deprecated_box_coord_from_cell(game: *GameState, cell_coord: u32_2) u32_2 {
    const x = (cell_coord[0] / game.box_w);
    const y = (cell_coord[1] / game.box_h);

    return .{ x, y };
}

fn get_candidate_layout(game_extent: u32) @Vector(2, u32) {
    if (game_extent > 12) {
        return .{ 4, 4 };
    } else if (game_extent > 9) {
        return .{ 4, 3 };
    } else if (game_extent > 6) {
        return .{ 3, 3 };
    } else if (game_extent > 4) {
        return .{ 3, 2 };
    } else if (game_extent > 2) {
        return .{ 2, 2 };
    } else {
        return .{ game_extent, 1 };
    }
}

fn input_number(game: *GameState, candidate_mode: bool, number: u4) void {
    if (candidate_mode) {
        sudoku.player_toggle_guess(game, number);
    } else {
        sudoku.player_input_number(game, number);
    }
}

pub fn execute_main_loop(allocator: std.mem.Allocator, game: *GameState) !void {
    const width = game.extent * SpriteScreenExtent;
    const height = game.extent * SpriteScreenExtent;

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

    var font = c.TTF_OpenFont("./res/FreeSans.ttf", FontSize) orelse {
        c.SDL_Log("TTF error: %s", c.TTF_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.TTF_CloseFont(font);

    var font_small = c.TTF_OpenFont("./res/FreeSansBold.ttf", FontSizeSmall) orelse {
        c.SDL_Log("TTF error: %s", c.TTF_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.TTF_CloseFont(font_small);

    const window = c.SDL_CreateWindow("Sudoku", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @intCast(width), @intCast(height), c.SDL_WINDOW_SHOWN) orelse {
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

    var text_surfaces = try allocator.alloc(*c.SDL_Surface, game.extent);
    defer allocator.free(text_surfaces);

    var text_textures = try allocator.alloc(*c.SDL_Texture, game.extent);
    defer allocator.free(text_textures);

    const numbers_string = NumbersString[0..game.extent];

    for (text_surfaces, text_textures, numbers_string) |*surface, *texture, number_string| {
        surface.* = c.TTF_RenderText_LCD(font, number_string, TextColor, BgColor);
        texture.* = c.SDL_CreateTextureFromSurface(ren, surface.*) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        _ = c.SDL_SetTextureBlendMode(texture.*, c.SDL_BLENDMODE_MUL);
    }

    var text_small_surfaces = try allocator.alloc(*c.SDL_Surface, game.extent);
    defer allocator.free(text_small_surfaces);

    var text_small_textures = try allocator.alloc(*c.SDL_Texture, game.extent);
    defer allocator.free(text_small_textures);

    for (text_small_surfaces, text_small_textures, numbers_string) |*surface, *texture, number_string| {
        surface.* = c.TTF_RenderText_LCD(font_small, number_string, TextColor, BgColor);
        texture.* = c.SDL_CreateTextureFromSurface(ren, surface.*) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        _ = c.SDL_SetTextureBlendMode(texture.*, c.SDL_BLENDMODE_MUL);
    }

    const title_string = try std.fmt.allocPrintZ(allocator, "Sudoku", .{});
    defer allocator.free(title_string);

    c.SDL_SetWindowTitle(window, title_string.ptr);

    const candidate_layout = get_candidate_layout(game.extent);

    var should_exit = false;

    while (!should_exit) {
        // Poll events
        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent) > 0) {
            const mods = c.SDL_GetModState();
            const is_any_ctrl_pressed = (mods & c.KMOD_CTRL) != 0;
            const is_any_shift_pressed = (mods & c.KMOD_SHIFT) != 0;

            switch (sdlEvent.type) {
                c.SDL_QUIT => {
                    should_exit = true;
                },
                c.SDL_KEYDOWN => {
                    switch (sdlEvent.key.keysym.sym) {
                        c.SDLK_ESCAPE => {
                            should_exit = true;
                        },
                        c.SDLK_DELETE, c.SDLK_0 => {
                            sudoku.player_clear_number(game);
                        },
                        c.SDLK_1...c.SDLK_9 => |sym| {
                            input_number(game, is_any_shift_pressed, @intCast(sym - c.SDLK_1));
                        },
                        c.SDLK_a => {
                            input_number(game, is_any_shift_pressed, 9);
                        },
                        c.SDLK_b => {
                            input_number(game, is_any_shift_pressed, 10);
                        },
                        c.SDLK_c => {
                            input_number(game, is_any_shift_pressed, 11);
                        },
                        c.SDLK_d => {
                            input_number(game, is_any_shift_pressed, 12);
                        },
                        c.SDLK_e => {
                            input_number(game, is_any_shift_pressed, 13);
                        },
                        c.SDLK_f => {
                            input_number(game, is_any_shift_pressed, 14);
                        },
                        c.SDLK_g => {
                            input_number(game, is_any_shift_pressed, 15);
                        },
                        c.SDLK_z => {
                            if (is_any_ctrl_pressed) {
                                if (is_any_shift_pressed) {
                                    sudoku.player_redo(game);
                                } else {
                                    sudoku.player_undo(game);
                                }
                            }
                        },
                        c.SDLK_h => {
                            if (is_any_shift_pressed) {
                                sudoku.player_clear_hints(game);
                            } else {
                                sudoku.player_fill_hints(game);
                            }
                        },
                        c.SDLK_LEFT => {
                            if (game.selected_cell[0] > 0)
                                sudoku.player_toggle_select(game, game.selected_cell - u32_2{ 1, 0 });
                        },
                        c.SDLK_RIGHT => {
                            if (game.selected_cell[0] + 1 < game.extent)
                                sudoku.player_toggle_select(game, game.selected_cell + u32_2{ 1, 0 });
                        },
                        c.SDLK_UP => {
                            if (game.selected_cell[1] > 0)
                                sudoku.player_toggle_select(game, game.selected_cell - u32_2{ 0, 1 });
                        },
                        c.SDLK_DOWN => {
                            if (game.selected_cell[1] + 1 < game.extent)
                                sudoku.player_toggle_select(game, game.selected_cell + u32_2{ 0, 1 });
                        },
                        c.SDLK_RETURN => {
                            if (is_any_shift_pressed) {
                                sudoku.player_solve_human_step(game); // FIXME undocumented because it's not user-friendly yet
                            } else {
                                sudoku.player_solve_brute_force(game);
                            }
                        },
                        else => {},
                    }
                },
                c.SDL_MOUSEBUTTONUP => {
                    const x: u32 = @intCast(@divTrunc(sdlEvent.button.x, SpriteScreenExtent));
                    const y: u32 = @intCast(@divTrunc(sdlEvent.button.y, SpriteScreenExtent));
                    if (sdlEvent.button.button == c.SDL_BUTTON_LEFT) {
                        sudoku.player_toggle_select(game, .{ x, y });
                    }
                },
                else => {},
            }
        }

        var highlight_mask: u16 = 0;
        if (all(game.selected_cell < u32_2{ game.extent, game.extent })) {
            const cell = sudoku.cell_at(game, game.selected_cell);

            if (cell.number != UnsetNumber) {
                highlight_mask = sudoku.mask_for_number(@intCast(cell.number));
            }
        }

        // Render game
        _ = c.SDL_SetRenderDrawColor(ren, BgColor.r, BgColor.g, BgColor.b, BgColor.a);
        _ = c.SDL_RenderClear(ren);

        const selected_col = game.selected_cell[0];
        const selected_row = game.selected_cell[1];
        const selected_box = if (all(game.selected_cell < u32_2{ game.extent, game.extent }))
            sudoku.box_index_from_cell(game, game.selected_cell)
        else
            game.extent;

        for (game.board, 0..) |cell, flat_index| {
            const cell_coord = sudoku.flat_index_to_2d(game.extent, flat_index);
            const box_coord = deprecated_box_coord_from_cell(game, cell_coord);

            const cell_rect = c.SDL_Rect{
                .x = @intCast(cell_coord[0] * SpriteScreenExtent),
                .y = @intCast(cell_coord[1] * SpriteScreenExtent),
                .w = SpriteScreenExtent,
                .h = SpriteScreenExtent,
            };

            // Draw box background
            if (((box_coord[0] & 1) ^ (box_coord[1] & 1)) != 0) {
                _ = c.SDL_SetRenderDrawColor(ren, BoxBgColor.r, BoxBgColor.g, BoxBgColor.b, BoxBgColor.a);
                _ = c.SDL_RenderFillRect(ren, &cell_rect);
            }

            // Draw highlighted cell
            if (all(game.selected_cell == cell_coord)) {
                _ = c.SDL_SetRenderDrawColor(ren, HighlightColor.r, HighlightColor.g, HighlightColor.b, HighlightColor.a);
                _ = c.SDL_RenderFillRect(ren, &cell_rect);
            } else {
                const box_index = game.box_indices[flat_index];

                if (cell_coord[0] == selected_col or cell_coord[1] == selected_row or box_index == selected_box) {
                    _ = c.SDL_SetRenderDrawColor(ren, HighlightRegionColor.r, HighlightRegionColor.g, HighlightRegionColor.b, HighlightRegionColor.a);
                    _ = c.SDL_RenderFillRect(ren, &cell_rect);
                }

                if (cell.number != UnsetNumber) {
                    if (highlight_mask & sudoku.mask_for_number(@intCast(cell.number)) != 0) {
                        _ = c.SDL_SetRenderDrawColor(ren, SameNumberHighlightColor.r, SameNumberHighlightColor.g, SameNumberHighlightColor.b, SameNumberHighlightColor.a);
                        _ = c.SDL_RenderFillRect(ren, &cell_rect);
                    }
                }
            }

            // Draw placed numbers
            if (cell.number != UnsetNumber) {
                var glyph_rect = std.mem.zeroes(c.SDL_Rect);

                if (c.TTF_SizeText(font, NumbersString[cell.number], &glyph_rect.w, &glyph_rect.h) != 0) {
                    c.SDL_Log("TTF error: %s", c.TTF_GetError());
                    return error.SDLInitializationFailed;
                }

                var glyph_out_rect = glyph_rect;
                glyph_out_rect.x += cell_rect.x + @divTrunc((cell_rect.w - glyph_rect.w), 2);
                glyph_out_rect.y += cell_rect.y + @divTrunc((cell_rect.h - glyph_rect.h), 2);

                _ = c.SDL_RenderCopy(ren, text_textures[cell.number], &glyph_rect, &glyph_out_rect);
            }

            // Draw candidates
            if (cell.number == UnsetNumber) {
                for (0..game.extent) |number_usize| {
                    const number: u4 = @intCast(number_usize);
                    if (((cell.hint_mask >> number) & 1) != 0) {
                        var candidate_rect = cell_rect;
                        candidate_rect.x += @intCast(@rem(number, candidate_layout[0]) * SpriteScreenExtent / candidate_layout[0]);
                        candidate_rect.y += @intCast(@divTrunc(number, candidate_layout[0]) * SpriteScreenExtent / candidate_layout[1]);
                        candidate_rect.w = @divTrunc(cell_rect.w, @as(c_int, @intCast(candidate_layout[0])));
                        candidate_rect.h = @divTrunc(cell_rect.h, @as(c_int, @intCast(candidate_layout[1])));

                        if (highlight_mask & sudoku.mask_for_number(number) != 0) {
                            _ = c.SDL_SetRenderDrawColor(ren, SameNumberHighlightColor.r, SameNumberHighlightColor.g, SameNumberHighlightColor.b, SameNumberHighlightColor.a);
                            _ = c.SDL_RenderFillRect(ren, &candidate_rect);
                        }

                        var glyph_rect = std.mem.zeroes(c.SDL_Rect);

                        if (c.TTF_SizeText(font_small, NumbersString[number], &glyph_rect.w, &glyph_rect.h) != 0) {
                            c.SDL_Log("TTF error: %s", c.TTF_GetError());
                            return error.SDLInitializationFailed;
                        }

                        var glyph_out_rect = glyph_rect;
                        glyph_out_rect.x += candidate_rect.x + @divTrunc((candidate_rect.w - glyph_rect.w), 2);
                        glyph_out_rect.y += candidate_rect.y + @divTrunc((candidate_rect.h - glyph_rect.h), 2);

                        _ = c.SDL_RenderCopy(ren, text_small_textures[number], &glyph_rect, &glyph_out_rect);
                    }
                }
            }
        }

        _ = c.SDL_SetRenderDrawColor(ren, TextColor.r, TextColor.g, TextColor.b, TextColor.a);

        // Draw thin grid
        for (0..game.extent + 1) |index| {
            const horizontal_rect = c.SDL_Rect{
                .x = @intCast(index * SpriteScreenExtent),
                .y = 0,
                .w = 1,
                .h = @intCast(game.extent * SpriteScreenExtent),
            };

            const vertical_rect = c.SDL_Rect{
                .x = 0,
                .y = @intCast(index * SpriteScreenExtent),
                .w = @intCast(game.extent * SpriteScreenExtent),
                .h = 1,
            };

            _ = c.SDL_RenderFillRect(ren, &vertical_rect);
            _ = c.SDL_RenderFillRect(ren, &horizontal_rect);
        }

        // Draw horizontal lines
        for (0..game.box_h + 1) |index| {
            const rect = c.SDL_Rect{
                .x = @as(c_int, @intCast(index * game.box_w * SpriteScreenExtent)) - 1,
                .y = 0,
                .w = 3,
                .h = @intCast(game.extent * SpriteScreenExtent),
            };

            _ = c.SDL_RenderFillRect(ren, &rect);
        }

        // Draw vertical lines
        for (0..game.box_w + 1) |index| {
            const rect = c.SDL_Rect{
                .x = 0,
                .y = @as(c_int, @intCast(index * game.box_h * SpriteScreenExtent)) - 1,
                .w = @intCast(game.extent * SpriteScreenExtent),
                .h = 3,
            };

            _ = c.SDL_RenderFillRect(ren, &rect);
        }

        // Present
        c.SDL_RenderPresent(ren);
    }

    for (text_textures, text_surfaces) |texture, surface| {
        c.SDL_DestroyTexture(texture);
        c.SDL_FreeSurface(surface);
    }

    for (text_small_textures, text_small_surfaces) |texture, surface| {
        c.SDL_DestroyTexture(texture);
        c.SDL_FreeSurface(surface);
    }
}
