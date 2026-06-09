const InstrumentModel = @import("../../../input/Instrument.zig");

// types.zig ------------------------------------------------------------------------------------------------- |
// Fixed scratch storage for instrument-response integration before wavelength plans compact it.               |
//                                                                                                             |
// used by                                                                                                     |
//   integration.zig writes one temporary IntegrationKernel for one nominal wavelength and channel             |
//   adaptive_plan.zig fills the same row from Gauss support samples and raw response weights                  |
//   wavelength_sampling.zig compacts the active prefix into inline rows or shared side arrays                 |
//                                                                                                             |
// data shape                                                                                                  |
//   default_integration_sample_count is the legacy five-tap fallback. max_integration_sample_count mirrors    |
//   input/Instrument.zig so explicit measured line-shape tables and generated adaptive kernels share one      |
//   hard limit and one caller-visible truncation boundary.                                                    |
//                                                                                                             |
// layout                                                                                                      |
//   IntegrationKernel is a builder row, not retained storage. offsets_nm and weights are parallel arrays;     |
//   sample_count names the active prefix. enabled tells the later measurement loop whether to integrate or    |
//   read one direct sample. Large rows are copied into side arrays after this builder step.                   |
//                                                                                                             |
// memory                                                                                                      |
//   The row is deliberately 32 KiB and caller-owned to avoid per-wavelength heap allocation. Pass it by       |
//   pointer and reuse it inside workers; copying it through hot paths would move hundreds of cache lines.     |
// ----------------------------------------------------------------------------------------------------------- |

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
