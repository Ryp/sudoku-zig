const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const sudoku = @import("../sudoku/game.zig");
const GameState = sudoku.GameState;
const BoardState = sudoku.BoardState;
const UnsetNumber = sudoku.UnsetNumber;
const u32_2 = sudoku.u32_2;
const all = sudoku.all;

const NumbersString = [_][*:0]const u8{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "G" };
const SpriteScreenExtent = 80;
const FontSize: u32 = SpriteScreenExtent - 10;
const FontSizeSmall: u32 = SpriteScreenExtent / 4;

const BlackColor = c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
const BgColor = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
const BoxBgColor = c.SDL_Color{ .r = 220, .g = 220, .b = 220, .a = 255 };
const HighlightColor = c.SDL_Color{ .r = 250, .g = 243, .b = 57, .a = 255 };
const HighlightRegionColor = c.SDL_Color{ .r = 160, .g = 208, .b = 232, .a = 80 };
const SameNumberHighlightColor = c.SDL_Color{ .r = 250, .g = 57, .b = 243, .a = 255 };
const TextColor = BlackColor;
const GridColor = BlackColor;

const JigsawRegionSaturation = 0.4;
const JigsawRegionValue = 1.0;

pub fn execute_main_loop(allocator: std.mem.Allocator, game: *GameState) !void {
    const extent = game.board.extent;

    var box_region_colors_full: [sudoku.MaxSudokuExtent]c.SDL_Color = undefined;
    var box_region_colors = box_region_colors_full[0..extent];

    fill_box_regions_colors(game.board.game_type, box_region_colors);

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

    const window_width = extent * SpriteScreenExtent;
    const window_height = extent * SpriteScreenExtent;

    const window = c.SDL_CreateWindow("Sudoku", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @intCast(window_width), @intCast(window_height), c.SDL_WINDOW_SHOWN) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    if (c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1") == c.SDL_FALSE) {
        c.SDL_Log("Unable to set hint: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    var text_surfaces = try allocator.alloc(*c.SDL_Surface, extent);
    defer allocator.free(text_surfaces);

    var text_textures = try allocator.alloc(*c.SDL_Texture, extent);
    defer allocator.free(text_textures);

    const numbers_string = NumbersString[0..extent];

    for (text_surfaces, text_textures, numbers_string) |*surface, *texture, number_string| {
        surface.* = c.TTF_RenderText_LCD(font, number_string, TextColor, BgColor);
        texture.* = c.SDL_CreateTextureFromSurface(renderer, surface.*) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        _ = c.SDL_SetTextureBlendMode(texture.*, c.SDL_BLENDMODE_MUL);
    }

    var text_small_surfaces = try allocator.alloc(*c.SDL_Surface, extent);
    defer allocator.free(text_small_surfaces);

    var text_small_textures = try allocator.alloc(*c.SDL_Texture, extent);
    defer allocator.free(text_small_textures);

    for (text_small_surfaces, text_small_textures, numbers_string) |*surface, *texture, number_string| {
        surface.* = c.TTF_RenderText_LCD(font_small, number_string, TextColor, BgColor);
        texture.* = c.SDL_CreateTextureFromSurface(renderer, surface.*) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        _ = c.SDL_SetTextureBlendMode(texture.*, c.SDL_BLENDMODE_MUL);
    }

    const title_string = try std.fmt.allocPrintZ(allocator, "Sudoku", .{});
    defer allocator.free(title_string);

    c.SDL_SetWindowTitle(window, title_string.ptr);

    const candidate_layout = get_candidate_layout(extent);
    var candidate_local_rects_full: [sudoku.MaxSudokuExtent]c.SDL_Rect = undefined;
    var candidate_local_rects = candidate_local_rects_full[0..extent];

    for (candidate_local_rects, 0..) |*candidate_local_rect, number| {
        candidate_local_rect.* = .{
            .x = @intCast(@rem(number, candidate_layout[0]) * SpriteScreenExtent / candidate_layout[0]),
            .y = @intCast(@divTrunc(number, candidate_layout[0]) * SpriteScreenExtent / candidate_layout[1]),
            .w = @divTrunc(SpriteScreenExtent, @as(c_int, @intCast(candidate_layout[0]))),
            .h = @divTrunc(SpriteScreenExtent, @as(c_int, @intCast(candidate_layout[1]))),
        };
    }

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
                            sudoku.player_clear_cell(game);
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
                                sudoku.player_clear_candidates(game);
                            } else if (is_any_ctrl_pressed) {
                                sudoku.player_fill_candidates_all(game);
                            } else {
                                sudoku.player_fill_candidates(game);
                            }
                        },
                        c.SDLK_LEFT => {
                            sudoku.player_move_selection(game, -1, 0);
                        },
                        c.SDLK_RIGHT => {
                            sudoku.player_move_selection(game, 1, 0);
                        },
                        c.SDLK_UP => {
                            sudoku.player_move_selection(game, 0, -1);
                        },
                        c.SDLK_DOWN => {
                            sudoku.player_move_selection(game, 0, 1);
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
        for (game.selected_cells) |selected_cell_index| {
            const cell_number = game.board.numbers[selected_cell_index];

            if (cell_number != UnsetNumber) {
                highlight_mask |= sudoku.mask_for_number(@intCast(cell_number));
            }
        }

        // Render game
        _ = c.SDL_SetRenderDrawColor(renderer, BgColor.r, BgColor.g, BgColor.b, BgColor.a);
        _ = c.SDL_RenderClear(renderer);

        for (game.board.numbers, game.candidate_masks, 0..) |cell_number, cell_candidate_mask, cell_index| {
            const box_index = game.board.box_indices[cell_index];
            const box_region_color = box_region_colors[box_index];
            const cell_coord = sudoku.cell_coord_from_index(extent, cell_index);

            const cell_rect = c.SDL_Rect{
                .x = @intCast(cell_coord[0] * SpriteScreenExtent),
                .y = @intCast(cell_coord[1] * SpriteScreenExtent),
                .w = SpriteScreenExtent,
                .h = SpriteScreenExtent,
            };

            // Draw box background
            _ = c.SDL_SetRenderDrawColor(renderer, box_region_color.r, box_region_color.g, box_region_color.b, box_region_color.a);
            _ = c.SDL_RenderFillRect(renderer, &cell_rect);

            // Draw highlighted cell
            if (game.selected_cells.len > 0) {
                const selected_cell_index = game.selected_cells[0];
                const selected_coord = sudoku.cell_coord_from_index(extent, selected_cell_index);
                const selected_col = selected_coord[0];
                const selected_row = selected_coord[1];
                const selected_box = game.board.box_indices[selected_cell_index];

                if (selected_cell_index == cell_index) {
                    _ = c.SDL_SetRenderDrawColor(renderer, HighlightColor.r, HighlightColor.g, HighlightColor.b, HighlightColor.a);
                    _ = c.SDL_RenderFillRect(renderer, &cell_rect);
                } else {
                    if (cell_coord[0] == selected_col or cell_coord[1] == selected_row or box_index == selected_box) {
                        _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);
                        _ = c.SDL_SetRenderDrawColor(renderer, HighlightRegionColor.r, HighlightRegionColor.g, HighlightRegionColor.b, HighlightRegionColor.a);
                        _ = c.SDL_RenderFillRect(renderer, &cell_rect);
                        _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_NONE);
                    }

                    if (cell_number != UnsetNumber) {
                        if (highlight_mask & sudoku.mask_for_number(@intCast(cell_number)) != 0) {
                            _ = c.SDL_SetRenderDrawColor(renderer, SameNumberHighlightColor.r, SameNumberHighlightColor.g, SameNumberHighlightColor.b, SameNumberHighlightColor.a);
                            _ = c.SDL_RenderFillRect(renderer, &cell_rect);
                        }
                    }
                }
            }

            // Draw placed numbers
            if (cell_number != UnsetNumber) {
                var glyph_rect = std.mem.zeroes(c.SDL_Rect);

                if (c.TTF_SizeText(font, NumbersString[cell_number], &glyph_rect.w, &glyph_rect.h) != 0) {
                    c.SDL_Log("TTF error: %s", c.TTF_GetError());
                    return error.SDLInitializationFailed;
                }

                var glyph_out_rect = glyph_rect;
                glyph_out_rect.x += cell_rect.x + @divTrunc((cell_rect.w - glyph_rect.w), 2);
                glyph_out_rect.y += cell_rect.y + @divTrunc((cell_rect.h - glyph_rect.h), 2);

                _ = c.SDL_RenderCopy(renderer, text_textures[cell_number], &glyph_rect, &glyph_out_rect);
            }

            // Draw candidates
            for (candidate_local_rects, 0..) |candidate_local_rect, number_usize| {
                const number: u4 = @intCast(number_usize);
                if (((cell_candidate_mask >> number) & 1) != 0) {
                    var candidate_rect = candidate_local_rect;
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    if (highlight_mask & sudoku.mask_for_number(number) != 0) {
                        _ = c.SDL_SetRenderDrawColor(renderer, SameNumberHighlightColor.r, SameNumberHighlightColor.g, SameNumberHighlightColor.b, SameNumberHighlightColor.a);
                        _ = c.SDL_RenderFillRect(renderer, &candidate_rect);
                    }

                    var glyph_rect = std.mem.zeroes(c.SDL_Rect);

                    if (c.TTF_SizeText(font_small, NumbersString[number], &glyph_rect.w, &glyph_rect.h) != 0) {
                        c.SDL_Log("TTF error: %s", c.TTF_GetError());
                        return error.SDLInitializationFailed;
                    }

                    const centered_glyph_rect = center_rect_inside_rect(glyph_rect, candidate_rect);

                    _ = c.SDL_RenderCopy(renderer, text_small_textures[number], &glyph_rect, &centered_glyph_rect);
                }
            }
        }

        draw_solver_event_overlay(renderer, candidate_local_rects, game.board, game.last_solver_event);

        draw_sudoku_grid(renderer, game.board);

        // Present
        c.SDL_RenderPresent(renderer);
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

