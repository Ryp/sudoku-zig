const std = @import("std");

const rules = @import("../sudoku/rules.zig");
const game_state = @import("../sudoku/game.zig");
const board_generic = @import("../sudoku/board_generic.zig");
const solver_logical = @import("../sudoku/solver_logical.zig");
const grader = @import("../sudoku/grader.zig");
const validator = @import("../sudoku/validator.zig");
const known_boards = @import("../sudoku/known_boards.zig");

const common = @import("../sudoku/common.zig");
const u32_2 = common.u32_2;
const f32_2 = common.f32_2;

const ui_palette = @import("color_palette.zig");
const ColorRGBA8 = ui_palette.ColorRGBA8;

const BlackColor = ui_palette.Lucky_Point;
const BgColor = ui_palette.Swan_White;
const BoxBgColor = ui_palette.Crocodile_Tooth;
const HighlightColor = ui_palette.Spiced_Butternut;
const HighlightRegionColor = ColorRGBA8{ .r = 160, .g = 208, .b = 232, .a = 80 };
const SameNumberHighlightColor = ui_palette.Mandarin_Sorbet;
const SolverRed = ui_palette.Fluorescent_Red;
const SolverGreen = ui_palette.Celestial_Green;
const SolverOrange = HighlightColor;
const SolverYellow = ui_palette.Spiced_Butternut;
const TextColor = BlackColor;
const GridColor = BlackColor;
const InactiveTextColor = ColorRGBA8{ .r = 160, .g = 160, .b = 160, .a = 255 };

const JigsawRegionSaturation = 0.32;
const JigsawRegionValue = 1.0;

const CellExtentBasePx = 29;
const CellExtentBasePxMin = 10;
const CellExtentBasePxMax = 60;

const CellCandidateFillRatio = 1.0;

const TrueType = @import("TrueType.zig");

const psp = @import("pspsdk");

const UIState = struct {
    selected_number: u4 = 4,
    selected_mode: enum {
        Normal,
        Candidate,
    } = .Normal,
};

