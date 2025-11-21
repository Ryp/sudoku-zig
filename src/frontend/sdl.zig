const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const TrueType = @import("TrueType.zig");

const sudoku = @import("../sudoku/game.zig");
const solver_logical = @import("../sudoku/solver_logical.zig");
const GameState = sudoku.GameState;
const BoardState = sudoku.BoardState;
const u32_2 = sudoku.u32_2;

const boards = @import("../sudoku/boards.zig");
const NumbersString = boards.NumbersString;

const ui_palette = @import("color_palette.zig");
const ColorRGBA8 = ui_palette.ColorRGBA8;

const CandidateBoxExtent = 27;
const CellExtent = 2 + 3 * CandidateBoxExtent;

const BlackColor = ui_palette.Lucky_Point;
const BgColor = ui_palette.Swan_White;
const BoxBgColor = ui_palette.Crocodile_Tooth;
const HighlightColor = ui_palette.Spiced_Butternut;
const HighlightRegionColor = ColorRGBA8{ .r = 160, .g = 208, .b = 232, .a = 80 };
const SameNumberHighlightColor = ui_palette.C64_Purple;
const SolverRed = ui_palette.Fluorescent_Red;
const SolverGreen = ui_palette.Celestial_Green;
const SolverOrange = ui_palette.Mandarin_Sorbet;
const SolverYellow = ui_palette.Spiced_Butternut;
const TextColor = BlackColor;
const GridColor = BlackColor;

const JigsawRegionSaturation = 0.32;
const JigsawRegionValue = 1.0;

const SdlContext = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    text_textures: []*c.SDL_Texture,
    text_aabbs: []c.SDL_FRect,
    small_text_textures: []*c.SDL_Texture,
    small_text_aabbs: []c.SDL_FRect,
};

