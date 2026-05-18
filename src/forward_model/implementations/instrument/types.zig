const InstrumentModel = @import("../../../input/Instrument.zig");

pub const default_integration_sample_count: usize = 5;
pub const max_integration_sample_count: usize = InstrumentModel.max_line_shape_samples;

// layout(64-bit):
//   size: 32784 B, align: 8 B
//   field storage: sample_count=8 B, offsets_nm=16384 B, weights=16384 B, enabled=1 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   inline arrays: offsets_nm:[2048]f64=16384 B, weights:[2048]f64=16384 B
//   cache span: 513 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32784 B (32.0 KiB); total = per instance * live instance count
pub const IntegrationKernel = struct {
    enabled: bool,
    sample_count: usize,
    offsets_nm: [max_integration_sample_count]f64,
    weights: [max_integration_sample_count]f64,
};
