const std = @import("std");
const types = @import("types.zig");
const InstrumentModel = @import("../../../input/Instrument.zig").Instrument;
const BuiltinLineShapeKind = @import("../../../input/Instrument.zig").BuiltinLineShapeKind;

// response.zig ----------------------------------------------------------------------------------------------- |
// Scalar instrument-response math shared by integration kernels, adaptive support planning, and the legacy     |
// five-tap slit-convolution route. This file answers one narrow question: "what raw response weight belongs    |
// to this wavelength offset?" Callers decide which offsets exist, then normalize neighboring raw weights into  |
// a kernel whose weights sum to one.                                                                           |
//                                                                                                              |
// called by                                                                                                    |
//   integration.zig uses these helpers for explicit high-resolution grids, default five-tap kernels, and the   |
//   legacy slitKernelForScene path. adaptive_plan.zig uses the same response weights for every candidate       |
//   Gauss node before duplicate merging and final normalization. Measured line-shape tables bypass this file   |
//   because their rows already provide normalized table weights.                                               |
//                                                                                                              |
// route map                                                                                                    |
//   resetKernel/writeIdentityKernel : initialize the caller-owned IntegrationKernel scratch row                |
//   defaultKernelHalfSpanNm         : choose a finite support span for FWHM-only fallback routes               |
//   adaptiveKernelHalfSpanNm        : prefer explicit high-resolution support, otherwise use the default span  |
//   spectralResponseWeight          : dispatch resolved SpectralResponse.slit_index to one scalar formula      |
//   builtinLineShapeWeight          : evaluate the public BuiltinLineShapeKind family without modulation       |
//   flatTopN4Weight                 : shared flat-top N4 primitive used by both dispatchers                    |
//                                                                                                              |
// hot path                                                                                                     |
//   Adaptive planning can call spectralResponseWeight thousands of times around strong O2 lines. The helpers   |
//   allocate nothing, touch no tables, and read only the resolved SpectralResponse value plus the offset.      |
//   IntegrationKernel storage is caller-owned; this file writes only the tiny identity/reset cases.            |
//                                                                                                              |
// normalization boundary                                                                                       |
//   spectralResponseWeight, builtinLineShapeWeight, and flatTopN4Weight return raw non-negative weights.       |
//   integration.zig and adaptive_plan.zig divide by the sum after all offsets for a nominal wavelength have    |
//   been chosen. Keeping normalization outside this file lets fixed grids, adaptive Gauss nodes, and five-tap  |
//   fallback kernels share the same scalar formulas.                                                           |
//                                                                                                              |
// math names                                                                                                   |
//   delta  = offset_nm                                                                                         |
//   FWHM   = full width at half maximum in nm                                                                  |
//   sigma  = FWHM / 2.354820045 for Gaussian response                                                          |
//   gaussian(delta) = exp(-0.5 * (delta / sigma)^2)                                                            |
//   modulation(delta) = 1 + amplitude * sin(scale * delta / FWHM + phase)^2                                    |
//   flat_top_n4(delta) = 2^(-2 * (delta / width)^4), where width = FWHM / 1.681793                             |
//   triple flat-top = flat_top(delta) + flat_top(delta - 0.1 nm) + flat_top(delta + 0.1 nm)                    |
//                                                                                                              |
// numbers                                                                                                      |
//   1.0e-4 nm keeps zero/degenerate FWHM routes finite. 1.0e-6 nm keeps flat-top width division finite.        |
//   The +/-0.1 nm triple flat-top offsets are the retained instrument-line-shape spacing used by the existing  |
//   input pipeline and O2 A reference cases.                                                                   |
// ------------------------------------------------------------------------------------------------------------ |

pub fn defaultKernelHalfSpanNm(fwhm_nm: f64) f64 {
    // defaultKernelHalfSpanNm -------------------------------------------------------------------------------- |
    // Returns the fallback response half-span in nanometers and keeps degenerate widths away from zero.        |
    //                                                                                                          |
    // math                                                                                                     |
    //   half_span = max(3 * max(FWHM, 1e-4), 1e-4)                                                             |
    // -------------------------------------------------------------------------------------------------------- |

    return @max(3.0 * @max(fwhm_nm, 1.0e-4), 1.0e-4);
}

pub fn adaptiveKernelHalfSpanNm(response: InstrumentModel.SpectralResponse) f64 {
    // adaptiveKernelHalfSpanNm --------------------------------------------------------------------------------|
    // Return the support half-span used by adaptive interval planning.                                         |
    //                                                                                                          |
    // route                                                                                                    |
    //   explicit high_resolution_half_span_nm wins when present; otherwise the FWHM-only default span keeps    |
    //   adaptive and fallback routes on the same finite support rule.                                          |
    // -------------------------------------------------------------------------------------------------------- |

    return if (response.high_resolution_half_span_nm > 0.0)
        response.high_resolution_half_span_nm
    else
        defaultKernelHalfSpanNm(response.fwhm_nm);
}