pub fn execute_main_loop(io: std.Io, allocator: std.mem.Allocator) !void {
    const board = known_boards.easy;
    const extent = comptime board.rules.type.extent();

    var game = try game_state.State(extent).init(io, allocator, board.rules, board.start_string);
    defer game.deinit(allocator);

    var ui_state: UIState = .{};

    game.apply_player_event(.{ .toggle_select = .{ .coord = .{ 0, 0 } } });
    game.apply_player_event(.{ .fill_candidates = undefined });

    psp.extra.utils.enableHBCB();
    psp.extra.debug.screenInit();

    // Controller
    _ = psp.sceCtrlSetSamplingCycle(0);
    _ = psp.sceCtrlSetSamplingMode(.analog);

    // FIXME does sceGeEdramSetAddrTranslation() interfere?
    const vram_size_bytes = psp.sceGeEdramGetSize();
    const vram_offset_bytes = psp.sceGeEdramGetAddr();
    const vram_slice = (@as([*]u8, @ptrCast(vram_offset_bytes))[0..vram_size_bytes]);
    var vram_fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(vram_slice);
    const vram_allocator = vram_fixed_buffer_allocator.allocator();

    const color_buffer_format: psp.GuPixelFormat = .Psm8888;
    const color_buffer_width = psp.extra.constants.SCREEN_WIDTH;
    const color_buffer_height = psp.extra.constants.SCREEN_HEIGHT;

    const color_buffer_pixel_size_bytes = psp.extra.vram.pixel_format_size_bits(color_buffer_format) / 8;
    const color_buffer_element_stride = try std.math.ceilPowerOfTwo(u24, color_buffer_width);

    // Normally the PSP only supports pow2 textures, but we can overlap those buffers in VRAM to save space
    const color_buffer_size_bytes = color_buffer_pixel_size_bytes * color_buffer_element_stride * color_buffer_height;

    const color_buffer0 = try vram_allocator.alignedAlloc(u8, .@"16", color_buffer_size_bytes);
    defer vram_allocator.free(color_buffer0);

    const color_buffer1 = try vram_allocator.alignedAlloc(u8, .@"16", color_buffer_size_bytes);
    defer vram_allocator.free(color_buffer1);

    const depth_buffer_format = u16;
    const depth_buffer_width = color_buffer_width;
    const depth_buffer_height = color_buffer_height;

    const depth_buffer_pixel_size_bytes = @sizeOf(depth_buffer_format);
    const depth_buffer_element_stride = try std.math.ceilPowerOfTwo(u24, depth_buffer_width);

    // Normally the PSP only supports pow2 textures, but we can overlap those buffers in VRAM to save space
    const depth_buffer_size_bytes = depth_buffer_pixel_size_bytes * depth_buffer_element_stride * depth_buffer_height;

    const depth_buffer = try vram_allocator.alignedAlloc(u8, .@"16", depth_buffer_size_bytes);
    defer vram_allocator.free(depth_buffer);

    psp.sceGuInit();
    psp.sceGuStart(.Direct, &display_list);
    psp.sceGuDrawBuffer(convert_gu_pixel_format_to_display(color_buffer_format), vram_buffer_to_relative_offset(color_buffer0), color_buffer_element_stride);
    psp.sceGuDispBuffer(color_buffer_width, color_buffer_height, vram_buffer_to_relative_offset(color_buffer1), color_buffer_element_stride);
    psp.sceGuDepthBuffer(vram_buffer_to_relative_offset(depth_buffer), depth_buffer_element_stride);

    const SCREEN_WIDTH = color_buffer_width;
    const SCREEN_HEIGHT = color_buffer_height;

    psp.sceGuOffset(2048 - (SCREEN_WIDTH / 2), 2048 - (SCREEN_HEIGHT / 2));
    psp.sceGuViewport(2048, 2048, SCREEN_WIDTH, SCREEN_HEIGHT);
    psp.sceGuDepthRange(65535, 0);
    psp.sceGuScissor(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);
    psp.sceGuEnable(.ScissorTest);
    psp.sceGuDepthFunc(.GreaterOrEqual);
    psp.sceGuShadeModel(.Smooth);
    psp.sceGuFrontFace(.Clockwise);
    psp.sceGuEnable(.CullFace);
    psp.sceGuDisable(.ClipPlanes);

    _ = psp.sceGuFinish();
    _ = psp.sceGuSync(.Finish, .wait);
    try psp.sceDisplayWaitVblankStart();
    _ = psp.sceGuDisplay(true);

    var button_held_prev: psp.c.types.PspCtrlButtons = undefined;

    var box_region_colors: [extent]ColorRGBA8 = undefined;
    fill_box_regions_colors(game.board.rules.type, &box_region_colors);

    var sdl_context = try PspContext(extent).init(allocator, vram_allocator);
    defer sdl_context.deinit(allocator, vram_allocator);

    grader.grade_and_print_summary(extent, game.board);

    while (true) {
        var button_held: psp.c.types.SceCtrlData = undefined;
        _ = try psp.sceCtrlReadBufferPositive((&button_held)[0..1]);

        const button_pressed: psp.c.types.PspCtrlButtons = @bitCast(@as(u32, @bitCast(button_held.buttons)) & ~@as(u32, @bitCast(button_held_prev)));

        if (button_pressed.down == 1) {
            game.apply_player_event(.{ .move_selection = .{ .x_offset = 0, .y_offset = 1 } });
        } else if (button_pressed.up == 1) {
            game.apply_player_event(.{ .move_selection = .{ .x_offset = 0, .y_offset = -1 } });
        }

        if (button_pressed.right == 1) {
            game.apply_player_event(.{ .move_selection = .{ .x_offset = 1, .y_offset = 0 } });
        } else if (button_pressed.left == 1) {
            game.apply_player_event(.{ .move_selection = .{ .x_offset = -1, .y_offset = 0 } });
        }

        if (button_pressed.r_trigger == 1) {
            ui_state.selected_mode = switch (ui_state.selected_mode) {
                .Normal => .Candidate,
                .Candidate => .Normal,
            };
        }

        if (button_pressed.cross == 1) {
            if (button_held.buttons.l_trigger == 1) {
                game.apply_player_event(.{ .clear_selected_cell = undefined });
            } else {
                switch (ui_state.selected_mode) {
                    .Normal => game.apply_player_event(.{ .set_number = .{ .number = ui_state.selected_number } }),
                    .Candidate => game.apply_player_event(.{ .toggle_candidate = .{ .number = ui_state.selected_number } }),
                }
            }
        } else if (button_pressed.square == 1) {
            if (button_held.buttons.l_trigger == 1) {
                game.apply_player_event(.{ .redo = undefined });
            } else {
                game.apply_player_event(.{ .undo = undefined });
            }
        } else if (button_held.buttons.circle == 1) {
            // Danzeff OSK-style digit selection
            const position_stick: f32_2 = .{ @as(f32, button_held.Lx) / 128.0 - 1.0, @as(f32, button_held.Ly) / 128.0 - 1.0 };
            const position_stick_length_sqr = @reduce(.Add, position_stick * position_stick);

            const Deadzone = 0.3;
            const DeadzoneSqr = Deadzone * Deadzone;

            if (position_stick_length_sqr < DeadzoneSqr) {
                ui_state.selected_number = 5;
            } else {
                const test_a_1_2 = cross(.{ -1.0, -2.0 }, position_stick) > 0.0;
                const test_b_3_6 = cross(.{ 2.0, -1.0 }, position_stick) > 0.0;
                const test_c_6_9 = cross(.{ 2.0, 1.0 }, position_stick) > 0.0;
                const test_d_2_3 = cross(.{ 1.0, -2.0 }, position_stick) > 0.0;

                if (test_a_1_2) {
                    if (test_b_3_6) {
                        ui_state.selected_number = if (test_c_6_9) 9 else 6;
                    } else {
                        ui_state.selected_number = if (test_d_2_3) 3 else 2;
                    }
                } else {
                    if (test_b_3_6) {
                        ui_state.selected_number = if (test_d_2_3) 8 else 7;
                    } else {
                        ui_state.selected_number = if (test_c_6_9) 4 else 1;
                    }
                }
            }
            ui_state.selected_number -= 1;
        }

        const highlight_mask = game.board.mask_for_number(ui_state.selected_number);

        psp.sceGuStart(.Direct, &display_list);

        psp.sceGuClearColor(@bitCast(Color24{ .r = GridColor.r, .g = GridColor.g, .b = GridColor.b }));
        psp.sceGuClearDepth(0);
        psp.sceGuClear(.{ .color = true, .depth = true });

        psp.sceGuDisable(.Blend);
        psp.sceGuDisable(.Texture2D);

        // Draw backgrounds
        for (game.board.numbers, game.candidate_masks, 0..) |number_opt, cell_candidate_mask, cell_index| {
            const box_index = game.board.regions.box_indices[cell_index];
            const box_region_color = box_region_colors[box_index];

            const cell_coord = game.board.cell_coord_from_index(cell_index);
            const cell_rect = sdl_context.cell_rectangle(cell_coord);

            psp_draw_colored_rect(cell_rect, box_region_color);

            // Draw highlighted cell
            if (game.selected_cells.len > 0) {
                const selected_cell_index = game.selected_cells[0];
                const selected_coord = game.board.cell_coord_from_index(selected_cell_index);
                const selected_col = selected_coord[0];
                const selected_row = selected_coord[1];
                const selected_box = game.board.regions.box_indices[selected_cell_index];

                if (selected_cell_index == cell_index) {
                    psp_draw_colored_rect(cell_rect, HighlightColor);
                } else {
                    if (cell_coord[0] == selected_col or cell_coord[1] == selected_row or box_index == selected_box) {
                        psp.sceGuEnable(.Blend);
                        psp.sceGuBlendFunc(.Add, .SrcAlpha, .OneMinusSrcAlpha, 0, 0);
                        psp_draw_colored_rect(cell_rect, HighlightRegionColor);
                        psp.sceGuDisable(.Blend);
                    }

                    if (number_opt) |number| {
                        if (highlight_mask & game.board.mask_for_number(number) != 0) {
                            psp_draw_colored_rect(cell_rect, SameNumberHighlightColor);
                        }
                    }
                }
            }

            // Draw highlighted candidates
            for (sdl_context.candidate_local_rects, 0..) |candidate_local_rect, number_usize| {
                const number: u4 = @intCast(number_usize);

                if (cell_candidate_mask & game.board.mask_for_number(number) != 0) {
                    var candidate_rect = candidate_local_rect;
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    if (highlight_mask & game.board.mask_for_number(number) != 0) {
                        psp_draw_colored_rect(candidate_rect, SameNumberHighlightColor);
                    }
                }
            }
        }

        if (game.solver_event) |solver_event| {
            switch (solver_event) {
                .found_technique => |technique| {
                    draw_solver_technique_overlay(extent, game.board, sdl_context, technique);
                },
                .found_nothing => {}, // Do nothing
            }
        }

        if (game.validation_error) |validation_error| {
            draw_validation_error(extent, game.board, sdl_context, validation_error);
        }

        draw_sudoku_box_regions(extent, game.board, sdl_context);

        {
            psp.sceGuEnable(.Blend);
            psp.sceGuEnable(.Texture2D);

            psp.sceGuTexFunc(.Blend, .Rgba);
            psp.sceGuTexEnvColor(rgba8_to_u24(TextColor));
            psp.sceGuBlendFunc(.Add, .SrcAlpha, .OneMinusSrcAlpha, 0, 0);
            psp.sceGuTexFilter(.Nearest, .Nearest);

            const clut = sdl_context.fonts.palette;

            psp.sceGuClutMode(clut.gu_pixel_format, 0, 0xff, 0);
            psp.sceGuClutLoad(clut.block_count, clut.vram_buffer.ptr);

            // Draw numbers
            for (game.board.numbers, game.candidate_masks, 0..) |number_opt, cell_candidate_mask, cell_index| {
                const cell_coord = game.board.cell_coord_from_index(cell_index);
                const cell_rect = sdl_context.cell_rectangle(cell_coord);

                if (number_opt) |number| {
                    const glyph_rect = sdl_context.fonts.regular_text_aabbs[number];
                    const centered_glyph_rect = center_rect_inside_rect(glyph_rect, cell_rect);

                    const texture = sdl_context.fonts.regular_text_textures[number];

                    psp.sceGuTexMode(texture.gu_pixel_format, 0, .Single, .Linear);
                    psp.sceGuTexImage(0, texture.width, texture.height, texture.element_stride, texture.vram_buffer.ptr);

                    psp_draw_textured_rect(centered_glyph_rect);
                } else {
                    // Draw candidate numbers
                    for (sdl_context.candidate_local_rects, 0..) |candidate_local_rect, number_usize| {
                        const number: u4 = @intCast(number_usize);
                        if (cell_candidate_mask & game.board.mask_for_number(number) != 0) {
                            var candidate_rect = candidate_local_rect;
                            candidate_rect.x += cell_rect.x;
                            candidate_rect.y += cell_rect.y;

                            const glyph_rect = sdl_context.fonts.small_text_aabbs[number];
                            const centered_glyph_rect = center_rect_inside_rect(glyph_rect, candidate_rect);

                            const texture = sdl_context.fonts.small_text_textures[number];

                            psp.sceGuTexMode(texture.gu_pixel_format, 0, .Single, .Linear);
                            psp.sceGuTexImage(0, texture.width, texture.height, texture.element_stride, texture.vram_buffer.ptr);

                            psp_draw_textured_rect(centered_glyph_rect);
                        }
                    }
                }
            }
        }

        draw_osk(extent, game.board, sdl_context, ui_state);

        _ = psp.sceGuFinish();
        _ = psp.sceGuSync(.Finish, .wait);
        psp.guSwapBuffers();

        _ = try psp.sceDisplayWaitVblankStart();

        button_held_prev = button_held.buttons;
    }
}

