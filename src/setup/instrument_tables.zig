const scene_input = @import("../input/scene.zig");

// InstrumentTable --------------------------------------------------------------------------------------------|
// Instrument line-shape and support-grid setup controls.                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.063 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] name                         : []const u8                                                          |
// [16..23] line_fwhm_nm                 : f64                                                                 |
// [24..31] high_resolution_step_nm      : f64                                                                 |
// [32..39] high_resolution_half_span_nm : f64                                                                 |
// [40..47] adaptive_points_per_fwhm     : usize                                                               |
// [48..55] strong_line_min_divisions    : usize                                                               |
// [56..63] strong_line_max_divisions    : usize                                                               |
//                                                                                                             |
// referenced storage                                                                                          |
//   name borrows the scene control string.                                                                    |
pub const InstrumentTable = struct {
    name: []const u8,
    line_fwhm_nm: f64,
    high_resolution_step_nm: f64,
    high_resolution_half_span_nm: f64,
    adaptive_points_per_fwhm: usize,
    strong_line_min_divisions: usize,
    strong_line_max_divisions: usize,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(scene: scene_input.Scene) InstrumentTable {
    // build --------------------------------------------------------------------------------------------------|
    // Copy instrument and support-grid controls into a setup table.                                           |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .name = scene.observation.instrument_name,
        .line_fwhm_nm = scene.observation.instrument_line_fwhm_nm,
        .high_resolution_step_nm = scene.observation.high_resolution_step_nm,
        .high_resolution_half_span_nm = scene.observation.high_resolution_half_span_nm,
        .adaptive_points_per_fwhm = scene.observation.adaptive_points_per_fwhm,
        .strong_line_min_divisions = scene.observation.strong_line_min_divisions,
        .strong_line_max_divisions = scene.observation.strong_line_max_divisions,
    };
}
