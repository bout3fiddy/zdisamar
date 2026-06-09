const InstrumentModel = @import("../../../input/Instrument.zig");

// types.zig ------------------------------------------------------------------------------------------------- |
// Fixed instrument-integration storage shared by response, adaptive planning, and wavelength-plan code.       |
//                                                                                                             |
// used by                                                                                                     |
//   integration.zig writes one IntegrationKernel for each nominal wavelength and channel                      |
//   adaptive_plan.zig fills the same row from Gauss samples and normalized response weights                   |
//   wavelength_plan.zig compacts small rows inline and stores larger rows in side arrays                      |
//                                                                                                             |
// data shape                                                                                                  |
//   default_integration_sample_count is the legacy five-tap fallback. max_integration_sample_count follows    |
//   input/Instrument.zig so explicit line-shape tables and generated adaptive kernels share one hard limit.   |
//                                                                                                             |
// memory                                                                                                      |
//   IntegrationKernel is deliberately large fixed scratch: offsets and weights are parallel arrays so callers |
//   can fill, normalize, and later compact the active prefix without per-row heap allocation. Pass it by      |
//   pointer; do not copy it through hot paths.                                                                |
// ------------------------------------------------------------------------------------------------------------|

pub const default_integration_sample_count: usize = 5;
pub const max_integration_sample_count: usize = InstrumentModel.max_line_shape_samples;

// IntegrationKernel ----------------------------------------------------------------------------------------- |
// Fixed-capacity instrument integration offsets and weights for one nominal wavelength.                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32784 B (32.016 KiB), align: 8 B                                                                      |
//                                                                                                             |
// memory                                                                                                      |
// [    0..    7] sample_count : usize                                                                         |
// [    8..16391] offsets_nm   : [2048]f64                                                                     |
// [16392..32775] weights      : [2048]f64                                                                     |
// [32776..32776] enabled      : bool                                                                          |
// [32777..32783] padding      : 7 B                                                                           |
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// cache span: 513 cache lines at 64 B per line                                                                |
// footprint: per instance = 32784 B; one large stack/caller-owned kernel row                                  |
pub const IntegrationKernel = struct {
    enabled: bool,
    sample_count: usize,
    offsets_nm: [max_integration_sample_count]f64,
    weights: [max_integration_sample_count]f64,
};
