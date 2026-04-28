const InstrumentModel = @import("../../../input/Instrument.zig");

pub const default_integration_sample_count: usize = 5;
pub const max_integration_sample_count: usize = InstrumentModel.max_line_shape_samples;

pub const IntegrationKernel = struct {
    enabled: bool,
    sample_count: usize,
    offsets_nm: [max_integration_sample_count]f64,
    weights: [max_integration_sample_count]f64,
};
