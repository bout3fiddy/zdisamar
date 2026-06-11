// fast_mode.zig ----------------------------------------------------------------------------------------------|
// WP2 placeholder for later fastmode controls. The parsed default route consumes no fastmode controls yet.    |
// ------------------------------------------------------------------------------------------------------------|

// FastModeControls -------------------------------------------------------------------------------------------|
// Placeholder row for later fastmode packages; WP2 keeps the future control family explicit.                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 1 B (0.001 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..0] enabled : bool                                                                                       |
pub const FastModeControls = struct {
    enabled: bool = false,
};
// ------------------------------------------------------------------------------------------------------------|
