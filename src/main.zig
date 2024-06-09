const std = @import("std");
const sdl = @import("sdl.zig");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const constants = @import("constants.zig");
const UPDATE_INTERVAL = constants.UPDATE_INTERVAL;
const INPUT_INTERVAL = constants.INPUT_INTERVAL;
const N_SAND_ROWS = constants.N_SAND_ROWS;
const N_SAND_COLS = constants.N_SAND_COLS;
const SAND_PER_BLOCK = constants.SAND_PER_BLOCK;

// We will union adjacent sand by color. If the union touches both
// the left and right walls, then the sand shall disappear.
const SandUnion = union(enum) {
    const Extent = struct {
        left_most: usize,
        right_most: usize,
    };

    // Leader pointer.
    follower: SandIndex,

    // Min and max extent of this group.
    extent: Extent,
};

const Sand = struct { color: sdl.Color };

// Possibly out of bounds coordinate in the sand grid.
const SandCoord = struct { x: isize, y: isize };

const SandIndex = sdl.SandIndex;

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
    fn block_offsets(self: TetminoKind) [4]SandCoord {
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
    fn rotate_offsets(self: Rotation, coord: SandCoord) SandCoord {
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

const TetminoSandCoordinates = [4 * SAND_PER_BLOCK * SAND_PER_BLOCK]SandIndex;

const Tetmino = struct {
    color: sdl.Color,
    kind: TetminoKind,
    rotation: Rotation,
    column: isize,
    row: isize,

    fn init(rng: *std.rand.Random) Tetmino {
        return .{
            .color = sdl.Color.random(rng),
            .kind = TetminoKind.random(rng),
            .rotation = Rotation.random(rng),
            .row = N_SAND_ROWS - 10,
            .column = N_SAND_COLS / 2,
        };
    }
    // Returns the 4 block_centers that make up the tetmino.
    fn block_centers(self: Tetmino) [4]SandCoord {
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
        var right_most: isize = N_SAND_COLS - 1;
        const half_side_len = SAND_PER_BLOCK / 2;
        for (self.block_centers()) |block_center| {
            min_left = @min(min_left, block_center.x - half_side_len);
            right_most = @max(right_most, block_center.x + half_side_len);
        }
        // You can only be beyond one edge at a time, logically.
        std.debug.assert((min_left == 0) or (right_most == N_SAND_COLS - 1));
        if (min_left < 0) {
            self.column -= min_left;
        }
        if (right_most > N_SAND_COLS - 1) {
            self.column -= right_most - (N_SAND_COLS - 1);
        }
    }

    fn as_sand_coordinates(self: Tetmino) TetminoSandCoordinates {
        var result: TetminoSandCoordinates = undefined;
        var written: usize = 0;
        const half_side_len = SAND_PER_BLOCK / 2;
        for (self.block_centers()) |coord| {
            const left: usize = @intCast(coord.x - half_side_len);
            const right: usize = @intCast(coord.x + half_side_len);
            const bottom: usize = @intCast(coord.y - half_side_len);
            const top: usize = @intCast(coord.y + half_side_len);
            for (left..right) |x| {
                for (bottom..top) |y| {
                    result[written] = .{ .x = x, .y = y };
                    written += 1;
                }
            }
        }
        return result;
    }

    fn draw(self: Tetmino, sdl_context: sdl.SdlContext) void {
        // TODO: We could draw just 4 rectangles if we drew them at the block level instead of
        // at the sand level, however previously there was a visual stutter due to subtle
        // implementation differences, so now this function relies on `as_sand_coordinates`.
        for (self.as_sand_coordinates()) |coord| {
            sdl_context.draw_sand(coord, self.color);
        }
    }
};

const GameState = struct {
    sands: [N_SAND_ROWS][N_SAND_COLS]?Sand,
    groups: [N_SAND_ROWS][N_SAND_COLS]?SandUnion,
    live_tetmino: ?Tetmino,
    rng: *std.rand.Random,
    game_over: bool,
    show_groups: bool,

    fn init(rng: *std.rand.Random) GameState {
        var self = GameState{
            .sands = undefined,
            .groups = undefined,
            .live_tetmino = null,
            .rng = rng,
            .show_groups = false,
            .game_over = false,
        };
        // Initialize the undefined sands to null.
        for (0..N_SAND_ROWS) |i| {
            for (0..N_SAND_COLS) |j| {
                self.sands[i][j] = null;
                // if (rng.float(f32) < 0.1) {
                //     // Make random sand.
                //     self.sands[i][j] = Sand{ .color = sdl.Color.random(rng) };
                // }
            }
        }
        // Initialize the undefined groups to null.
        for (0..N_SAND_ROWS) |i| {
            for (0..N_SAND_COLS) |j| {
                self.groups[i][j] = null;
            }
        }
        return self;
    }

    fn index_group(self: *GameState, i: SandIndex) *?SandUnion {
        return &self.groups[i.y][i.x];
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
        if (self.game_over) return;
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

    fn compute_unions(self: *GameState) void {
        if (self.game_over) return;
        for (0..N_SAND_ROWS) |row| {
            for (0..N_SAND_COLS) |col| {
                // If the cell is empty of sand, then its part of no group.
                if (self.sands[row][col] == null) {
                    self.groups[row][col] = null;
                    continue;
                }
                // Initialize the cell's group as a singleton.
                self.groups[row][col] = SandUnion{
                    .extent = .{
                        .left_most = col,
                        .right_most = col,
                    },
                };
                const current_color = self.sands[row][col].?.color;
                // Try to join the cell below.
                if (row > 0 and
                    self.groups[row - 1][col] != null and
                    current_color.equals(self.sands[row - 1][col].?.color))
                {
                    self.join_group(
                        SandIndex{ .x = col, .y = row },
                        SandIndex{ .x = col, .y = row - 1 },
                    );
                }
                // Try to join the cell to the left.
                if (col > 0 and
                    self.groups[row][col - 1] != null and
                    current_color.equals(self.sands[row][col - 1].?.color))
                {
                    self.join_group(
                        SandIndex{ .x = col, .y = row },
                        SandIndex{ .x = col - 1, .y = row },
                    );
                }
            }
        }
    }
    fn traverse_to_group_leader(self: *GameState, i: SandIndex) SandIndex {
        // As per the union-find algorithm, we will follow `i` until we see a leader.
        // The path length is O(inverse ackermann) so its basically constant size.
        const max_depth = 10;
        var path_to_leader: [max_depth]?SandIndex = undefined;
        for (0..max_depth) |k| path_to_leader[k] = null;

        path_to_leader[0] = i;
        var lead_index: ?SandIndex = null;
        var max_depth_reached: usize = 1;
        for (1..max_depth) |depth| {
            const previous = path_to_leader[depth - 1].?;
            const current = self.groups[previous.y][previous.x];
            if (current == null) {
                std.debug.print("Attempting to traverse to leader of {d},{d}.\n", .{ i.y, i.x });
                std.debug.print("At depth {d}, we point to a null group at {d},{d} as leader.\n", .{ depth, previous.y, previous.x });
            }
            switch (current.?) {
                .follower => |leader_coord| {
                    path_to_leader[depth] = leader_coord;
                },
                .extent => {
                    lead_index = previous;
                    max_depth_reached = depth;
                    break;
                },
            }
        }
        // Reassign everything we saw along the path directly to the leader to accelerate
        // future lookups.
        for (0..max_depth_reached - 1) |p| {
            self.index_group(path_to_leader[p].?).*.?.follower = lead_index.?;
        }
        return lead_index.?;
    }

    // Unions the group of a and group of b.
    fn join_group(self: *GameState, a: SandIndex, b: SandIndex) void {
        const lead_a = self.traverse_to_group_leader(a);
        const lead_b = self.traverse_to_group_leader(b);
        if (lead_a.equals(lead_b)) return;

        // Merge the extent of group a into group b.
        const extent_a = self.index_group(lead_a).*.?.extent;
        const extent_b = &self.index_group(lead_b).*.?.extent;
        extent_b.left_most = @min(extent_b.left_most, extent_a.left_most);
        extent_b.right_most = @max(extent_b.right_most, extent_a.right_most);

        // Point the leader of group a to the leader of group b.
        self.index_group(lead_a).* = SandUnion{ .follower = lead_b };
    }

    fn convert_live_tetmino_to_sand(self: *GameState) void {
        std.debug.assert(self.live_tetmino != null);
        for (self.live_tetmino.?.as_sand_coordinates()) |coord| {
            if (coord.y >= N_SAND_ROWS) {
                self.game_over = true;
                return;
            }

            self.sands[coord.y][coord.x] = Sand{ .color = self.live_tetmino.?.color };
        }
        self.live_tetmino = null;
    }

    fn live_tetmino_touches_sand_or_floor(self: GameState) bool {
        if (self.live_tetmino == null) return false;
        const tetmino = self.live_tetmino.?;
        for (tetmino.block_centers()) |coord| {
            // Consider the outline of a block, 1 sand cell beyond the edge.
            const outline_dist: isize = SAND_PER_BLOCK / 2 + 1;
            const left: usize = @intCast(@max(coord.x - outline_dist, 0));
            const right: usize = @intCast(@min(coord.x + outline_dist, N_SAND_COLS - 1));
            const bottom: usize = @intCast(@max(coord.y - outline_dist, 0));
            const top: usize = @intCast(@min(coord.y + outline_dist, N_SAND_ROWS - 1));

            // Turn to sand if the block is against the floor.
            if (bottom == 0) {
                return true;
            }
            // Turn to sand if the block is next to sand.
            for (left..right) |x| {
                if ((self.sands[bottom][x] != null) or (self.sands[top][x] != null)) {
                    return true;
                }
            }
            for (bottom..top) |y| {
                if ((self.sands[y][left] != null) or (self.sands[y][right] != null)) {
                    return true;
                }
            }
        }
        return false;
    }

    fn drop_tetmino(self: *GameState) void {
        if (self.live_tetmino == null) return;
        const tetmino = &self.live_tetmino.?;
        tetmino.row -= 1;
        if (self.live_tetmino_touches_sand_or_floor()) {
            return self.convert_live_tetmino_to_sand();
        }
    }

    fn apply_controls(self: *GameState, controller: sdl.Controller) void {
        if (controller.show_groups) {
            self.show_groups = !self.show_groups;
        }

        if (self.game_over) {
            if (controller.pause) {
                // Reset the game.
                self.* = GameState.init(self.rng);
            }
            return;
        }

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

    fn draw(self: GameState, sdl_context: sdl.SdlContext) void {
        if (self.live_tetmino != null) {
            self.live_tetmino.?.draw(sdl_context);
        }

        for (0..N_SAND_ROWS) |row| {
            for (0..N_SAND_COLS) |col| {
                if (self.sands[row][col] == null) continue;
                const sand = self.sands[row][col].?;
                sdl_context.draw_sand(SandIndex{ .x = col, .y = row }, sand.color);
            }
        }
        // Draw unions for debugging purposes
        if (self.show_groups) {
            for (0..N_SAND_ROWS) |row| {
                for (0..N_SAND_COLS) |col| {
                    const g = self.groups[row][col];
                    if (g == null) continue;
                    switch (g.?) {
                        .follower => |leader| {
                            sdl_context.draw_line(SandIndex{
                                .x = col,
                                .y = row,
                            }, leader);
                        },
                        .extent => {},
                    }
                }
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
    const sdl_context = sdl.SdlContext.init("Tetris Sands");
    defer sdl_context.destroy();

    // Initialize the game.
    var game_state = GameState.init(&rand);
    var is_paused = false;

    // Begin the game loop.
    var now = sdl_context.get_ticks();
    var next_update_time = now;
    var next_input_time = now;
    while (true) {
        now = sdl_context.get_ticks();

        if (now >= next_input_time) {
            const controller = sdl.Controller.poll_control_inputs();
            next_input_time += INPUT_INTERVAL;

            if (controller.quit) break;
            if (controller.pause) is_paused = !is_paused;

            game_state.apply_controls(controller);
        }

        if (now >= next_update_time) {
            next_update_time += UPDATE_INTERVAL;

            if (!is_paused) {
                game_state.drop_sands();
                game_state.drop_tetmino();
                game_state.compute_unions();
            }
        }

        sdl_context.clear_screen();
        sdl_context.draw_board();
        game_state.draw(sdl_context);
        sdl_context.present();

        // Sleep until next action.
        now = sdl_context.get_ticks();
        const next_time = @min(next_input_time, next_update_time);
        sdl_context.sleep_until(next_time);
    }
}
