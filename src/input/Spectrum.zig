const errors = @import("../common/errors.zig");
const units = @import("../common/units.zig");

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: start_nm=8 B, end_nm=8 B, sample_count=4 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count
pub const SpectralGrid = struct {
    // UNITS:
    //   Public spectral bounds are stored in nanometers.
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
