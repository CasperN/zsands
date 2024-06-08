const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const constants = @import("constants.zig");
const SAND_PX_SIZE = constants.SAND_PX_SIZE;
const SAND_MARGIN = constants.SAND_MARGIN;
const SCREEN_WIDTH = constants.SCREEN_WIDTH;
const SCREEN_HEIGHT = constants.SCREEN_HEIGHT;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn random(rng: *std.rand.Random) Color {
        return Color{
            .r = rng.int(u8),
            .g = rng.int(u8),
            .b = rng.int(u8),
        };
    }
};

// In-bounds coordinates on the sand grid.
pub const SandIndex = struct { x: usize, y: usize };

pub const Rect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    color: Color,
};

pub const SdlContext = struct {
    window: *c.SDL_Window,
    surface: *c.SDL_Surface,
    renderer: *c.SDL_Renderer,

    pub fn init(title: [*c]const u8) SdlContext {
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) < 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        }
        var self = SdlContext{
            .window = undefined,
            .surface = undefined,
            .renderer = undefined,
        };
        const w = c.SDL_CreateWindow(
            title,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            SCREEN_WIDTH,
            SCREEN_HEIGHT,
            0,
        );
        if (w == null) {
            c.SDL_Log("Failed to create window %s", c.SDL_GetError());
        }
        self.window = w.?;
        self.surface = c.SDL_GetWindowSurface(self.window).?;
        self.renderer = c.SDL_GetRenderer(self.window).?;
        return self;
    }

    pub fn destroy(self: SdlContext) void {
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
    pub fn clear_screen(self: SdlContext) void {
        // TODO: Probably should check these error codes...
        _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 128);
        _ = c.SDL_RenderClear(self.renderer);
    }
    pub fn draw_rect(self: SdlContext, rect: Rect) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, rect.color.r, rect.color.g, rect.color.b, 255);
        const sdl_rect = c.SDL_Rect{
            .x = @intCast(rect.x),
            .y = @intCast(rect.y),
            .w = @intCast(rect.width),
            .h = @intCast(rect.height),
        };
        _ = c.SDL_RenderFillRect(self.renderer, &sdl_rect);
    }

    // Draws a sand cell given its coordiantes and color.
    pub fn draw_sand(self: SdlContext, sand: SandIndex, color: Color) void {
        self.draw_rect(Rect{
            .x = @intCast(sand.x * SAND_PX_SIZE + SAND_MARGIN),
            .y = @intCast(SCREEN_HEIGHT - SAND_MARGIN - SAND_PX_SIZE * sand.y),
            .width = SAND_PX_SIZE,
            .height = SAND_PX_SIZE,
            .color = color,
        });
    }

    pub fn present(self: SdlContext) void {
        _ = c.SDL_RenderPresent(self.renderer);
    }

    pub fn get_ticks(self: SdlContext) u64 {
        _ = self;
        return c.SDL_GetTicks64();
    }
    pub fn sleep_until(self: SdlContext, next_time: u64) void {
        const now = self.get_ticks();
        if (now < next_time) {
            c.SDL_Delay(@intCast(next_time - now));
        }
    }
};

pub const Controller = struct {
    up: bool,
    down: bool,
    left: bool,
    right: bool,
    clockwise: bool,
    counter_clockwise: bool,
    pause: bool,
    action: bool,
    quit: bool,

    pub fn poll_control_inputs() Controller {
        var self = Controller{
            .up = false,
            .down = false,
            .left = false,
            .right = false,
            .clockwise = false,
            .counter_clockwise = false,
            .pause = false,
            .action = false,
            .quit = false,
        };
        var event = c.SDL_Event{ .type = 0 };
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => self.quit = true,
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_w => self.up = true,
                        c.SDLK_s => self.down = true,
                        c.SDLK_a => self.left = true,
                        c.SDLK_d => self.right = true,
                        c.SDLK_LSHIFT => self.counter_clockwise = true,
                        c.SDLK_RSHIFT => self.clockwise = true,
                        c.SDLK_ESCAPE => self.pause = true,
                        c.SDLK_SPACE => self.action = true,
                        else => {},
                    }
                },
                else => {},
            }
        }
        return self;
    }
};