var display_list: [0x40000]u32 align(16) = [_]u32{0} ** 0x40000;

const Color32 = packed union {
    raw: u32,
    c8888: packed struct(u32) {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    },
};

const Color24 = packed struct(u24) {
    r: u8,
    g: u8,
    b: u8,
};

const Color16 = packed union {
    raw: u16,
    c5551: packed struct(u16) {
        r: u5,
        g: u5,
        b: u5,
        a: u1,
    },
    c5650: packed struct(u16) {
        r: u5,
        g: u6,
        b: u5,
    },
    c4444: packed struct(u16) {
        r: u4,
        g: u4,
        b: u4,
        a: u4,
    },
};

const SDL_FRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

fn PspContext(board_extent: comptime_int) type {
    return struct {
        const Self = @This();

        const ThinLineWidthBasePx = 1;
        const ThickLineExtraWidth = 1;
        const ThickLineWidthBasePx = 1 * ThickLineExtraWidth + ThinLineWidthBasePx;

        comptime BoardExtent: comptime_int = board_extent,

        candidate_local_rects: [board_extent]SDL_FRect,
        fonts: FontResources,

        base_cell_extent: u32, // Doesn't change with DPI
        thin_line_px: f32,
        thick_line_px: f32,
        cell_offset_px: f32,
        cell_extent_px: f32,
        cell_stride_px: f32,

        fn init(allocator: std.mem.Allocator, vram_allocator: std.mem.Allocator) !Self {
            var context = Self{
                .candidate_local_rects = undefined,
                .fonts = undefined,

                .base_cell_extent = CellExtentBasePx,
                .thin_line_px = undefined,
                .thick_line_px = undefined,
                .cell_offset_px = undefined,
                .cell_extent_px = undefined,
                .cell_stride_px = undefined,
            };

            context.update_content_metrics();

            context.fonts = try FontResources.create(allocator, vram_allocator, context.cell_extent_px, board_extent);
            errdefer context.fonts.destroy(allocator, vram_allocator);

            return context;
        }

        fn deinit(self: Self, allocator: std.mem.Allocator, vram_allocator: std.mem.Allocator) void {
            self.fonts.destroy(allocator, vram_allocator);
        }

        pub fn get_default_window_extent(base_cell_extent: u32) u32 {
            const base_extent = ThickLineWidthBasePx * 2 + base_cell_extent * board_extent + ThinLineWidthBasePx * (board_extent - 1);
            return @intFromFloat(@as(f32, @floatFromInt(base_extent)));
        }

        pub fn cell_rectangle(self: Self, cell_coord: u32_2) SDL_FRect {
            const rect = SDL_FRect{
                .x = self.cell_offset_px + @as(f32, @floatFromInt(cell_coord[0])) * self.cell_stride_px,
                .y = self.cell_offset_px + @as(f32, @floatFromInt(cell_coord[1])) * self.cell_stride_px,
                .w = self.cell_extent_px,
                .h = self.cell_extent_px,
            };

            return rect;
        }

        pub fn update_content_metrics(self: *Self) void {
            self.thin_line_px = @as(f32, @floatFromInt(ThinLineWidthBasePx));
            self.thick_line_px = @as(f32, @floatFromInt(ThickLineWidthBasePx));
            self.cell_offset_px = self.thick_line_px;
            self.cell_extent_px = @as(f32, @floatFromInt(self.base_cell_extent));
            self.cell_stride_px = self.cell_extent_px + self.thin_line_px;

            self.compute_candidate_local_rects();
        }

        pub fn resize_fonts(self: *Self, allocator: std.mem.Allocator, vram_allocator: std.mem.Allocator) !void {
            self.fonts.destroy(allocator, vram_allocator);
            self.fonts = try FontResources.create(allocator, vram_allocator, self.renderer, self.cell_extent_px, self.BoardExtent);
        }

        pub fn compute_candidate_local_rects(self: *Self) void {
            const candidate_layout = get_candidate_layout(self.BoardExtent);

            const fill_ratio = self.cell_extent_px * CellCandidateFillRatio;
            const offset = (self.cell_extent_px - fill_ratio) / 2.0;

            const candidate_box_extent = .{
                fill_ratio / @as(f32, @floatFromInt(candidate_layout[0])),
                fill_ratio / @as(f32, @floatFromInt(candidate_layout[1])),
            };

            for (&self.candidate_local_rects, 0..) |*candidate_local_rect, number| {
                candidate_local_rect.* = .{
                    .x = offset + candidate_box_extent[0] * @as(f32, @floatFromInt(@rem(number, candidate_layout[0]))),
                    .y = offset + candidate_box_extent[1] * @as(f32, @floatFromInt(@divTrunc(number, candidate_layout[0]))),
                    .w = candidate_box_extent[0],
                    .h = candidate_box_extent[1],
                };
            }
        }
    };
}

