const o2_case = @import("../input/o2_case.zig");

// PhaseTable -------------------------------------------------------------------------------------------------|
// Phase-function setup shape needed by later transport.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] coefficient_count       : usize                                                                     |
// [8..15] aerosol_asymmetry_factor: f64                                                                       |
pub const PhaseTable = struct {
    coefficient_count: usize,
    aerosol_asymmetry_factor: f64,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(case: o2_case.O2Case) PhaseTable {
    // build --------------------------------------------------------------------------------------------------|
    // Retain phase coefficient shape and aerosol asymmetry for later transport.                               |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .coefficient_count = 3,
        .aerosol_asymmetry_factor = case.aerosol.asymmetry_factor,
    };
}
