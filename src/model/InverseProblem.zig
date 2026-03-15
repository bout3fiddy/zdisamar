const errors = @import("../core/errors.zig");
const MeasurementVector = @import("Measurement.zig").MeasurementVector;
const StateVector = @import("StateVector.zig").StateVector;

pub const DerivativeMode = enum {
    none,
    semi_analytical,
    analytical_plugin,
    numerical,
};

pub const InverseProblem = struct {
    id: []const u8 = "inverse-0",
    state_vector: StateVector = .{},
    measurements: MeasurementVector = .{},

    pub fn validate(self: InverseProblem) errors.Error!void {
        if (self.id.len == 0) return errors.Error.InvalidRequest;
        if (self.state_vector.value_count == 0) return errors.Error.InvalidRequest;
        try self.measurements.validate();
    }
};