const FontResources = struct {
    const Self = @This();

    regular_text_textures: []Texture,
    regular_text_aabbs: []SDL_FRect,
    small_text_textures: []Texture,
    small_text_aabbs: []SDL_FRect,
    palette: ClutTexture,

    pub fn create(allocator: std.mem.Allocator, vram_allocator: std.mem.Allocator, cell_extent_px: f32, board_extent: u32) !Self {
        var palette: ClutTexture = undefined;
        {
            const vram_palette = try vram_allocator.alignedAlloc(Color32, .@"16", 256);
            errdefer vram_allocator.free(vram_palette);

            for (vram_palette, 0..) |*color, color_index| {
                // The PSP doesn't have premultiplied alpha support
                const alpha: u8 = @as(u8, @intCast(color_index));
                color.* = .{ .c8888 = .{
                    .r = 255,
                    .g = 255,
                    .b = 255,
                    .a = alpha,
                } };
            }

            palette = .{
                .vram_buffer = vram_palette,
                .block_count = @intCast(vram_palette.len / 8), // FIXME
                .gu_pixel_format = .Psm8888,
            };
        }

        const regular_ttf = try TrueType.load(@embedFile("font_regular"));
        const regular_ttf_scale = regular_ttf.scaleForPixelHeight(cell_extent_px + 3);

        const regular_ttf_textures, const regular_ttf_aabbs = try create_font_textures_and_aabbs(allocator, vram_allocator, regular_ttf, regular_ttf_scale, board_extent);

        const small_ttf = try TrueType.load(@embedFile("font_small"));
        const small_ttf_scale = small_ttf.scaleForPixelHeight((cell_extent_px + 3) / 3.0);

        const small_ttf_textures, const small_ttf_aabbs = try create_font_textures_and_aabbs(allocator, vram_allocator, small_ttf, small_ttf_scale, board_extent);

        // NOTE: hacking AABBs to always have the same height. This way when we align vertically they look even.
        // inline for (.{ regular_ttf_aabbs, small_ttf_aabbs }) |aabb_set| {
        //     var max_height: f32 = 0.0;
        //     for (aabb_set) |aabb| {
        //         max_height = @max(max_height, aabb.h);
        //     }

        //     for (aabb_set) |*aabb| {
        //         aabb.h = max_height;
        //     }
        // }

        return .{
            .regular_text_textures = regular_ttf_textures,
            .regular_text_aabbs = regular_ttf_aabbs,
            .small_text_textures = small_ttf_textures,
            .small_text_aabbs = small_ttf_aabbs,
            .palette = palette,
        };
    }

    pub fn destroy(self: Self, allocator: std.mem.Allocator, vram_allocator: std.mem.Allocator) void {
        for (self.regular_text_textures) |texture| {
            vram_allocator.free(texture.vram_buffer);
        }
        allocator.free(self.regular_text_textures);
        allocator.free(self.regular_text_aabbs);

        for (self.small_text_textures) |texture| {
            vram_allocator.free(texture.vram_buffer);
        }
        allocator.free(self.small_text_textures);
        allocator.free(self.small_text_aabbs);

        vram_allocator.free(self.palette.vram_buffer);
    }
};

