const InstrumentModel = @import("../../../input/Instrument.zig");

// types.zig ------------------------------------------------------------------------------------------------- |
// Fixed scratch storage for instrument-response integration before wavelength plans compact it. This is the   |
// byte-heavy handoff between response realization and the retained sampling plan: builders can write a large  |
// simple row, while simulation later reads compact per-nominal rows.                                          |
//                                                                                                             |
// lifecycle                                                                                                   |
//   input/Instrument.zig exposes max_line_shape_samples, the public cap used for measured line-shape tables   |
//   and generated high-resolution kernels. integration.zig resets and writes one IntegrationKernel for one    |
//   nominal wavelength and one channel. adaptive_plan.zig fills the same row from Gauss support samples.      |
//   wavelength_sampling.zig reuses caller-owned kernel scratch inside worker chunks, then compacts only the   |
//   active prefix into wavelength_plan.zig as disabled, inline-five-sample, or side-array retained storage.   |
//   spectral_eval.zig and output/instrument_response.zig read compacted samples; they do not retain or copy   |
//   this builder row.                                                                                         |
//                                                                                                             |
// row contract                                                                                                |
//   sample_count names the meaningful prefix of offsets_nm and weights. enabled=false means the later plan    |
//   should gather one direct sample at the shifted channel wavelength. enabled=true means offsets/weights     |
//   contain a normalized integration kernel and must be applied exactly once by spectral_eval.zig.            |
//                                                                                                             |
// memory                                                                                                      |
//   IntegrationKernel is 32784 B: two [2048]f64 arrays plus sample_count and enabled. It owns no heap         |
//   storage. Route builders take a pointer and rewrite the active prefix, avoiding a 513-cache-line copy.     |
//   Large adaptive/measured kernels move into side arrays after this scratch step; common                     |
//   direct and five-sample rows stay compact in the retained plan.                                            |
//                                                                                                             |
// boundary                                                                                                    |
//   This file defines only the scratch row and caps. Route order, normalization, error handling, adaptive     |
//   interval planning, and retained-plan ownership live in integration.zig, adaptive_plan.zig, and            |
//   wavelength_sampling.zig.                                                                                  |
// ----------------------------------------------------------------------------------------------------------- |

pub const default_integration_sample_count: usize = 5;
pub const max_integration_sample_count: usize = InstrumentModel.max_line_shape_samples;

// IntegrationKernel ----------------------------------------------------------------------------------------- |
// Fixed-capacity instrument integration offsets and weights for one nominal wavelength and one channel.       |
// The row is caller-owned scratch; only [0..sample_count] is valid after a builder returns.                   |
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
//                                                                                                             |
// hot use                                                                                                     |
//   Wavelength-plan workers pass this row by pointer while building radiance and irradiance kernels. Only     |
//   offsets_nm[0..sample_count] and weights[0..sample_count] are meaningful after a builder returns.          |
pub const IntegrationKernel = struct {
    enabled: bool,
    sample_count: usize,
    offsets_nm: [max_integration_sample_count]f64,
    weights: [max_integration_sample_count]f64,
};
// ------------------------------------------------------------------------------------------------------------|