fn create_sdl_context(allocator: std.mem.Allocator, extent: u32) !SdlContext {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    errdefer c.SDL_Quit();

    const window_width = extent * CellExtent;
    const window_height = extent * CellExtent;

    const window = c.SDL_CreateWindow("Sudoku", @intCast(window_width), @intCast(window_height), c.SDL_WINDOW_HIGH_PIXEL_DENSITY) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    errdefer c.SDL_DestroyWindow(window);

    const content_scale = c.SDL_GetDisplayContentScale(c.SDL_GetPrimaryDisplay());
    std.debug.print("SDL_GetDisplayContentScale: {}\n", .{content_scale});

    const scale = c.SDL_GetWindowDisplayScale(window);
    std.debug.print("SDL_GetWindowDisplayScale: {}\n", .{scale});

    const density = c.SDL_GetWindowPixelDensity(window);
    std.debug.print("SDL_GetWindowPixelDensity: {}\n", .{density});

    if (!c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) {
        c.SDL_Log("Unable to set hint: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const renderer = c.SDL_CreateRenderer(window, null) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    errdefer c.SDL_DestroyRenderer(renderer);

    const text_palette = c.SDL_CreatePalette(256) orelse {
        c.SDL_Log("Unable to create palette: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyPalette(text_palette);

    var palette_colors_full: [256]c.SDL_Color = undefined;
    for (&palette_colors_full, 0..) |*color, color_index| {
        const alpha: u8 = @as(u8, @intCast(color_index));
        color.* = c.SDL_Color{
            .r = @intCast((@as(u32, @intCast(TextColor.r)) * alpha) / 255),
            .g = @intCast((@as(u32, @intCast(TextColor.g)) * alpha) / 255),
            .b = @intCast((@as(u32, @intCast(TextColor.b)) * alpha) / 255),
            .a = alpha,
        };
    }
    _ = c.SDL_SetPaletteColors(text_palette, &palette_colors_full, 0, 256);

    const regular_ttf = try TrueType.load(@embedFile("font_regular"));
    const regular_ttf_scale = regular_ttf.scaleForPixelHeight(CellExtent);

    const regular_ttf_textures, const regular_ttf_aabbs = try create_font_textures_and_aabbs(allocator, regular_ttf, regular_ttf_scale, renderer, text_palette, extent);

    const small_ttf = try TrueType.load(@embedFile("font_small"));
    const small_ttf_scale = small_ttf.scaleForPixelHeight(CellExtent / 3);

    const small_ttf_textures, const small_ttf_aabbs = try create_font_textures_and_aabbs(allocator, small_ttf, small_ttf_scale, renderer, text_palette, extent);

    return .{
        .window = window,
        .renderer = renderer,
        .text_textures = regular_ttf_textures,
        .text_aabbs = regular_ttf_aabbs,
        .small_text_textures = small_ttf_textures,
        .small_text_aabbs = small_ttf_aabbs,
    };
}

fn destroy_sdl_context(allocator: std.mem.Allocator, sdl_context: SdlContext) void {
    // Regular text
    for (sdl_context.text_textures) |texture| {
        c.SDL_DestroyTexture(texture);
    }
    allocator.free(sdl_context.text_textures);
    allocator.free(sdl_context.text_aabbs);

    // Small text
    for (sdl_context.small_text_textures) |texture| {
        c.SDL_DestroyTexture(texture);
    }
    allocator.free(sdl_context.small_text_textures);
    allocator.free(sdl_context.small_text_aabbs);

    c.SDL_DestroyRenderer(sdl_context.renderer);
    c.SDL_DestroyWindow(sdl_context.window);
    c.SDL_Quit();
}

fn create_font_textures_and_aabbs(allocator: std.mem.Allocator, ttf: TrueType, scale: f32, sdl_renderer: *c.SDL_Renderer, palette: *c.SDL_Palette, sudoku_extent: u32) !struct { []*c.SDL_Texture, []c.SDL_FRect } {
    const textures = try allocator.alloc(*c.SDL_Texture, sudoku_extent);
    errdefer allocator.free(textures);

    const aabbs = try allocator.alloc(c.SDL_FRect, sudoku_extent);
    errdefer allocator.free(aabbs);

    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(allocator);

    var glyph_indices_full: [sudoku.MaxSudokuExtent]TrueType.GlyphIndex = undefined;
    const glyph_indices = glyph_indices_full[0..sudoku_extent];

    var numbers_string_iterator = std.unicode.Utf8View.initComptime(&NumbersString).iterator();

    var index: u32 = 0;
    while (numbers_string_iterator.nextCodepoint()) |codepoint| : (index += 1) {
        if (index >= sudoku_extent) {
            break;
        }

        if (ttf.codepointGlyphIndex(codepoint)) |glyph_index| {
            glyph_indices[index] = glyph_index;
        } else {
            return error.FontMissingGlyph;
        }
    }

    for (glyph_indices, 0..) |glyph_index, number| {
        buffer.clearRetainingCapacity();
        const dims = try ttf.glyphBitmap(allocator, &buffer, glyph_index, scale, scale);

        const surface = c.SDL_CreateSurfaceFrom(dims.width, dims.height, c.SDL_PIXELFORMAT_INDEX8, @ptrCast(buffer.items), dims.width) orelse {
            c.SDL_Log("Unable to surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        defer c.SDL_DestroySurface(surface);

        _ = c.SDL_SetSurfacePalette(surface, palette);

        aabbs[number] = .{
            .x = 0.0,
            .y = 0.0,
            .w = @floatFromInt(dims.width),
            .h = @floatFromInt(dims.height),
        };

        textures[number] = c.SDL_CreateTextureFromSurface(sdl_renderer, surface) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        errdefer c.SDL_DestroyTexture(textures[number]);

        _ = c.SDL_SetTextureBlendMode(textures[number], c.SDL_BLENDMODE_MUL);
    }

    return .{ textures, aabbs };
}

fn sdl_key_to_number(key_code: c.SDL_Keycode) u4 {
    return switch (key_code) {
        c.SDLK_1...c.SDLK_9 => @intCast(key_code - c.SDLK_1),
        c.SDLK_A => 9,
        c.SDLK_B => 10,
        c.SDLK_C => 11,
        c.SDLK_D => 12,
        c.SDLK_E => 13,
        c.SDLK_F => 14,
        c.SDLK_G => 15,
        else => unreachable,
    };
}

pub fn execute_main_loop(allocator: std.mem.Allocator, game: *GameState) !void {
    const extent = game.board.extent;

    var box_region_colors_full: [sudoku.MaxSudokuExtent]ColorRGBA8 = undefined;
    const box_region_colors = box_region_colors_full[0..extent];

    fill_box_regions_colors(game.board.game_type, box_region_colors);

    const sdl_context = try create_sdl_context(allocator, extent);

    const title_string = try allocator.alloc(u8, 1024);
    defer allocator.free(title_string);

    const candidate_layout = get_candidate_layout(extent);
    var candidate_local_rects_full: [sudoku.MaxSudokuExtent]c.SDL_FRect = undefined;
    const candidate_local_rects = candidate_local_rects_full[0..extent];

    for (candidate_local_rects, 0..) |*candidate_local_rect, number| {
        const x: c_int = @intCast(@rem(number, candidate_layout[0]) * CellExtent / candidate_layout[0]);
        const y: c_int = @intCast(@divTrunc(number, candidate_layout[0]) * CellExtent / candidate_layout[1]);
        const x2: c_int = @intCast((@rem(number, candidate_layout[0]) + 1) * CellExtent / candidate_layout[0]);
        const y2: c_int = @intCast((@divTrunc(number, candidate_layout[0]) + 1) * CellExtent / candidate_layout[1]);

        candidate_local_rect.* = .{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
            .w = @floatFromInt(x2 - x),
            .h = @floatFromInt(y2 - y),
        };
    }

    main_loop: while (true) {
        // Poll events
        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent)) {
            const mods = c.SDL_GetModState();
            const is_any_ctrl_pressed = (mods & c.SDL_KMOD_CTRL) != 0;
            const is_any_shift_pressed = (mods & c.SDL_KMOD_SHIFT) != 0;

            switch (sdlEvent.type) {
                c.SDL_EVENT_QUIT => {
                    break :main_loop;
                },
                // c.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED => {
                //     const scale = c.SDL_GetWindowDisplayScale(sdl_context.window);
                //     //c.SDL_SetWindowSize(sdl_context.window, (int)(640.0f * scale), (int)(480.0f * scale));
                //     std.debug.print("SDL_GetWindowDisplayScale returned: {}\n", .{scale});
                // },
                c.SDL_EVENT_MOUSE_BUTTON_UP => {
                    const x: u32 = @intFromFloat(sdlEvent.button.x / CellExtent);
                    const y: u32 = @intFromFloat(sdlEvent.button.y / CellExtent);
                    if (sdlEvent.button.button == c.SDL_BUTTON_LEFT) {
                        sudoku.apply_player_event(game, .{ .toggle_select = .{ .coord = .{ x, y } } });
                    }
                },
                c.SDL_EVENT_KEY_DOWN => {
                    const key_sym = sdlEvent.key.key;
                    switch (key_sym) {
                        c.SDLK_ESCAPE => {
                            break :main_loop;
                        },
                        else => switch (game.flow) {
                            .Normal => {
                                const player_event =
                                    switch (key_sym) {
                                        c.SDLK_LEFT => sudoku.PlayerAction{ .move_selection = .{ .x_offset = -1, .y_offset = 0 } },
                                        c.SDLK_RIGHT => sudoku.PlayerAction{ .move_selection = .{ .x_offset = 1, .y_offset = 0 } },
                                        c.SDLK_UP => sudoku.PlayerAction{ .move_selection = .{ .x_offset = 0, .y_offset = -1 } },
                                        c.SDLK_DOWN => sudoku.PlayerAction{ .move_selection = .{ .x_offset = 0, .y_offset = 1 } },
                                        c.SDLK_1...c.SDLK_9, c.SDLK_A, c.SDLK_B, c.SDLK_C, c.SDLK_D, c.SDLK_E, c.SDLK_F, c.SDLK_G => if (is_any_shift_pressed)
                                            sudoku.PlayerAction{ .toggle_candidate = .{ .number = sdl_key_to_number(key_sym) } }
                                        else
                                            sudoku.PlayerAction{ .set_number = .{ .number = sdl_key_to_number(key_sym) } },
                                        c.SDLK_DELETE, c.SDLK_0 => sudoku.PlayerAction{ .clear_selected_cell = undefined },
                                        c.SDLK_Z => if (is_any_ctrl_pressed)
                                            if (is_any_shift_pressed)
                                                sudoku.PlayerAction{ .redo = undefined }
                                            else
                                                sudoku.PlayerAction{ .undo = undefined }
                                        else
                                            null,
                                        c.SDLK_H => if (is_any_shift_pressed)
                                            sudoku.PlayerAction{ .clear_all_candidates = undefined }
                                        else if (is_any_ctrl_pressed)
                                            sudoku.PlayerAction{ .fill_all_candidates = undefined }
                                        else
                                            sudoku.PlayerAction{ .fill_candidates = undefined },
                                        c.SDLK_RETURN => if (is_any_shift_pressed)
                                            sudoku.PlayerAction{ .get_hint = undefined }
                                        else
                                            sudoku.PlayerAction{ .solve_board = undefined },
                                        else => null,
                                    };

                                if (player_event) |event| {
                                    sudoku.apply_player_event(game, event);
                                }
                            },
                            .WaitingForHintValidation => {
                                switch (key_sym) {
                                    c.SDLK_RETURN => {
                                        sudoku.apply_player_event(game, sudoku.PlayerAction{ .get_hint = undefined });
                                    },
                                    else => {},
                                }
                            },
                        },
                    }
                },
                else => {},
            }
        }

        var highlight_mask: u16 = 0;
        for (game.selected_cells) |selected_cell_index| {
            if (game.board.numbers[selected_cell_index]) |number| {
                highlight_mask |= game.board.mask_for_number(number);
            }
        }

        // Render game
        _ = SDL_SetRenderDrawColor2(sdl_context.renderer, BgColor);
        _ = c.SDL_RenderClear(sdl_context.renderer);

        for (game.board.numbers, 0..) |number_opt, cell_index| {
            const box_index = game.board.box_indices[cell_index];
            const box_region_color = box_region_colors[box_index];

            const cell_coord = game.board.cell_coord_from_index(cell_index);
            const cell_rect = cell_rectangle(cell_coord);

            // Draw box background
            _ = SDL_SetRenderDrawColor2(sdl_context.renderer, box_region_color);
            _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);

            // Draw highlighted cell
            if (game.selected_cells.len > 0) {
                const selected_cell_index = game.selected_cells[0];
                const selected_coord = game.board.cell_coord_from_index(selected_cell_index);
                const selected_col = selected_coord[0];
                const selected_row = selected_coord[1];
                const selected_box = game.board.box_indices[selected_cell_index];

                if (selected_cell_index == cell_index) {
                    _ = SDL_SetRenderDrawColor2(sdl_context.renderer, HighlightColor);
                    _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);
                } else {
                    if (cell_coord[0] == selected_col or cell_coord[1] == selected_row or box_index == selected_box) {
                        _ = SDL_SetRenderDrawColor2(sdl_context.renderer, HighlightRegionColor);
                        _ = c.SDL_SetRenderDrawBlendMode(sdl_context.renderer, c.SDL_BLENDMODE_BLEND);
                        _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);
                        _ = c.SDL_SetRenderDrawBlendMode(sdl_context.renderer, c.SDL_BLENDMODE_NONE);
                    }

                    if (number_opt) |number| {
                        if (highlight_mask & game.board.mask_for_number(number) != 0) {
                            _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SameNumberHighlightColor);
                            _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);
                        }
                    }
                }
            }
        }

        if (game.solver_event) |solver_event| {
            switch (solver_event) {
                .found_technique => |technique| {
                    draw_solver_technique_overlay(sdl_context, candidate_local_rects, game.board, technique);
                },
                .found_nothing => {}, // Do nothing
            }
        }

        if (game.validation_error) |validation_error| {
            draw_validation_error(sdl_context, candidate_local_rects, game.board, validation_error);
        }

        for (game.board.numbers, 0..) |number_opt, cell_index| {
            const cell_coord = game.board.cell_coord_from_index(cell_index);
            const cell_rect = cell_rectangle(cell_coord);

            // Draw placed numbers
            if (number_opt) |number| {
                const glyph_rect = sdl_context.text_aabbs[number];
                const centered_glyph_rect = center_rect_inside_rect(glyph_rect, cell_rect);

                _ = c.SDL_RenderTexture(sdl_context.renderer, sdl_context.text_textures[number], &glyph_rect, &centered_glyph_rect);
            }
        }

        for (game.candidate_masks, 0..) |cell_candidate_mask, cell_index| {
            const cell_coord = game.board.cell_coord_from_index(cell_index);
            const cell_rect = cell_rectangle(cell_coord);

            // Draw candidates
            for (candidate_local_rects, 0..) |candidate_local_rect, number_usize| {
                const number: u4 = @intCast(number_usize);
                if (((cell_candidate_mask >> number) & 1) != 0) {
                    var candidate_rect = candidate_local_rect;
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    if (highlight_mask & game.board.mask_for_number(number) != 0) {
                        _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SameNumberHighlightColor);
                        _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                    }

                    const glyph_rect = sdl_context.small_text_aabbs[number];
                    const centered_glyph_rect = center_rect_inside_rect(glyph_rect, candidate_rect);

                    _ = c.SDL_RenderTexture(sdl_context.renderer, sdl_context.small_text_textures[number], &glyph_rect, &centered_glyph_rect);
                }
            }
        }

        draw_sudoku_grid(sdl_context.renderer, game.board);

        set_window_title(sdl_context.window, game, title_string);

        _ = c.SDL_RenderPresent(sdl_context.renderer);
    }

    destroy_sdl_context(allocator, sdl_context);
}