fn create_font_textures_and_aabbs(allocator: std.mem.Allocator, vram_allocator: std.mem.Allocator, ttf: TrueType, scale: f32, board_extent: u32) !struct { []Texture, []SDL_FRect } {
    const textures = try allocator.alloc(Texture, board_extent);
    errdefer allocator.free(textures);

    const aabbs = try allocator.alloc(SDL_FRect, board_extent);
    errdefer allocator.free(aabbs);

    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(allocator);

    var glyph_indices_full: [board_generic.MaxExtent]TrueType.GlyphIndex = undefined;
    const glyph_indices = glyph_indices_full[0..board_extent];

    var numbers_string_iterator = std.unicode.Utf8View.initComptime(&board_generic.MaxNumbersString).iterator();

    var index: u32 = 0;
    while (numbers_string_iterator.nextCodepoint()) |codepoint| : (index += 1) {
        if (index >= board_extent) {
            break;
        }

        const glyph_index = ttf.codepointGlyphIndex(codepoint);
        if (glyph_index == .notdef) return error.FontMissingGlyph;
        glyph_indices[index] = glyph_index;
    }

    for (glyph_indices, 0..) |glyph_index, number| {
        buffer.clearRetainingCapacity();
        const dims = try ttf.glyphBitmap(allocator, &buffer, glyph_index, scale, scale);

        const gu_pixel_format = psp.GuPixelFormat.PsmT8;
        const gu_pixel_format_size_bits = psp.extra.vram.pixel_format_size_bits(gu_pixel_format);

        const tex_width = try std.math.ceilPowerOfTwo(u10, @intCast(dims.width));
        const tex_height = try std.math.ceilPowerOfTwo(u10, @intCast(dims.height));

        const vram_stride_bytes = std.mem.alignForward(usize, (@as(usize, tex_width) * gu_pixel_format_size_bits) / 8, 16);
        const vram_size_bytes = vram_stride_bytes * tex_height;

        const vram_buffer = try vram_allocator.alignedAlloc(u8, .@"16", vram_size_bytes);
        errdefer vram_allocator.free(vram_buffer);

        for (0..tex_height) |line_index| {
            const dest = vram_buffer[line_index * vram_stride_bytes ..];

            if (line_index < dims.height) {
                const src = buffer.items[line_index * dims.width ..][0..dims.width];
                @memcpy(dest[0..dims.width], src);

                @memset(dest[dims.width..tex_width], 0);
            } else {
                @memset(dest[0..tex_width], 0);
            }
        }

        textures[number] = .{
            .vram_buffer = vram_buffer,
            .width = tex_width,
            .height = tex_height,
            .element_stride = @intCast(vram_stride_bytes),
            .gu_pixel_format = gu_pixel_format,
        };

        aabbs[number] = .{
            .x = 0.0,
            .y = 0.0,
            .w = @floatFromInt(dims.width),
            .h = @floatFromInt(dims.height),
        };
    }

    return .{ textures, aabbs };
}

const ClutTexture = struct {
    vram_buffer: []align(16) Color32,
    block_count: u24,
    gu_pixel_format: psp.GuPixelFormat,
};

// FIXME: Be very careful with alignment. A small T4 texture will need to be padded to a 16 bytes stride
const Texture = struct {
    vram_buffer: []align(16) u8,
    width: u10,
    height: u10,
    element_stride: u16,

    gu_pixel_format: psp.GuPixelFormat,
};

