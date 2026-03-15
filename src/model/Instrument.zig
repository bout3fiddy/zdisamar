const errors = @import("../core/errors.zig");

pub const Instrument = struct {
    name: []const u8 = "generic",
    sampling: []const u8 = "native",
    noise_model: []const u8 = "none",

    pub fn validate(self: Instrument) errors.Error!void {
        if (self.name.len == 0) {
            return errors.Error.MissingObservationInstrument;
        }
        if (self.sampling.len == 0 or self.noise_model.len == 0) {
            return errors.Error.InvalidRequest;
        }
    }
};
