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

const SAND_PER_BLOCK = 8;

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

const TetminoKind = enum(u8) {
    L,
    P,
    S,
    Z,
    T,
    I,
    O,
    fn random(rng: *std.rand.Random) TetminoKind {
        return switch (rng.intRangeLessThan(u8, 0, 7)) {
            0 => TetminoKind.L,
            1 => TetminoKind.P,
            2 => TetminoKind.S,
            3 => TetminoKind.Z,
            4 => TetminoKind.T,
            5 => TetminoKind.I,
            6 => TetminoKind.O,
            else => undefined,
        };
    }
    // Returns the shape of this tetmino, as indices in a 2x4 grid.
    // Grid: 0 1 2 3
    //       4 5 6 7
    fn blocks_filled(self: TetminoKind) [4]u8 {
        return switch (self) {
            .L => .{ 4, 5, 6, 2 },
            .P => .{ 0, 1, 2, 6 },
            .S => .{ 1, 2, 4, 5 },
            .Z => .{ 0, 1, 5, 6 },
            .T => .{ 0, 1, 2, 5 },
            .I => .{ 0, 1, 2, 3 },
            .O => .{ 1, 2, 5, 6 },
        };
    }
};

const Rotation = enum(u8) {
    R0,
    R90,
    R180,
    R270,

    fn random(rng: *std.rand.Random) Rotation {
        return switch (rng.intRangeLessThan(u8, 0, 3)) {
            0 => Rotation.R0,
            1 => Rotation.R90,
            2 => Rotation.R270,
            3 => Rotation.R180,
            else => undefined,
        };
    }
    fn rotate_offsets(self: Rotation, dx: isize, dy: isize) struct { isize, isize } {
        return switch (self) {
            .R0 => .{ dx, dy },
            .R90 => .{ dy, dx },
            .R180 => .{ -dx, -dy },
            .R270 => .{ -dy, -dx },
        };
    }
    fn rotate_clockwise(self: *Rotation) void {
        self.* = switch (self.*) {
            .R0 => Rotation.R90,
            .R90 => Rotation.R180,
            .R180 => Rotation.R270,
            .R270 => Rotation.R0,
        };
    }
    fn rotate_counter_clockwise(self: *Rotation) void {
        self.* = switch (self.*) {
            .R0 => Rotation.R270,
            .R90 => Rotation.R0,
            .R180 => Rotation.R90,
            .R270 => Rotation.R180,
        };
    }
};

const Tetmino = struct {
    color: Color,
    kind: TetminoKind,
    rotation: Rotation,
    column: usize,
    row: usize,

    fn init(rng: *std.rand.Random) Tetmino {
        return .{
            .color = Color.random(rng),
            .kind = TetminoKind.random(rng),
            .rotation = Rotation.random(rng),
            .row = N_SAND_ROWS - 10,
            .column = N_SAND_COLS / 2,
        };
    }
    fn shift(self: *Tetmino, left: bool) void {
        _ = self;
        _ = left;
        // TODO: Try shifting tetmino, avoiding collisions with the wall or
        // sand.
        // var furthest_left = self.column;
        // var furthest_right = self.column;
        // for (0..8) |block| {
        //     const d_row = if (block < 4) 0 else SAND_PER_BLOCK;
        //     const d_cols = @mod(block, 4) * SAND_PER_BLOCK;

        // }
    }

    fn draw(self: Tetmino, sdl: SdlContext) void {
        // Decompose a TetminoKind into 8 blocks. Each is a cell.
        for (self.kind.blocks_filled()) |block| {
            // TODO: This would be more succinct with a Vec2 type.
            var d_row: isize = if (block < 4) 0 else SAND_PER_BLOCK;
            var d_cols: isize = @mod(block, 4) * SAND_PER_BLOCK;
            const offsets = self.rotation.rotate_offsets(d_row, d_cols);
            d_row = offsets[0];
            d_cols = offsets[1];
            const column: usize = @intCast(@as(isize, @intCast(self.column)) + d_cols);
            const row: usize = @intCast(@as(isize, @intCast(self.row)) + d_row);
            sdl.draw_rect(Rect{
                .color = self.color,
                .height = SAND_PER_BLOCK * SAND_PX_SIZE,
                .width = SAND_PER_BLOCK * SAND_PX_SIZE,
                .x = @intCast(column * SAND_PX_SIZE + SAND_MARGIN),
                .y = @intCast(SCREEN_HEIGHT - SAND_MARGIN - SAND_PX_SIZE * row),
            });
        }
    }
};

