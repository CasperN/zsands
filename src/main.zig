const std = @import("std");
const sdl = @import("sdl.zig");
const constants = @import("constants.zig");
const t = @import("tetmino.zig");

const N_SAND_ROWS = constants.N_SAND_ROWS;
const N_SAND_COLS = constants.N_SAND_COLS;

// We will union adjacent sand by color. If the union touches both
// the left and right walls, then the sand shall disappear.
const Group = union(enum) {
    const Extent = struct {
        left_most: usize,
        right_most: usize,
    };

    // Leader pointer.
    follower: SandIndex,

    // Min and max extent of this group.
    extent: Extent,
};

const SandIndex = sdl.SandIndex;

const GameState = struct {
    colors: [N_SAND_ROWS][N_SAND_COLS]?sdl.Color,
    groups: [N_SAND_ROWS][N_SAND_COLS]?Group,
    live_tetmino: ?t.Tetmino,
    rng: *std.rand.Random,
    show_groups: bool,

    fn init(rng: *std.rand.Random) GameState {
        var self = GameState{
            .colors = undefined,
            .groups = undefined,
            .live_tetmino = null,
            .rng = rng,
            .show_groups = false,
        };
        // Initialize the undefined sands to null.
        for (0..N_SAND_ROWS) |i| {
            for (0..N_SAND_COLS) |j| {
                self.colors[i][j] = null;
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

    fn index_group(self: *GameState, i: SandIndex) *?Group {
        return &self.groups[i.y][i.x];
    }

    fn create_tetmino(self: *GameState) void {
        std.debug.assert(self.live_tetmino == null);
        self.live_tetmino = t.Tetmino.init(self.rng);
    }

    fn drop_sands(self: *GameState) void {
        for (1..N_SAND_ROWS) |i| {
            for (0..N_SAND_COLS) |j0| {
                const j = if (i % 2 == 0) j0 else N_SAND_COLS - 1 - j0;
                const current_cell = &self.colors[i][j];
                const row_below = &self.colors[i - 1];
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
        for (0..N_SAND_ROWS) |row| {
            for (0..N_SAND_COLS) |col| {
                // If the cell is empty of sand, then its part of no group.
                if (self.colors[row][col] == null) {
                    self.groups[row][col] = null;
                    continue;
                }
                // Initialize the cell's group as a singleton.
                self.groups[row][col] = Group{
                    .extent = .{
                        .left_most = col,
                        .right_most = col,
                    },
                };
                const current_color = self.colors[row][col].?;
                // Try to join the cell below.
                if (row > 0 and
                    self.groups[row - 1][col] != null and
                    current_color.equals(self.colors[row - 1][col].?))
                {
                    self.join_group(
                        SandIndex{ .x = col, .y = row },
                        SandIndex{ .x = col, .y = row - 1 },
                    );
                }
                // Try to join the cell to the left.
                if (col > 0 and
                    self.groups[row][col - 1] != null and
                    current_color.equals(self.colors[row][col - 1].?))
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
        // the max depth is bounded more or less by the sand height.
        const max_depth = constants.N_SAND_COLS;
        var path_to_leader: [max_depth]?SandIndex = undefined;
        for (0..max_depth) |k| path_to_leader[k] = null;

        path_to_leader[0] = i;
        var lead_index: ?SandIndex = null;
        var max_depth_reached: usize = 1;
        for (1..max_depth) |depth| {
            max_depth_reached = depth;
            const previous = path_to_leader[depth - 1].?;
            const current = self.groups[previous.y][previous.x];
            if (current == null) {
                self.debug_print_state();
                std.debug.panic(
                    \\ Attempting to traverse to leader of {d},{d}.
                    \\ At depth {d}, we point to a null group at {d},{d} as leader.\n
                , .{ i.y, i.x, depth, previous.y, previous.x });
            }
            switch (current.?) {
                .follower => |leader_coord| {
                    path_to_leader[depth] = leader_coord;
                },
                .extent => {
                    lead_index = previous;
                    break;
                },
            }
        }
        if (lead_index == null) {
            self.debug_print_state();
            std.debug.panic(
                "Failed to traverse to leader. mdr={d} row={d}, col={d}\n",
                .{ max_depth_reached, i.y, i.x },
            );
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
        self.index_group(lead_a).* = Group{ .follower = lead_b };
    }

    fn convert_live_tetmino_to_sand(self: *GameState) void {
        std.debug.assert(self.live_tetmino != null);
        for (self.live_tetmino.?.as_sand_coordinates()) |coord| {
            if (coord.y >= N_SAND_ROWS) {
                return;
            }

            self.colors[coord.y][coord.x] = self.live_tetmino.?.color;
        }
        self.live_tetmino = null;
    }
    fn clear_sands(self: *GameState) void {
        for (0..N_SAND_ROWS) |row| {
            iter_sands: for (0..N_SAND_COLS) |col| {
                if (self.groups[row][col] == null) continue;
                const lead = self.traverse_to_group_leader(
                    SandIndex{ .x = col, .y = row },
                );
                const extent = self.index_group(lead).*.?.extent;
                if (extent.left_most == 0 and extent.right_most == N_SAND_COLS - 1) {
                    for (constants.SAND_CLEAR_PROGRESSION, 0..) |death_color, i| {
                        if (self.colors[row][col].?.equals(death_color)) {
                            if (i == 0) {
                                self.colors[row][col] = null;
                            } else {
                                self.colors[row][col].? = constants.SAND_CLEAR_PROGRESSION[i - 1];
                            }
                            continue :iter_sands;
                        }
                    }
                    const last = constants.SAND_CLEAR_PROGRESSION.len - 1;
                    self.colors[row][col].? = constants.SAND_CLEAR_PROGRESSION[last];
                }
            }
        }
    }

    fn live_tetmino_touches_sand_or_floor(self: GameState) bool {
        if (self.live_tetmino == null) return false;
        const tetmino = self.live_tetmino.?;
        for (tetmino.block_centers()) |coord| {
            // Consider the outline of a block, 1 sand cell beyond the edge.
            const outline_dist: isize = constants.SAND_PER_BLOCK / 2 + 1;
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
                if ((self.colors[bottom][x] != null) or (self.colors[top][x] != null)) {
                    return true;
                }
            }
            for (bottom..top) |y| {
                if ((self.colors[y][left] != null) or (self.colors[y][right] != null)) {
                    return true;
                }
            }
        }
        return false;
    }

    // Drops the tetmino by 1 line and returns whether it just hit the floor or sand.
    fn drop_tetmino(self: *GameState) bool {
        if (self.live_tetmino == null) return false;
        const tetmino = &self.live_tetmino.?;
        tetmino.row -= 1;
        if (self.live_tetmino_touches_sand_or_floor()) {
            self.convert_live_tetmino_to_sand();
            return true;
        }
        return false;
    }

    fn apply_controls(self: *GameState, controller: sdl.Controller) void {
        if (controller.show_groups) {
            self.show_groups = !self.show_groups;
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
    fn debug_print_state(self: GameState) void {
        std.debug.print("Game state:\n", .{});
        for (0..N_SAND_ROWS) |row| {
            std.debug.print("----------\n", .{});
            for (0..N_SAND_COLS) |col| {
                const sand = self.colors[row][col];
                const group = self.groups[row][col];
                if (sand == null and group == null) continue;
                std.debug.print("{d}-{d}:\t", .{ row, col });
                if (sand == null) {
                    std.debug.print("null\t", .{});
                } else {
                    const x = sand.?;
                    std.debug.print("{x}{x}{x}\t", .{ x.r, x.g, x.b });
                }

                if (group == null) {
                    std.debug.print("null\n", .{});
                } else {
                    switch (group.?) {
                        .follower => |f| {
                            std.debug.print(
                                "following({d},{d})\n",
                                .{ f.y, f.x },
                            );
                        },
                        .extent => |e| {
                            std.debug.print(
                                "LEADER of [{d},{d}] extent\n",
                                .{ e.left_most, e.right_most },
                            );
                        },
                    }
                }
            }
        }
    }

    fn draw(self: GameState, sdl_context: sdl.SdlContext) void {
        if (self.live_tetmino != null) {
            self.live_tetmino.?.draw(sdl_context);
        }

        for (0..N_SAND_ROWS) |row| {
            for (0..N_SAND_COLS) |col| {
                if (self.colors[row][col] == null) continue;
                const color = self.colors[row][col].?;
                sdl_context.draw_sand(SandIndex{ .x = col, .y = row }, color);
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
    var game_over = false;
    var now = sdl_context.get_ticks();
    var next_update_time = now;
    var next_input_time = now;
    var next_tetmino_time = now;
    var last_tetmino_creation_time = now - 1 - constants.MIN_TETMINO_LIFE;
    while (true) {
        now = sdl_context.get_ticks();

        if (now >= next_input_time) {
            const controller = sdl.Controller.poll_control_inputs();
            next_input_time = now + constants.INPUT_INTERVAL;
            if (controller.quit) break;
            if (game_over and controller.pause) {
                game_state = GameState.init(&rand);
                game_over = false;
            }
            if (controller.pause) is_paused = !is_paused;
            if (!is_paused) {
                game_state.apply_controls(controller);
            }
        }
        if (game_state.live_tetmino == null and now >= next_tetmino_time) {
            game_state.create_tetmino();
            last_tetmino_creation_time = now;
        }

        if (now >= next_update_time) {
            next_update_time = now + constants.UPDATE_INTERVAL;

            if (!is_paused and !game_over) {
                game_state.drop_sands();
                if (game_state.drop_tetmino()) {
                    if (last_tetmino_creation_time + constants.MIN_TETMINO_LIFE > now) {
                        game_over = true;
                        continue;
                    }
                    next_tetmino_time = now + constants.SPAWN_DELAY;
                }
                game_state.compute_unions();
                game_state.clear_sands();
            }
        }
        sdl_context.clear_screen();
        sdl_context.draw_board();
        game_state.draw(sdl_context);
        if (is_paused) {
            sdl_context.draw_pause_overlay();
        }
        sdl_context.present();

        // Sleep until next action.
        now = sdl_context.get_ticks();
        const next_time = @min(next_input_time, next_update_time);
        sdl_context.sleep_until(next_time);
    }
}
