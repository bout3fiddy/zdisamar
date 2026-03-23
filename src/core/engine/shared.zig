const PreparedPlan = @import("../Plan.zig").PreparedPlan;
const MeasurementSpace = @import("../../kernels/transport/measurement.zig");

pub fn measurementProviders(plan: *const PreparedPlan) MeasurementSpace.ProviderBindings {
    return .{
        .transport = plan.providers.transport,
        .surface = plan.providers.surface,
        .instrument = plan.providers.instrument,
        .noise = plan.providers.noise,
    };
}
