const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const TICK_TIME = 50;
const N_SAND_ROWS = 250;
const N_SAND_COLS = 150;
const SAND_PX_SIZE = 3;
const SAND_MARGIN = 50;

const SCREEN_WIDTH = SAND_MARGIN * 2 + N_SAND_COLS * SAND_PX_SIZE;
const SCREEN_HEIGHT = SAND_MARGIN * 2 + N_SAND_ROWS * SAND_PX_SIZE;

const Color = struct {
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

const Rect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    color: Color,
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

    pub fn present(self: SdlContext) void {
        _ = c.SDL_RenderPresent(self.renderer);
    }
};

const Sand = struct {
    color: Color,
};

const GameState = struct {
    sands: [N_SAND_ROWS][N_SAND_ROWS]?Sand,
    rng: *std.rand.Random,

    fn init(rng: *std.rand.Random) GameState {
        var self = GameState{
            .sands = undefined,
            .rng = rng,
        };
        // Initialize the undefined sands to null.
        for (0..N_SAND_ROWS) |i| {
            for (0..N_SAND_COLS) |j| {
                self.sands[i][j] = null;
                if (rng.float(f32) < 0.1) {
                    // Make random sand.
                    self.sands[i][j] = Sand{ .color = Color.random(rng) };
                }
            }
        }
        return self;
    }

    fn drop_sands(self: *GameState) void {
        for (1..N_SAND_ROWS) |i| {
            for (0..N_SAND_COLS) |j| {
                const current_cell = &self.sands[i][j];
                const row_below = &self.sands[i - 1];
                // Try dropping straight down.
                if (row_below[j] == null) {
                    row_below[j] = current_cell.*;
                    current_cell.* = null;
                    continue;
                }
                // Try dropping left.
                if (j > 0 and row_below[j - 1] == null) {
                    row_below[j - 1] = current_cell.*;
                    current_cell.* = null;
                    continue;
                }
                // Try dropping right.
                if (j < N_SAND_COLS - 1 and row_below[j + 1] == null) {
                    row_below[j + 1] = current_cell.*;
                    current_cell.* = null;
                    continue;
                }
            }
        }
    }

    fn update(self: *GameState) void {
        // TODO: Spawn a tetmino and control it...
        // Collision detection, etc.
        self.drop_sands();
    }

    fn draw(self: GameState, sdl: SdlContext) void {
        for (0..N_SAND_ROWS) |i| {
            for (0..N_SAND_COLS) |j| {
                const sand = self.sands[i][j];
                if (sand == null) continue;
                sdl.draw_rect(Rect{
                    .x = @intCast(j * SAND_PX_SIZE + SAND_MARGIN),
                    .y = @intCast(SCREEN_HEIGHT - SAND_MARGIN - SAND_PX_SIZE * i),
                    .width = SAND_PX_SIZE,
                    .height = SAND_PX_SIZE,
                    .color = sand.?.color,
                });
            }
        }
    }
};

pub fn main() !void {
    // Initialize Random Number Generator.
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    var rand = prng.random();

    // Create window.
    const sdl = SdlContext.init("Tetris Sands");
    defer sdl.destroy();

    // Initialize the game.
    var game_state = GameState.init(&rand);

    // Begin the game loop.
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
