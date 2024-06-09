const std = @import("std");
const sdl = @import("sdl.zig");
const constants = @import("constants.zig");

const SAND_PER_BLOCK = constants.SAND_PER_BLOCK;
const N_SAND_ROWS = constants.N_SAND_ROWS;
const N_SAND_COLS = constants.N_SAND_COLS;
const SandIndex = sdl.SandIndex;

// Possibly out of bounds coordinate in the sand grid.
const SandCoord = struct { x: isize, y: isize };

const TetminoKind = enum(u8) {
    L,
    P,
    S,
    Z,
    T,
    I,
    O,
    // Returns a random tetmino kind.
    pub fn random(rng: *std.rand.Random) TetminoKind {
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

pub const Tetmino = struct {
    color: sdl.Color,
    kind: TetminoKind,
    rotation: Rotation,
    column: isize,
    row: isize,

    pub fn init(rng: *std.rand.Random) Tetmino {
        return .{
            .color = sdl.Color.random(rng),
            .kind = TetminoKind.random(rng),
            .rotation = Rotation.random(rng),
            .row = N_SAND_ROWS - 10,
            .column = N_SAND_COLS / 2,
        };
    }
    // Returns the 4 block_centers that make up the tetmino.
    pub fn block_centers(self: Tetmino) [4]SandCoord {
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

    pub fn shift(self: *Tetmino, left: bool) void {
        self.column += if (left) -1 else 1;
        self.correct_horizontal_position();
    }
    pub fn rotate(self: *Tetmino, clockwise: bool) void {
        if (clockwise) {
            self.rotation.rotate_clockwise();
        } else {
            self.rotation.rotate_counter_clockwise();
        }
        self.correct_horizontal_position();
    }

    pub fn correct_horizontal_position(self: *Tetmino) void {
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

    pub fn as_sand_coordinates(self: Tetmino) TetminoSandCoordinates {
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

    pub fn draw(self: Tetmino, sdl_context: sdl.SdlContext) void {
        // TODO: We could draw just 4 rectangles if we drew them at the block
        // level instead of at the sand level, however previously there was a
        // visual stutter due to subtle implementation differences, so now this
        // function relies on `as_sand_coordinates`.
        for (self.as_sand_coordinates()) |coord| {
            sdl_context.draw_sand(coord, self.color);
        }
    }
};
