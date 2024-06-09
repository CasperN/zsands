const sdl = @import("sdl.zig");

// Milliseconds between updates.
pub const UPDATE_INTERVAL = 20;
// TODO: Separate low and high frequency input intervals, e.g. pause vs rotate.
pub const INPUT_INTERVAL = 20;

// Screen configuration for the main tetris board.
pub const N_SAND_ROWS = 70;
pub const N_SAND_COLS = 60;
pub const SAND_PX_SIZE = 3;
pub const SAND_MARGIN = 50;
pub const SCREEN_WIDTH = SAND_MARGIN * 2 + N_SAND_COLS * SAND_PX_SIZE;
pub const SCREEN_HEIGHT = SAND_MARGIN * 2 + N_SAND_ROWS * SAND_PX_SIZE;

// Other configuration.
pub const SAND_PER_BLOCK = 8;

// When the extent of one color of sand touches the left and right walls,
// they will convert to these colors (in reverse order) and then dissapear.
const progresion_len = 20;
fn make_sand_clear_progression() [progresion_len]sdl.Color {
    var result: [progresion_len]sdl.Color = undefined;
    for (0..progresion_len) |i| {
        const x = 255 - 10 * i;
        result[i] = sdl.Color{ .r = x, .g = x, .b = x };
    }
    return result;
}
pub const SAND_CLEAR_PROGRESSION: [progresion_len]sdl.Color = make_sand_clear_progression();