pub fn resetKernel(kernel: *types.IntegrationKernel) void {
    // resetKernel ---------------------------------------------------------------------------------------------|
    // Clear the caller-owned builder row before a route writes the active prefix.                              |
    // -------------------------------------------------------------------------------------------------------- |

    kernel.enabled = false;
    kernel.sample_count = 0;
}

pub fn writeIdentityKernel(kernel: *types.IntegrationKernel, enabled: bool) void {
    // writeIdentityKernel -------------------------------------------------------------------------------------|
    // Stores the one-sample identity kernel used when no spectral integration broadening is active.            |
    //                                                                                                          |
    // math                                                                                                     |
    //   y(lambda_i) = 1 * y(lambda_i + 0)                                                                      |
    // -------------------------------------------------------------------------------------------------------- |

    resetKernel(kernel);
    kernel.enabled = enabled;
    kernel.sample_count = 1;
    kernel.offsets_nm[0] = 0.0;
    kernel.weights[0] = 1.0;
}

pub fn spectralResponseWeight(response: InstrumentModel.SpectralResponse, offset_nm: f64) f64 {
    // spectralResponseWeight ----------------------------------------------------------------------------------|
    // Evaluates the configured slit or line-shape response at one wavelength offset.                           |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Called while adaptive kernels compute sample weights. Reads only response controls, offset, FWHM, and  |
    //   builtin line-shape parameters.                                                                         |
    //                                                                                                          |
    // math                                                                                                     |
    //   Gaussian branch: exp(-0.5 * (delta / sigma)^2) * modulation                                            |
    //   modulation    : 1 + amplitude * sin(scale * delta / FWHM + phase)^2                                    |
    // -------------------------------------------------------------------------------------------------------- |

    const fwhm_nm = @max(response.fwhm_nm, 1.0e-4);
    return switch (response.slit_index) {
        .gaussian_modulated => {
            const sigma_nm = fwhm_nm / 2.354820045;
            const gaussian = @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
            const phase_rad = std.math.degreesToRadians(response.phase_deg);
            const modulation_phase = response.scale * offset_nm / fwhm_nm + phase_rad;
            const modulation = 1.0 + response.amplitude * std.math.pow(f64, @sin(modulation_phase), 2.0);
            return @max(gaussian * modulation, 0.0);
        },
        .flat_top_n4 => flatTopN4Weight(fwhm_nm, offset_nm),
        .triple_flat_top_n4 => flatTopN4Weight(fwhm_nm, offset_nm) +
            flatTopN4Weight(fwhm_nm, offset_nm - 0.1) +
            flatTopN4Weight(fwhm_nm, offset_nm + 0.1),
        .table => builtinLineShapeWeight(response.builtin_line_shape, fwhm_nm, offset_nm),
    };
}

pub fn builtinLineShapeWeight(shape: BuiltinLineShapeKind, fwhm_nm: f64, offset_nm: f64) f64 {
    // builtinLineShapeWeight ----------------------------------------------------------------------------------|
    // Evaluates the builtin instrument line shape selected by resolved input controls.                         |
    //                                                                                                          |
    // boundary                                                                                                 |
    //   This is the unmodulated public shape family. spectralResponseWeight handles the resolved slit-index    |
    //   route that can apply Gaussian modulation before integration normalization.                             |
    // -------------------------------------------------------------------------------------------------------- |

    const safe_fwhm_nm = @max(fwhm_nm, 1.0e-4);
    return switch (shape) {
        .gaussian => {
            const sigma_nm = safe_fwhm_nm / 2.354820045;
            return @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
        },
        .flat_top_n4 => flatTopN4Weight(safe_fwhm_nm, offset_nm),
        .triple_flat_top_n4 => flatTopN4Weight(safe_fwhm_nm, offset_nm) +
            flatTopN4Weight(safe_fwhm_nm, offset_nm - 0.1) +
            flatTopN4Weight(safe_fwhm_nm, offset_nm + 0.1),
    };
}

pub fn flatTopN4Weight(fwhm_nm: f64, offset_nm: f64) f64 {
    // flatTopN4Weight ---------------------------------------------------------------------------------------- |
    // Evaluates the normalized flat-top N4 response in nanometer units.                                        |
    //                                                                                                          |
    // math                                                                                                     |
    //   flat_top_n4(delta) = 2^(-2 * (delta / max(width, 1e-6))^4)                                             |
    //   width = FWHM / 1.681793                                                                                |
    // -------------------------------------------------------------------------------------------------------- |

    const w_nm = fwhm_nm / 1.681793;
    return std.math.pow(f64, 2.0, -2.0 * std.math.pow(f64, offset_nm / @max(w_nm, 1.0e-6), 4.0));
}
