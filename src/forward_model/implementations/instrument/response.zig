const std = @import("std");
const types = @import("types.zig");
const InstrumentModel = @import("../../../input/Instrument.zig").Instrument;
const BuiltinLineShapeKind = @import("../../../input/Instrument.zig").BuiltinLineShapeKind;

// response.zig ----------------------------------------------------------------------------------------------- |
// Instrument spectral-response helpers used by fixed and adaptive integration kernels.                         |
//                                                                                                              |
// hot path                                                                                                     |
//   adaptive_plan.zig and integration.zig call spectralResponseWeight for each candidate offset while          |
//   building or evaluating an integration kernel.                                                              |
//                                                                                                              |
// math                                                                                                         |
//   response(delta) is a Gaussian-modulated, flat-top N4, triple flat-top N4, or builtin table shape.          |
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
    return if (response.high_resolution_half_span_nm > 0.0)
        response.high_resolution_half_span_nm
    else
        defaultKernelHalfSpanNm(response.fwhm_nm);
}

pub fn resetKernel(kernel: *types.IntegrationKernel) void {
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