fn fill_box_regions_colors(game_type: sudoku.GameType, box_region_colors: []ColorRGBA8) void {
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
                box_region_color.* = hsv_to_rgba8(hue, JigsawRegionSaturation, JigsawRegionValue);
            }
        },
    }
}

fn draw_solver_technique_overlay(sdl_context: SdlContext, candidate_local_rects: []c.SDL_FRect, board: BoardState, technique: solver_logical.Technique) void {
    switch (technique) {
        .naked_single => |naked_single| {
            const cell_coord = board.cell_coord_from_index(naked_single.cell_index);
            const cell_rect = cell_rectangle(cell_coord);

            _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverOrange);
            _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);

            var candidate_rect = candidate_local_rects[naked_single.number];
            candidate_rect.x += cell_rect.x;
            candidate_rect.y += cell_rect.y;

            _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverGreen);
            _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
        },
        .naked_pair => |naked_pair| {
            for (naked_pair.region, 0..) |cell_index, region_cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = cell_rectangle(cell_coord);

                // Highlight region that was considered
                _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverOrange);
                _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);

                // Draw naked pair
                if (cell_index == naked_pair.cell_index_u or cell_index == naked_pair.cell_index_v) {
                    inline for (.{ naked_pair.number_a, naked_pair.number_b }) |number| {
                        var candidate_rect = candidate_local_rects[number];

                        candidate_rect.x += cell_rect.x;
                        candidate_rect.y += cell_rect.y;
                        _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverGreen);
                        _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                    }
                }

                const region_mask = @as(u16, 1) << @as(u4, @intCast(region_cell_index));

                // Draw candidates to remove
                if (region_mask & naked_pair.deletion_mask_b != 0) {
                    var candidate_rect = candidate_local_rects[naked_pair.number_b];

                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverRed);
                    _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                }

                if (region_mask & naked_pair.deletion_mask_a != 0) {
                    var candidate_rect = candidate_local_rects[naked_pair.number_a];

                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverRed);
                    _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                }
            }
        },
        .hidden_single => |hidden_single| {
            // Highlight region that was considered
            for (hidden_single.region) |cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = cell_rectangle(cell_coord);

                _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverOrange);
                _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);
            }

            // Highlight the candidates we removed and the single that was considered
            const cell_coord = board.cell_coord_from_index(hidden_single.cell_index);
            const cell_rect = cell_rectangle(cell_coord);

            // Draw candidates
            for (0..board.extent) |number_usize| {
                const number: u4 = @intCast(number_usize);
                const number_mask = board.mask_for_number(number);

                const is_deleted = hidden_single.deletion_mask & number_mask != 0;
                const is_single = hidden_single.number == number;

                if (is_single or is_deleted) {
                    var candidate_rect = candidate_local_rects[number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    _ = SDL_SetRenderDrawColor2(sdl_context.renderer, if (is_single) SolverGreen else SolverRed);
                    _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                }
            }
        },
        .hidden_pair => |hidden_pair| {
            // Highlight region that was considered
            assert(hidden_pair.a.region.ptr == hidden_pair.b.region.ptr);
            for (hidden_pair.a.region) |cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = cell_rectangle(cell_coord);

                _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverOrange);
                _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);
            }

            inline for (.{ hidden_pair.a, hidden_pair.b }) |hidden_single| {
                // Highlight the candidates we removed and the single that was considered
                const cell_coord = board.cell_coord_from_index(hidden_single.cell_index);
                const cell_rect = cell_rectangle(cell_coord);

                // Draw candidates
                for (0..board.extent) |number_usize| {
                    const number: u4 = @intCast(number_usize);
                    const number_mask = board.mask_for_number(number);

                    const is_deleted = hidden_single.deletion_mask & number_mask != 0;
                    const is_single = hidden_pair.a.number == number or hidden_pair.b.number == number;

                    if (is_single or is_deleted) {
                        var candidate_rect = candidate_local_rects[number];
                        candidate_rect.x += cell_rect.x;
                        candidate_rect.y += cell_rect.y;

                        _ = SDL_SetRenderDrawColor2(sdl_context.renderer, if (is_single) SolverGreen else SolverRed);
                        _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                    }
                }
            }
        },
        .pointing_line => |pointing_line| {
            // Draw line
            for (pointing_line.line_region, 0..) |cell_index, line_region_cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = cell_rectangle(cell_coord);

                _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverOrange);
                _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);

                const region_index_mask = board.mask_for_number(@intCast(line_region_cell_index));

                if (pointing_line.line_region_deletion_mask & region_index_mask != 0) {
                    var candidate_rect = candidate_local_rects[pointing_line.number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverRed);
                    _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                }
            }

            // Draw box
            for (pointing_line.box_region, 0..) |cell_index, box_region_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = cell_rectangle(cell_coord);

                _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverYellow);
                _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);

                const region_index_mask = board.mask_for_number(@intCast(box_region_index));
                if (pointing_line.box_region_mask & region_index_mask != 0) {
                    var candidate_rect = candidate_local_rects[pointing_line.number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverGreen);
                    _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                }
            }
        },
        .box_line_reduction => |box_line_reduction| {
            // Draw box
            for (box_line_reduction.box_region, 0..) |cell_index, line_region_cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = cell_rectangle(cell_coord);

                _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverOrange);
                _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);

                const region_index_mask = board.mask_for_number(@intCast(line_region_cell_index));

                if (box_line_reduction.box_region_deletion_mask & region_index_mask != 0) {
                    var candidate_rect = candidate_local_rects[box_line_reduction.number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverRed);
                    _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                }
            }

            // Draw line
            for (box_line_reduction.line_region, 0..) |cell_index, box_region_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = cell_rectangle(cell_coord);

                _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverYellow);
                _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);

                const region_index_mask = board.mask_for_number(@intCast(box_region_index));
                if (box_line_reduction.line_region_mask & region_index_mask != 0) {
                    var candidate_rect = candidate_local_rects[box_line_reduction.number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverGreen);
                    _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
                }
            }
        },
    }
}