fn input_number(game: *GameState, candidate_mode: bool, number: u4) void {
    if (candidate_mode) {
        sudoku.player_toggle_guess(game, number);
    } else {
        sudoku.player_input_number(game, number);
    }
}

fn fill_box_regions_colors(game_type: sudoku.GameType, box_region_colors: []c.SDL_Color) void {
    switch (game_type) {
        .regular => |regular| {
            // Draw a checkerboard pattern
            for (box_region_colors, 0..) |*box_region_color, box_index| {
                const box_index_x = box_index % regular.box_h;
                const box_index_y = box_index / regular.box_h;

                if (((box_index_x & 1) ^ (box_index_y & 1)) != 0) {
                    box_region_color.* = BoxBgColor;
                } else {
                    box_region_color.* = BgColor;
                }
            }
        },
        .jigsaw => {
            // Get a unique color for each region
            for (box_region_colors, 0..) |*box_region_color, box_index| {
                const hue = @as(f32, @floatFromInt(box_index)) / @as(f32, @floatFromInt(box_region_colors.len));
                box_region_color.* = hsv_to_sdl_color(hue, JigsawRegionSaturation, JigsawRegionValue);
            }
        },
    }
}

fn draw_solver_event_overlay(renderer: *c.SDL_Renderer, candidate_local_rects: []c.SDL_Rect, board: BoardState, solver_event: sudoku.SolverEvent) void {
    _ = renderer;
    _ = candidate_local_rects;
    _ = board;

    switch (solver_event) {
        .naked_single => |naked_single| {
            _ = naked_single;
        },
        .hidden_single => |hidden_single| {
            _ = hidden_single;
        },
        .hidden_pair => |hidden_pair| {
            _ = hidden_pair;
        },
        .pointing_line => |pointing_line| {
            _ = pointing_line;
        },
        .nothing_found => |nothing_found| {
            _ = nothing_found;
        },
    }
}

