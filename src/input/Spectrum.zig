const errors = @import("../common/errors.zig");
const units = @import("../common/units.zig");

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
