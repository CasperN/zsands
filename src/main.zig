const std = @import("std");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

// Milliseconds between updates.
const UPDATE_INTERVAL = 50;
// TODO: Separate low and high frequency input intervals, e.g. pause vs rotate.
const INPUT_INTERVAL = 40;

// Screen configuration for the main tetris board.
const N_SAND_ROWS = 250;
const N_SAND_COLS = 150;
const SAND_PX_SIZE = 3;
const SAND_MARGIN = 50;
const SCREEN_WIDTH = SAND_MARGIN * 2 + N_SAND_COLS * SAND_PX_SIZE;
const SCREEN_HEIGHT = SAND_MARGIN * 2 + N_SAND_ROWS * SAND_PX_SIZE;

// Other configuration.
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

const SandCoordinate = struct {
    row: isize,
    col: isize,
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

const BlockCenter = struct { x: isize, y: isize };

const TetminoKind = enum(u8) {
    L,
    P,
    S,
    Z,
    T,
    I,
    O,
    // Returns a random tetmino kind.
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
    // Relative coordinate
    fn block_offsets(self: TetminoKind) [4]BlockCenter {
        const half_block = SAND_PER_BLOCK / 2;
        return switch (self) {
            .L => .{
                .{ .x = half_block, .y = half_block },
                .{ .x = half_block, .y = -half_block },
                .{ .x = -half_block, .y = -half_block },
                .{ .x = -2 * half_block, .y = -half_block },
            },
            .P => .{
                .{ .x = half_block, .y = -half_block },
                .{ .x = half_block, .y = half_block },
                .{ .x = -half_block, .y = half_block },
                .{ .x = -2 * half_block, .y = half_block },
            },
            .S => .{
                .{ .x = 0, .y = half_block },
                .{ .x = 0, .y = -half_block },
                .{ .x = SAND_PER_BLOCK, .y = half_block },
                .{ .x = -SAND_PER_BLOCK, .y = -half_block },
            },
            .Z => .{
                .{ .x = 0, .y = half_block },
                .{ .x = 0, .y = -half_block },
                .{ .x = -SAND_PER_BLOCK, .y = half_block },
                .{ .x = SAND_PER_BLOCK, .y = -half_block },
            },
            .T => .{
                .{ .x = 0, .y = half_block },
                .{ .x = -SAND_PER_BLOCK, .y = half_block },
                .{ .x = SAND_PER_BLOCK, .y = half_block },
                .{ .x = 0, .y = -half_block },
            },
            .I => .{
                .{ .x = 0, .y = -half_block },
                .{ .x = 0, .y = -3 * half_block },
                .{ .x = 0, .y = half_block },
                .{ .x = 0, .y = 3 * half_block },
            },
            .O => .{
                .{ .x = half_block, .y = half_block },
                .{ .x = half_block, .y = -half_block },
                .{ .x = -half_block, .y = half_block },
                .{ .x = -half_block, .y = -half_block },
            },
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
    fn rotate_offsets(self: Rotation, coord: BlockCenter) BlockCenter {
        return switch (self) {
            .R0 => .{ .x = coord.x, .y = coord.y },
            .R90 => .{ .x = -coord.y, .y = coord.x },
            .R180 => .{ .x = -coord.x, .y = -coord.y },
            .R270 => .{ .x = coord.y, .y = -coord.x },
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
    column: isize,
    row: isize,

    fn init(rng: *std.rand.Random) Tetmino {
        return .{
            .color = Color.random(rng),
            .kind = TetminoKind.random(rng),
            .rotation = Rotation.random(rng),
            .row = N_SAND_ROWS - 10,
            .column = N_SAND_COLS / 2,
        };
    }
    // Returns the 4 block_centers that make up the tetmino.
    fn block_centers(self: Tetmino) [4]BlockCenter {
        var result = self.kind.block_offsets();
        // Convert the block offsets into absolute coordinates on the sand grid.
        for (0..4) |i| {
            var coord = self.rotation.rotate_offsets(result[i]);
            coord.x += self.column;
            coord.y += self.row;
            result[i] = coord;
        }
        return result;
    }

    fn shift(self: *Tetmino, left: bool) void {
        self.column += if (left) -1 else 1;
        self.correct_horizontal_position();
    }
    fn rotate(self: *Tetmino, clockwise: bool) void {
        if (clockwise) {
            self.rotation.rotate_clockwise();
        } else {
            self.rotation.rotate_counter_clockwise();
        }
        self.correct_horizontal_position();
    }

    fn correct_horizontal_position(self: *Tetmino) void {
        var min_left: isize = 0;
        var max_right: isize = N_SAND_COLS - 1;
        const half_side_len = SAND_PER_BLOCK / 2;
        for (self.block_centers()) |block_center| {
            min_left = @min(min_left, block_center.x - half_side_len);
            max_right = @max(max_right, block_center.x + half_side_len);
        }
        // You can only be beyond one edge at a time, logically.
        std.debug.assert((min_left == 0) or (max_right == N_SAND_COLS - 1));
        if (min_left < 0) {
            self.column -= min_left;
        }
        if (max_right > N_SAND_COLS - 1) {
            self.column -= max_right - (N_SAND_COLS - 1);
        }
    }

    fn draw(self: Tetmino, sdl: SdlContext) void {
        const half_side_len = SAND_PER_BLOCK / 2;
        for (self.block_centers()) |block_center| {
            // Get the top left.
            const x: u32 = @intCast(block_center.x - half_side_len);
            const y: u32 = @intCast(block_center.y - half_side_len);
            // Remap from sand-grid coordinate to pixel coordinate.
            sdl.draw_rect(Rect{
                .color = self.color,
                .height = SAND_PER_BLOCK * SAND_PX_SIZE,
                .width = SAND_PER_BLOCK * SAND_PX_SIZE,
                .x = x * SAND_PX_SIZE + SAND_MARGIN,
                .y = SCREEN_HEIGHT - SAND_MARGIN - y * SAND_PX_SIZE,
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

    fn apply_controls(self: *GameState, controller: Controller) void {
        if (controller.action) {
            self.create_tetmino();
        }
        // Control the live tetmino.
        if (self.live_tetmino != null) {
            const tetmino = &self.live_tetmino.?;

            if (controller.left != controller.right) {
                tetmino.shift(controller.left);
            }
            if (controller.clockwise != controller.counter_clockwise) {
                tetmino.rotate(controller.clockwise);
            }
        }
        // TODO: Once against a wall you can rotate to clip out of bounds.
        // After rotating we should bring you back in bounds.
        // Collision detection, etc.
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

const Controller = struct {
    up: bool,
    down: bool,
    left: bool,
    right: bool,
    clockwise: bool,
    counter_clockwise: bool,
    pause: bool,
    action: bool,
    quit: bool,

    fn init() Controller {
        return Controller{
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
    }

    fn reset(self: *Controller) void {
        self.* = Controller.init();
    }

    fn poll_sdl_events(self: *Controller) void {
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
    var now = c.SDL_GetTicks64();
    var next_update_time = now;
    var next_input_time = now;
    while (true) {
        now = c.SDL_GetTicks64();

        if (now >= next_input_time) {
            controller.poll_sdl_events();
            defer controller.reset();
            next_input_time += INPUT_INTERVAL;

            if (controller.quit) break;
            if (controller.pause) is_paused = !is_paused;

            game_state.apply_controls(controller);
        }

        if (now >= next_update_time) {
            next_update_time += UPDATE_INTERVAL;

            if (!is_paused) {
                game_state.drop_sands();
            }
        }

        sdl.clear_screen();
        game_state.draw(sdl);
        sdl.present();

        // Sleep until next action.
        now = c.SDL_GetTicks64();
        const next_time = @min(next_input_time, next_update_time);
        if (now < next_time) {
            c.SDL_Delay(@intCast(next_time - now));
        }
    }
}