fn fill_box_regions_colors(board_type: rules.Type, box_region_colors: []ColorRGBA8) void {
    switch (board_type) {
        .regular => |regular| {
            // Draw a checkerboard pattern
            for (box_region_colors, 0..) |*box_region_color, box_index| {
                const box_index_x = box_index % regular.box_extent[1];
                const box_index_y = box_index / regular.box_extent[1];

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

fn draw_osk(extent: comptime_int, board: board_generic.State(extent), sdl_context: PspContext(extent), ui_state: UIState) void {
    psp.sceGuDisable(.Blend);
    psp.sceGuDisable(.Texture2D);

    const osk_regions = [9]u32_2{
        .{ 0, 0 }, .{ 1, 0 }, .{ 2, 0 },
        .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 },
        .{ 0, 2 }, .{ 1, 2 }, .{ 2, 2 },
    };

    const osk_offset = sdl_context.cell_rectangle(u32_2{ 11, 3 });

    // Draw backgrounds
    for (osk_regions, 0..) |cell_coord, number| {
        var cell_rect = sdl_context.cell_rectangle(cell_coord);
        cell_rect.x += osk_offset.x;
        cell_rect.y += osk_offset.y;

        if (number == ui_state.selected_number) {
            psp_draw_colored_rect(cell_rect, HighlightColor);
        } else {
            psp_draw_colored_rect(cell_rect, BgColor);
        }
    }

    // Draw numbers
    psp.sceGuEnable(.Blend);
    psp.sceGuEnable(.Texture2D);

    psp.sceGuTexFunc(.Blend, .Rgba);
    psp.sceGuTexEnvColor(rgba8_to_u24(TextColor));
    psp.sceGuBlendFunc(.Add, .SrcAlpha, .OneMinusSrcAlpha, 0, 0);
    psp.sceGuTexFilter(.Nearest, .Nearest);

    var counts = std.mem.zeroes([extent]u32);

    for (board.numbers) |number_opt| {
        if (number_opt) |number| {
            counts[number] += 1;
        }
    }

    for (osk_regions, 0..) |cell_coord, number| {
        var cell_rect = sdl_context.cell_rectangle(cell_coord);
        cell_rect.x += osk_offset.x;
        cell_rect.y += osk_offset.y;

        if (counts[number] == extent) {
            psp.sceGuTexEnvColor(rgba8_to_u24(InactiveTextColor));
        } else {
            psp.sceGuTexEnvColor(rgba8_to_u24(TextColor));
        }

        switch (ui_state.selected_mode) {
            .Normal => {
                const glyph_rect = sdl_context.fonts.regular_text_aabbs[number];
                const centered_glyph_rect = center_rect_inside_rect(glyph_rect, cell_rect);

                const texture = sdl_context.fonts.regular_text_textures[number];

                psp.sceGuTexMode(texture.gu_pixel_format, 0, .Single, .Linear);
                psp.sceGuTexImage(0, texture.width, texture.height, texture.element_stride, texture.vram_buffer.ptr);

                psp_draw_textured_rect(centered_glyph_rect);
            },
            .Candidate => {
                const glyph_rect = sdl_context.fonts.small_text_aabbs[number];
                const centered_glyph_rect = center_rect_inside_rect(glyph_rect, cell_rect);

                const texture = sdl_context.fonts.small_text_textures[number];

                psp.sceGuTexMode(texture.gu_pixel_format, 0, .Single, .Linear);
                psp.sceGuTexImage(0, texture.width, texture.height, texture.element_stride, texture.vram_buffer.ptr);

                psp_draw_textured_rect(centered_glyph_rect);
            },
        }
    }
}

fn draw_solver_technique_overlay(extent: comptime_int, board: board_generic.State(extent), sdl_context: PspContext(extent), technique: solver_logical.Technique) void {
    switch (technique) {
        .naked_single => |naked_single| {
            const cell_coord = board.cell_coord_from_index(naked_single.cell_index);
            const cell_rect = sdl_context.cell_rectangle(cell_coord);

            psp_draw_colored_rect(cell_rect, SolverOrange);

            var candidate_rect = sdl_context.candidate_local_rects[naked_single.number];
            candidate_rect.x += cell_rect.x;
            candidate_rect.y += cell_rect.y;

            psp_draw_colored_rect(candidate_rect, SolverGreen);
        },
        .naked_pair => |naked_pair| {
            for (board.regions.get(naked_pair.region_index), 0..) |cell_index, region_cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = sdl_context.cell_rectangle(cell_coord);

                // Highlight region that was considered
                psp_draw_colored_rect(cell_rect, SolverOrange);

                // Draw naked pair
                if (cell_index == naked_pair.cell_index_u or cell_index == naked_pair.cell_index_v) {
                    inline for (.{ naked_pair.number_a, naked_pair.number_b }) |number| {
                        var candidate_rect = sdl_context.candidate_local_rects[number];

                        candidate_rect.x += cell_rect.x;
                        candidate_rect.y += cell_rect.y;
                        psp_draw_colored_rect(candidate_rect, SolverGreen);
                    }
                }

                const region_mask = board.mask_for_number(@intCast(region_cell_index));

                // Draw candidates to remove
                if (region_mask & naked_pair.deletion_mask_b != 0) {
                    var candidate_rect = sdl_context.candidate_local_rects[naked_pair.number_b];

                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;
                    psp_draw_colored_rect(candidate_rect, SolverRed);
                }

                if (region_mask & naked_pair.deletion_mask_a != 0) {
                    var candidate_rect = sdl_context.candidate_local_rects[naked_pair.number_a];

                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    psp_draw_colored_rect(candidate_rect, SolverRed);
                }
            }
        },
        .hidden_single => |hidden_single| {
            // Highlight region that was considered
            for (board.regions.get(hidden_single.region_index)) |cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = sdl_context.cell_rectangle(cell_coord);

                psp_draw_colored_rect(cell_rect, SolverOrange);
            }

            // Highlight the candidates we removed and the single that was considered
            const cell_coord = board.cell_coord_from_index(hidden_single.cell_index);
            const cell_rect = sdl_context.cell_rectangle(cell_coord);

            // Draw candidates
            for (0..board.Extent) |number_usize| {
                const number: u4 = @intCast(number_usize);
                const number_mask = board.mask_for_number(number);

                const is_deleted = hidden_single.deletion_mask & number_mask != 0;
                const is_single = hidden_single.number == number;

                if (is_single or is_deleted) {
                    var candidate_rect = sdl_context.candidate_local_rects[number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    psp_draw_colored_rect(candidate_rect, if (is_single) SolverGreen else SolverRed);
                }
            }
        },
        .hidden_pair => |hidden_pair| {
            // Highlight region that was considered
            for (board.regions.get(hidden_pair.a.region_index)) |cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = sdl_context.cell_rectangle(cell_coord);

                psp_draw_colored_rect(cell_rect, SolverOrange);
            }

            inline for (.{ hidden_pair.a, hidden_pair.b }) |hidden_single| {
                // Highlight the candidates we removed and the single that was considered
                const cell_coord = board.cell_coord_from_index(hidden_single.cell_index);
                const cell_rect = sdl_context.cell_rectangle(cell_coord);

                // Draw candidates
                for (0..board.Extent) |number_usize| {
                    const number: u4 = @intCast(number_usize);
                    const number_mask = board.mask_for_number(number);

                    const is_deleted = hidden_single.deletion_mask & number_mask != 0;
                    const is_single = hidden_pair.a.number == number or hidden_pair.b.number == number;

                    if (is_single or is_deleted) {
                        var candidate_rect = sdl_context.candidate_local_rects[number];
                        candidate_rect.x += cell_rect.x;
                        candidate_rect.y += cell_rect.y;

                        psp_draw_colored_rect(candidate_rect, if (is_single) SolverGreen else SolverRed);
                    }
                }
            }
        },
        .pointing_line => |pointing_line| {
            // Draw line
            for (board.regions.get(pointing_line.line_region_index), 0..) |cell_index, line_region_cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = sdl_context.cell_rectangle(cell_coord);

                psp_draw_colored_rect(cell_rect, SolverOrange);

                const region_index_mask = board.mask_for_number(@intCast(line_region_cell_index));

                if (pointing_line.line_region_deletion_mask & region_index_mask != 0) {
                    var candidate_rect = sdl_context.candidate_local_rects[pointing_line.number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    psp_draw_colored_rect(candidate_rect, SolverRed);
                }
            }

            // Draw box
            for (board.regions.get(pointing_line.box_region_index), 0..) |cell_index, box_region_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = sdl_context.cell_rectangle(cell_coord);

                psp_draw_colored_rect(cell_rect, SolverYellow);

                const region_index_mask = board.mask_for_number(@intCast(box_region_index));
                if (pointing_line.box_region_mask & region_index_mask != 0) {
                    var candidate_rect = sdl_context.candidate_local_rects[pointing_line.number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    psp_draw_colored_rect(candidate_rect, SolverGreen);
                }
            }
        },
        .box_line_reduction => |box_line_reduction| {
            // Draw box
            for (board.regions.get(box_line_reduction.box_region_index), 0..) |cell_index, line_region_cell_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = sdl_context.cell_rectangle(cell_coord);

                psp_draw_colored_rect(cell_rect, SolverOrange);

                const region_index_mask = board.mask_for_number(@intCast(line_region_cell_index));

                if (box_line_reduction.box_region_deletion_mask & region_index_mask != 0) {
                    var candidate_rect = sdl_context.candidate_local_rects[box_line_reduction.number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    psp_draw_colored_rect(candidate_rect, SolverRed);
                }
            }

            // Draw line
            for (board.regions.get(box_line_reduction.line_region_index), 0..) |cell_index, box_region_index| {
                const cell_coord = board.cell_coord_from_index(cell_index);
                const cell_rect = sdl_context.cell_rectangle(cell_coord);

                psp_draw_colored_rect(cell_rect, SolverYellow);

                const region_index_mask = board.mask_for_number(@intCast(box_region_index));
                if (box_line_reduction.line_region_mask & region_index_mask != 0) {
                    var candidate_rect = sdl_context.candidate_local_rects[box_line_reduction.number];
                    candidate_rect.x += cell_rect.x;
                    candidate_rect.y += cell_rect.y;

                    psp_draw_colored_rect(candidate_rect, SolverGreen);
                }
            }
        },
    }
}

fn draw_validation_error(extent: comptime_int, board: board_generic.State(extent), sdl_context: PspContext(extent), validation_error: validator.Error) void {
    // Highlight region that was considered if any
    if (validation_error.region_index_opt) |region_index| {
        const region = board.regions.get(region_index);
        for (region) |cell_index| {
            const cell_coord = board.cell_coord_from_index(cell_index);
            const cell_rect = sdl_context.cell_rectangle(cell_coord);

            psp_draw_colored_rect(cell_rect, SolverOrange);
        }
    }

    // Draw reference cell
    {
        const cell_coord = board.cell_coord_from_index(validation_error.reference_cell_index);
        const cell_rect = sdl_context.cell_rectangle(cell_coord);

        psp_draw_colored_rect(cell_rect, SolverRed);
    }

    // Draw invalid cell
    const cell_coord = board.cell_coord_from_index(validation_error.invalid_cell_index);
    const cell_rect = sdl_context.cell_rectangle(cell_coord);

    if (validation_error.is_candidate) {
        var candidate_rect = sdl_context.candidate_local_rects[validation_error.number];
        candidate_rect.x += cell_rect.x;
        candidate_rect.y += cell_rect.y;

        psp_draw_colored_rect(candidate_rect, SolverRed);
    } else {
        psp_draw_colored_rect(cell_rect, SolverRed);
    }
}

fn draw_sudoku_box_regions(extent: comptime_int, board: board_generic.State(extent), sdl_context: PspContext(extent)) void {
    const thickness_large_half_offset = (sdl_context.thick_line_px - sdl_context.thin_line_px) / 2.0;

    for (0..board.numbers.len) |cell_index| {
        const box_index = board.regions.box_indices[cell_index];
        const cell_coord = board.cell_coord_from_index(cell_index);

        var thick_vertical = true;

        if (cell_coord[0] + 1 < board.Extent) {
            const neighbor_cell_index = board.cell_index_from_coord(cell_coord + u32_2{ 1, 0 });
            const neighbor_box_index = board.regions.box_indices[neighbor_cell_index];
            thick_vertical = box_index != neighbor_box_index;
        } else {
            thick_vertical = false;
        }

        var thick_horizontal = true;

        if (cell_coord[1] + 1 < board.Extent) {
            const neighbor_cell_index = board.cell_index_from_coord(cell_coord + u32_2{ 0, 1 });
            const neighbor_box_index = board.regions.box_indices[neighbor_cell_index];
            thick_horizontal = box_index != neighbor_box_index;
        } else {
            thick_horizontal = false;
        }

        if (thick_vertical) {
            const rect = SDL_FRect{
                .x = sdl_context.cell_offset_px - sdl_context.thin_line_px + sdl_context.cell_stride_px * @as(f32, @floatFromInt(cell_coord[0] + 1)) - thickness_large_half_offset,
                .y = sdl_context.cell_offset_px - sdl_context.thin_line_px + sdl_context.cell_stride_px * @as(f32, @floatFromInt(cell_coord[1])) - thickness_large_half_offset,
                .w = sdl_context.thick_line_px,
                .h = sdl_context.cell_stride_px + sdl_context.thick_line_px,
            };

            psp_draw_colored_rect(rect, GridColor);
        }

        if (thick_horizontal) {
            const rect = SDL_FRect{
                .x = sdl_context.cell_offset_px - sdl_context.thin_line_px + sdl_context.cell_stride_px * @as(f32, @floatFromInt(cell_coord[0])) - thickness_large_half_offset,
                .y = sdl_context.cell_offset_px - sdl_context.thin_line_px + sdl_context.cell_stride_px * @as(f32, @floatFromInt(cell_coord[1] + 1)) - thickness_large_half_offset,
                .w = sdl_context.cell_stride_px + sdl_context.thick_line_px,
                .h = sdl_context.thick_line_px,
            };

            psp_draw_colored_rect(rect, GridColor);
        }
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

fn center_rect_inside_rect(rect: SDL_FRect, reference_rect: SDL_FRect) SDL_FRect {
    return .{
        .x = @round(reference_rect.x + (reference_rect.w - rect.w) / 2.0),
        .y = @round(reference_rect.y + (reference_rect.h - rect.h) / 2.0),
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

fn vram_buffer_to_relative_offset(vram_buffer: []align(16) u8) ?*align(16) anyopaque {
    return @ptrFromInt(@intFromPtr(vram_buffer.ptr) - @intFromPtr(psp.sceGeEdramGetAddr()));
}

fn convert_gu_pixel_format_to_display(pixel_format: psp.GuPixelFormat) psp.display.PixelFormat {
    return switch (pixel_format) {
        .Psm5650 => .rgb565,
        .Psm5551 => .rgba5551,
        .Psm4444 => .rgba4444,
        .Psm8888 => .rgba8888,
        else => @panic("Unsupported pixel format for display"),
    };
}

fn psp_draw_colored_rect(rect: SDL_FRect, color: ColorRGBA8) void {
    const sprite_vertex_format: psp.gu.types.VertexType = .{
        .vertex = .Vertex16Bit,
        .transform = .Transform2D,
    };

    const Vertex3D16 = extern struct {
        x: u16,
        y: u16,
        z: u16 = 0,
    };

    const sprite_vertex: [*]Vertex3D16 = @ptrCast(@alignCast(psp.sceGuGetMemory(@sizeOf(Vertex3D16) * 2)));
    const sprite_vertex_count = 2;

    sprite_vertex[0] = .{
        .x = @intFromFloat(rect.x),
        .y = @intFromFloat(rect.y),
    };

    sprite_vertex[1] = .{
        .x = @intFromFloat(rect.x + rect.w),
        .y = @intFromFloat(rect.y + rect.h),
    };

    psp.sceGuColor(@bitCast(Color32{ .c8888 = .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a } }));

    psp.sceGumDrawArray(.Sprites, sprite_vertex_format, sprite_vertex_count, null, sprite_vertex);
}

fn psp_draw_textured_rect(centered_glyph_rect: SDL_FRect) void {
    const sprite_vertex_format: psp.gu.types.VertexType = .{
        .uv = .Texture16Bit,
        .vertex = .Vertex16Bit,
        .transform = .Transform2D,
    };

    const VertexUV16_3D16 = extern struct {
        u: u16,
        v: u16,
        x: u16,
        y: u16,
        z: u16 = 0,
    };
    const sprite_vertex: [*]VertexUV16_3D16 = @ptrCast(@alignCast(psp.sceGuGetMemory(@sizeOf(VertexUV16_3D16) * 2)));
    const sprite_vertex_count = 2;

    sprite_vertex[0] = .{
        .u = 0,
        .v = 0,
        .x = @intFromFloat(centered_glyph_rect.x),
        .y = @intFromFloat(centered_glyph_rect.y),
    };

    sprite_vertex[1] = .{
        .u = @intFromFloat(centered_glyph_rect.w),
        .v = @intFromFloat(centered_glyph_rect.h),
        .x = @intFromFloat(centered_glyph_rect.x + centered_glyph_rect.w),
        .y = @intFromFloat(centered_glyph_rect.y + centered_glyph_rect.h),
    };

    psp.sceGumDrawArray(.Sprites, sprite_vertex_format, sprite_vertex_count, null, sprite_vertex);
}

fn rgba8_to_u24(rgba8: ColorRGBA8) u24 {
    const color = Color24{
        .r = rgba8.r,
        .g = rgba8.g,
        .b = rgba8.b,
    };
    return @bitCast(color);
}

fn cross(a: f32_2, b: f32_2) f32 {
    return a[0] * b[1] - a[1] * b[0];
}