fn draw_validation_error(sdl_context: SdlContext, candidate_local_rects: []c.SDL_FRect, board: BoardState, validation_error: sudoku.ValidationError) void {
    for (validation_error.region) |cell_index| {
        const cell_coord = board.cell_coord_from_index(cell_index);
        const cell_rect = cell_rectangle(cell_coord);

        if (validation_error.reference_cell_index == cell_index or validation_error.invalid_cell_index == cell_index and !validation_error.is_candidate) {
            _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverRed);
        } else {
            _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverOrange);
        }
        _ = c.SDL_RenderFillRect(sdl_context.renderer, &cell_rect);

        if (validation_error.invalid_cell_index == cell_index and validation_error.is_candidate) {
            var candidate_rect = candidate_local_rects[validation_error.number];
            candidate_rect.x += cell_rect.x;
            candidate_rect.y += cell_rect.y;

            _ = SDL_SetRenderDrawColor2(sdl_context.renderer, SolverRed);
            _ = c.SDL_RenderFillRect(sdl_context.renderer, &candidate_rect);
        }
    }
}

fn draw_sudoku_grid(renderer: *c.SDL_Renderer, board: BoardState) void {
    _ = SDL_SetRenderDrawColor2(renderer, GridColor);

    for (0..board.numbers.len) |cell_index| {
        const box_index = board.box_indices[cell_index];
        const cell_coord = board.cell_coord_from_index(cell_index);
        const cell_rect = cell_rectangle(cell_coord);

        var thick_vertical = true;

        if (cell_coord[0] + 1 < board.extent) {
            const neighbor_cell_index = board.cell_index_from_coord(cell_coord + u32_2{ 1, 0 });
            const neighbor_box_index = board.box_indices[neighbor_cell_index];
            thick_vertical = box_index != neighbor_box_index;
        }

        var thick_horizontal = true;

        if (cell_coord[1] + 1 < board.extent) {
            const neighbor_cell_index = board.cell_index_from_coord(cell_coord + u32_2{ 0, 1 });
            const neighbor_box_index = board.box_indices[neighbor_cell_index];
            thick_horizontal = box_index != neighbor_box_index;
        }

        if (thick_vertical) {
            const rect = c.SDL_FRect{
                .x = cell_rect.w * @as(f32, @floatFromInt(cell_coord[0] + 1)) - 2.0,
                .y = cell_rect.h * @as(f32, @floatFromInt(cell_coord[1])) - 2.0,
                .w = 5.0,
                .h = cell_rect.h + 5.0,
            };

            _ = c.SDL_RenderFillRect(renderer, &rect);
        }

        if (thick_horizontal) {
            const rect = c.SDL_FRect{
                .x = cell_rect.w * @as(f32, @floatFromInt(cell_coord[0])) - 2.0,
                .y = cell_rect.h * @as(f32, @floatFromInt(cell_coord[1] + 1)) - 2.0,
                .w = cell_rect.w + 5.0,
                .h = 5.0,
            };

            _ = c.SDL_RenderFillRect(renderer, &rect);
        }
    }

    // Draw thin grid
    for (0..board.extent + 1) |index| {
        const horizontal_rect = c.SDL_FRect{
            .x = @floatFromInt(index * CellExtent),
            .y = 0.0,
            .w = 1.0,
            .h = @floatFromInt(board.extent * CellExtent),
        };

        const vertical_rect = c.SDL_FRect{
            .x = 0.0,
            .y = @floatFromInt(index * CellExtent),
            .w = @floatFromInt(board.extent * CellExtent),
            .h = 1.0,
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

fn cell_rectangle(cell_coord: u32_2) c.SDL_FRect {
    return .{
        .x = @floatFromInt(cell_coord[0] * CellExtent + 1),
        .y = @floatFromInt(cell_coord[1] * CellExtent + 1),
        .w = CellExtent,
        .h = CellExtent,
    };
}

fn center_rect_inside_rect(rect: c.SDL_FRect, reference_rect: c.SDL_FRect) c.SDL_FRect {
    return .{
        .x = reference_rect.x + @divTrunc((reference_rect.w - rect.w), 2),
        .y = reference_rect.y + @divTrunc((reference_rect.h - rect.h), 2),
        .w = rect.w,
        .h = rect.h,
    };
}

// https://www.rapidtables.com/convert/color/hsv-to-rgb.html
fn hsv_to_rgba8(hue: f32, saturation: f32, value: f32) ColorRGBA8 {
    const c_f = value * saturation;
    const area_index = hue * 6.0;
    const area_index_i: u8 = @intFromFloat(area_index);
    const x_f = c_f * (1.0 - @abs(@mod(area_index, 2.0) - 1.0));
    const m_f = value - c_f;
    const c_u8 = @min(255, @as(u8, @intFromFloat((c_f + m_f) * 255.0)));
    const x_u8 = @min(255, @as(u8, @intFromFloat((x_f + m_f) * 255.0)));
    const m_u8 = @min(255, @as(u8, @intFromFloat(m_f * 255.0)));

    return switch (area_index_i) {
        0 => ColorRGBA8{ .r = c_u8, .g = x_u8, .b = m_u8, .a = 255 },
        1 => ColorRGBA8{ .r = x_u8, .g = c_u8, .b = m_u8, .a = 255 },
        2 => ColorRGBA8{ .r = m_u8, .g = c_u8, .b = x_u8, .a = 255 },
        3 => ColorRGBA8{ .r = m_u8, .g = x_u8, .b = c_u8, .a = 255 },
        4 => ColorRGBA8{ .r = x_u8, .g = m_u8, .b = c_u8, .a = 255 },
        5 => ColorRGBA8{ .r = c_u8, .g = m_u8, .b = x_u8, .a = 255 },
        else => unreachable,
    };
}

fn set_window_title(window: *c.SDL_Window, game: *GameState, title_string: []u8) void {
    const title = "Sudoku";

    if (game.solver_event) |solver_event| {
        _ = switch (solver_event) {
            .found_technique => |technique| switch (technique) {
                .naked_single => |naked_single| std.fmt.bufPrintZ(title_string, "{s} | hint: naked {c} single", .{ title, NumbersString[naked_single.number] }),
                .naked_pair => |naked_pair| std.fmt.bufPrintZ(title_string, "{s} | hint: naked {c} and {c} pair", .{ title, NumbersString[naked_pair.number_a], NumbersString[naked_pair.number_b] }),
                .hidden_single => |hidden_single| std.fmt.bufPrintZ(title_string, "{s} | hint: hidden {c} single", .{ title, NumbersString[hidden_single.number] }),
                .hidden_pair => |hidden_pair| std.fmt.bufPrintZ(title_string, "{s} | hint: hidden {c} and {c} pair", .{ title, NumbersString[hidden_pair.a.number], NumbersString[hidden_pair.b.number] }),
                .pointing_line => |pointing_line| std.fmt.bufPrintZ(title_string, "{s} | hint: pointing line of {c}", .{ title, NumbersString[pointing_line.number] }),
                .box_line_reduction => |box_line_reduction| std.fmt.bufPrintZ(title_string, "{s} | hint: box line reduction of {c}", .{ title, NumbersString[box_line_reduction.number] }),
            },
            .found_nothing => std.fmt.bufPrintZ(title_string, "{s} | hint: nothing found!", .{title}),
        } catch unreachable;
    } else {
        _ = std.fmt.bufPrintZ(title_string, "{s}", .{title}) catch unreachable;
    }

    _ = c.SDL_SetWindowTitle(window, title_string.ptr);
}

fn SDL_SetRenderDrawColor2(renderer: *c.SDL_Renderer, color: ColorRGBA8) bool {
    return c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
}
