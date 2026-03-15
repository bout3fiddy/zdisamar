const errors = @import("../core/errors.zig");
const Instrument = @import("Instrument.zig").Instrument;

pub const ObservationRegime = enum {
    nadir,
    limb,
    occultation,
};

pub const ObservationModel = struct {
    instrument: []const u8 = "generic",
    regime: ObservationRegime = .nadir,
    sampling: []const u8 = "native",
    noise_model: []const u8 = "none",

    pub fn instrumentSpec(self: ObservationModel) Instrument {
        return .{
            .name = self.instrument,
            .sampling = self.sampling,
            .noise_model = self.noise_model,
        };
    }

    pub fn validate(self: ObservationModel) errors.Error!void {
        try self.instrumentSpec().validate();
    }
};
