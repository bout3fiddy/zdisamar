const errors = @import("../core/errors.zig");

pub const Measurement = struct {
    product: []const u8 = "radiance",
    sample_count: u32 = 0,

    pub fn validate(self: Measurement) errors.Error!void {
        if (self.product.len == 0) return errors.Error.InvalidRequest;
        if (self.sample_count == 0) return errors.Error.InvalidRequest;
    }
};

pub const MeasurementVector = Measurement;