const GameState = struct {
    sands: [N_SAND_ROWS][N_SAND_ROWS]?Sand,
    live_tetmino: ?Tetmino,
    rng: *std.rand.Random,

    fn init(rng: *std.rand.Random) GameState {
        var self = GameState{
            .sands = undefined,
            .live_tetmino = null,
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

    fn create_tetmino(self: *GameState) void {
        if (self.live_tetmino == null) {
            self.live_tetmino = Tetmino.init(self.rng);
        } else {
            self.live_tetmino = null;
        }
        // const left = self.rng.intRangeLessThan(usize, 0, N_SAND_COLS - 10);
        // const color = Color.random(self.rng);
        // for (0..10) |di| {
        //     for (0..10) |dj| {
        //         const row = N_SAND_ROWS - 1 - di;
        //         const col = left + dj;
        //         self.sands[row][col] = Sand{
        //             .color = color,
        //         };
        //     }
        // }
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

    fn update(self: *GameState, controller: Controller) void {
        if (self.live_tetmino != null) {
            const tet = &self.live_tetmino.?;
            if (controller.clockwise and !controller.counter_clockwise) {
                tet.rotation.rotate_clockwise();
            }
            if (controller.counter_clockwise and !controller.clockwise) {
                tet.rotation.rotate_counter_clockwise();
            }
        }
        // Collision detection, etc.
        self.drop_sands();
    }

    fn draw(self: GameState, sdl: SdlContext) void {
        if (self.live_tetmino != null) {
            self.live_tetmino.?.draw(sdl);
        }

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

const BUTTON_RATE_LIMIT = 250; // milliseconds.

const RateLimitedButton = struct {
    last_press_time: u64,
    last_handled_time: u64,

    fn init() RateLimitedButton {
        return .{ .last_press_time = 0, .last_handled_time = 0 };
    }

    fn press(self: *RateLimitedButton, now: u64) void {
        self.last_press_time = now;
    }

    fn should_handle(self: *RateLimitedButton, now: u64) bool {
        if (self.last_handled_time + BUTTON_RATE_LIMIT < self.last_press_time) {
            self.last_handled_time = now;
            return true;
        }
        return false;
    }
};

const Controller = struct {
    up: bool,
    down: bool,
    left: bool,
    right: bool,
    clockwise: bool,
    counter_clockwise: bool,
    pause: RateLimitedButton,
    action: RateLimitedButton,
    quit: bool,

    fn init() Controller {
        return Controller{
            .up = false,
            .down = false,
            .left = false,
            .right = false,
            .clockwise = false,
            .counter_clockwise = false,
            .pause = RateLimitedButton.init(),
            .action = RateLimitedButton.init(),
            .quit = false,
        };
    }

    fn poll_sdl_events(self: *Controller) void {
        var event = c.SDL_Event{ .type = 0 };
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => self.quit = true,
                c.SDL_KEYDOWN, c.SDL_KEYUP => {
                    const is_pressed = event.type == c.SDL_KEYDOWN;
                    const now = c.SDL_GetTicks64();
                    switch (event.key.keysym.sym) {
                        c.SDLK_w => self.up = is_pressed,
                        c.SDLK_s => self.down = is_pressed,
                        c.SDLK_a => self.left = is_pressed,
                        c.SDLK_d => self.right = is_pressed,
                        c.SDLK_LSHIFT => self.counter_clockwise = is_pressed,
                        c.SDLK_RSHIFT => self.clockwise = is_pressed,
                        c.SDLK_ESCAPE => self.pause.press(now),
                        c.SDLK_SPACE => self.action.press(now),
                        else => {},
                    }
                },
                else => {},
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
    var controller = Controller.init();

    var is_paused = false;

    // Begin the game loop.
    var next_time = c.SDL_GetTicks64() + TICK_TIME;
    while (true) {
        // First, handle events...
        controller.poll_sdl_events();
        if (controller.quit) break;

        var now = c.SDL_GetTicks64();

        if (controller.pause.should_handle(now)) {
            is_paused = !is_paused;
        }
        if (controller.action.should_handle(now)) {
            game_state.create_tetmino();
        }

        if (!is_paused) {
            game_state.update(controller);
        }

        sdl.clear_screen();
        game_state.draw(sdl);
        sdl.present();

        // Sleep until next frame.
        now = c.SDL_GetTicks64();
        if (now < next_time) {
            const remaining = next_time - now;
            c.SDL_Delay(@intCast(remaining));
        }
        next_time += TICK_TIME;
    }
}
