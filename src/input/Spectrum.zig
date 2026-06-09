const errors = @import("../common/errors.zig");
const units = @import("../common/units.zig");

// Spectrum.zig -----------------------------------------------------------------------------------------------|
// Public spectral-grid bounds.                                                                                |
//                                                                                                             |
// data                                                                                                        |
//   SpectralGrid stores wavelength start/end bounds in nanometers plus the requested sample count.            |
//                                                                                                             |
// validation                                                                                                  |
//   WavelengthRange enforces ordered positive bounds. sample_count must be non-zero.                          |
// ------------------------------------------------------------------------------------------------------------|

// SpectralGrid -----------------------------------------------------------------------------------------------|
// One public spectral grid request.                                                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] start_nm     : f64                                                                                 |
// [ 8..15] end_nm       : f64                                                                                 |
// [16..19] sample_count : u32                                                                                 |
// [20..23] trailing padding : 4 B                                                                             |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per instance = 24 B (0.023 KiB); total = per instance * live grid count                          |
pub const SpectralGrid = struct {
    start_nm: f64 = 270.0,
    end_nm: f64 = 2400.0,
    sample_count: u32 = 0,

    pub fn validate(self: SpectralGrid) errors.Error!void {
        (units.WavelengthRange{
            .start_nm = self.start_nm,
            .end_nm = self.end_nm,
        }).validate() catch return errors.Error.InvalidRequest;

        if (self.sample_count == 0) {
            return errors.Error.InvalidRequest;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|
