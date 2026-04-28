const std = @import("std");
const types = @import("types.zig");
const InstrumentModel = @import("../../../input/Instrument.zig").Instrument;
const BuiltinLineShapeKind = @import("../../../input/Instrument.zig").BuiltinLineShapeKind;

pub fn defaultKernelHalfSpanNm(fwhm_nm: f64) f64 {
    // UNITS:
    //   Half-span is expressed in nanometers and clamped to keep the fallback
    //   routine away from degenerate widths.
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
    @memset(kernel.offsets_nm[0..], 0.0);
    @memset(kernel.weights[0..], 0.0);
}

pub fn spectralResponseWeight(response: InstrumentModel.SpectralResponse, offset_nm: f64) f64 {
    const fwhm_nm = @max(response.fwhm_nm, 1.0e-4);
    return switch (response.slit_index) {
        .gaussian_modulated => {
            const sigma_nm = fwhm_nm / 2.354820045;
            const gaussian = @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
            const phase_rad = std.math.degreesToRadians(response.phase_deg);
            const modulation = 1.0 + response.amplitude * std.math.pow(f64, @sin(response.scale * offset_nm / fwhm_nm + phase_rad), 2.0);
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
    // UNITS:
    //   The width parameter is in nanometers and controls the normalized
    //   flat-top shape used by the builtin response.
    const w_nm = fwhm_nm / 1.681793;
    return std.math.pow(f64, 2.0, -2.0 * std.math.pow(f64, offset_nm / @max(w_nm, 1.0e-6), 4.0));
}