fn draw_sudoku_grid(renderer: *c.SDL_Renderer, board: BoardState) void {
    _ = c.SDL_SetRenderDrawColor(renderer, GridColor.r, GridColor.g, GridColor.b, GridColor.a);

    for (0..board.numbers.len) |cell_index| {
        const box_index = board.box_indices[cell_index];
        const cell_coord = sudoku.cell_coord_from_index(board.extent, cell_index);

        const cell_rect = c.SDL_Rect{
            .x = @intCast(cell_coord[0] * SpriteScreenExtent),
            .y = @intCast(cell_coord[1] * SpriteScreenExtent),
            .w = SpriteScreenExtent,
            .h = SpriteScreenExtent,
        };

        var thick_vertical = true;

        if (cell_coord[0] + 1 < board.extent) {
            const neighbor_cell_index = sudoku.cell_index_from_coord(board.extent, cell_coord + u32_2{ 1, 0 });
            const neighbor_box_index = board.box_indices[neighbor_cell_index];
            thick_vertical = box_index != neighbor_box_index;
        }

        var thick_horizontal = true;

        if (cell_coord[1] + 1 < board.extent) {
            const neighbor_cell_index = sudoku.cell_index_from_coord(board.extent, cell_coord + u32_2{ 0, 1 });
            const neighbor_box_index = board.box_indices[neighbor_cell_index];
            thick_horizontal = box_index != neighbor_box_index;
        }

        if (thick_vertical) {
            const rect = c.SDL_Rect{
                .x = cell_rect.w * @as(c_int, @intCast(cell_coord[0] + 1)) - 2,
                .y = cell_rect.h * @as(c_int, @intCast(cell_coord[1])) - 2,
                .w = 5,
                .h = cell_rect.h + 5,
            };

            _ = c.SDL_RenderFillRect(renderer, &rect);
        }

        if (thick_horizontal) {
            const rect = c.SDL_Rect{
                .x = cell_rect.w * @as(c_int, @intCast(cell_coord[0])) - 2,
                .y = cell_rect.h * @as(c_int, @intCast(cell_coord[1] + 1)) - 2,
                .w = cell_rect.w + 5,
                .h = 5,
            };

            _ = c.SDL_RenderFillRect(renderer, &rect);
        }
    }

    // Draw thin grid
    for (0..board.extent + 1) |index| {
        const horizontal_rect = c.SDL_Rect{
            .x = @intCast(index * SpriteScreenExtent),
            .y = 0,
            .w = 1,
            .h = @intCast(board.extent * SpriteScreenExtent),
        };

        const vertical_rect = c.SDL_Rect{
            .x = 0,
            .y = @intCast(index * SpriteScreenExtent),
            .w = @intCast(board.extent * SpriteScreenExtent),
            .h = 1,
        };

        _ = c.SDL_RenderFillRect(renderer, &vertical_rect);
        _ = c.SDL_RenderFillRect(renderer, &horizontal_rect);
    }
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

fn center_rect_inside_rect(rect: c.SDL_Rect, reference_rect: c.SDL_Rect) c.SDL_Rect {
    return .{
        .x = reference_rect.x + @divTrunc((reference_rect.w - rect.w), 2),
        .y = reference_rect.y + @divTrunc((reference_rect.h - rect.h), 2),
        .w = rect.w,
        .h = rect.h,
    };
}

// https://www.rapidtables.com/convert/color/hsv-to-rgb.html
fn hsv_to_sdl_color(hue: f32, saturation: f32, value: f32) c.SDL_Color {
    const c_f = value * saturation;
    const area_index = hue * 6.0;
    const area_index_i: u8 = @intFromFloat(area_index);
    const x_f = c_f * (1.0 - @fabs(@mod(area_index, 2.0) - 1.0));
    const m_f = value - c_f;
    const c_u8 = @min(255, @as(u8, @intFromFloat((c_f + m_f) * 255.0)));
    const x_u8 = @min(255, @as(u8, @intFromFloat((x_f + m_f) * 255.0)));
    const m_u8 = @min(255, @as(u8, @intFromFloat(m_f * 255.0)));

    return switch (area_index_i) {
        0 => c.SDL_Color{ .r = c_u8, .g = x_u8, .b = m_u8, .a = 255 },
        1 => c.SDL_Color{ .r = x_u8, .g = c_u8, .b = m_u8, .a = 255 },
        2 => c.SDL_Color{ .r = m_u8, .g = c_u8, .b = x_u8, .a = 255 },
        3 => c.SDL_Color{ .r = m_u8, .g = x_u8, .b = c_u8, .a = 255 },
        4 => c.SDL_Color{ .r = x_u8, .g = m_u8, .b = c_u8, .a = 255 },
        5 => c.SDL_Color{ .r = c_u8, .g = m_u8, .b = x_u8, .a = 255 },
        else => unreachable,
    };
}
