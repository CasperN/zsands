// Milliseconds between updates.
pub const UPDATE_INTERVAL = 20;
// TODO: Separate low and high frequency input intervals, e.g. pause vs rotate.
pub const INPUT_INTERVAL = 30;

// Screen configuration for the main tetris board.
pub const N_SAND_ROWS = 150;
pub const N_SAND_COLS = 100;
pub const SAND_PX_SIZE = 3;
pub const SAND_MARGIN = 50;
pub const SCREEN_WIDTH = SAND_MARGIN * 2 + N_SAND_COLS * SAND_PX_SIZE;
pub const SCREEN_HEIGHT = SAND_MARGIN * 2 + N_SAND_ROWS * SAND_PX_SIZE;

// Other configuration.
pub const SAND_PER_BLOCK = 8;
