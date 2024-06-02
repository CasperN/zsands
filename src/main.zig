const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const TICK_TIME = 50;

const Rect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    rgb: [3]u8,
};

const SdlContext = struct {
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
            680,
            480,
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
        _ = c.SDL_SetRenderDrawColor(self.renderer, rect.rgb[0], rect.rgb[1], rect.rgb[2], 255);
        const sdl_rect = c.SDL_Rect{
            .x = @intCast(rect.x),
            .y = @intCast(rect.y),
            .w = @intCast(rect.width),
            .h = @intCast(rect.height),
        };
        _ = c.SDL_RenderFillRect(self.renderer, &sdl_rect);
    }

    pub fn present(self: SdlContext) void {
        _ = c.SDL_RenderPresent(self.renderer);
    }
};

const GameState = struct {
    x: u32,
    y: u32,

    fn update(self: *GameState) void {
        self.x = @mod(self.x + 1, 480);
        self.y = @mod(self.y + 1, 360);
    }

    fn draw(self: GameState, sdl: SdlContext) void {
        sdl.draw_rect(Rect{
            .x = self.x,
            .y = self.y,
            .width = 100,
            .height = 100,
            .rgb = .{ 200, 100, 50 },
        });
    }
};

pub fn main() !void {
    const sdl = SdlContext.init("Tetris Sands");
    defer sdl.destroy();

    var game_state = GameState{ .x = 100, .y = 100 };
    var event = c.SDL_Event{ .type = 0 };
    var next_time = c.SDL_GetTicks64() + TICK_TIME;
    game_loop: while (true) {
        // First, handle events...
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_QUIT) break :game_loop;
        }

        game_state.update();
        sdl.clear_screen();
        game_state.draw(sdl);
        sdl.present();

        // Sleep until next frame.
        const now = c.SDL_GetTicks64();
        if (now < next_time) {
            const remaining = next_time - now;
            c.SDL_Delay(@intCast(remaining));
        }
        next_time += TICK_TIME;
    }
}
