const std = @import("std");

pub const Error = error{
    InvalidSampleCount,
    InvalidBounds,
    IndexOutOfRange,
    InvalidExplicitSamples,
};

// grid.zig --------------------------------------------------------------------------------------------------------------|
// Wavelength-axis helpers for instrument-grid output samples. The rest of the module asks this file for the              |
// nominal wavelength at an output index, whether that index comes from a uniform grid or measured channels.              |
//                                                                                                                        |
// main paths                                                                                                             |
//   SpectralGrid.sampleAt -> uniform native grid address                                                                 |
//   ResolvedAxis.sampleAt -> explicit measured wavelength when present, otherwise uniform grid                           |
// -----------------------------------------------------------------------------------------------------------------------|

// SpectralGrid ----------------------------------------------------------------------------------------------------------|
// Uniform output wavelength grid in nm. sample_count includes both endpoints.                                            |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 24 B (0.023 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] start_nm     : f64                                                                                            |
// [ 8..15] end_nm       : f64                                                                                            |
// [16..19] sample_count : u32                                                                                            |
// [20..23] padding      : 4 B                                                                                            |
//                                                                                                                        |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                               |
// footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count                                 |
pub const SpectralGrid = struct {
    start_nm: f64,
    end_nm: f64,
    sample_count: u32,

    pub fn validate(self: SpectralGrid) Error!void {
        // SpectralGrid.validate -----------------------------------------------------------------------------------------|
        // Reject grids that cannot define a positive finite step between two endpoints.                                  |
        // ---------------------------------------------------------------------------------------------------------------|

        if (self.sample_count < 2) return Error.InvalidSampleCount;
        if (self.end_nm <= self.start_nm) return Error.InvalidBounds;
    }

    pub fn sampleAt(self: SpectralGrid, index: u32) Error!f64 {
        // SpectralGrid.sampleAt -----------------------------------------------------------------------------------------|
        // Return the wavelength for a uniform endpoint-inclusive grid index.                                             |
        //                                                                                                                |
        // math                                                                                                           |
        //   lambda_i = start_nm + i * (end_nm - start_nm) / (sample_count - 1)                                           |
        // ---------------------------------------------------------------------------------------------------------------|

        try self.validate();
        if (index >= self.sample_count) return Error.IndexOutOfRange;

        const step = (self.end_nm - self.start_nm) / @as(f64, @floatFromInt(self.sample_count - 1));
        return self.start_nm + step * @as(f64, @floatFromInt(index));
    }
};
// -----------------------------------------------------------------------------------------------------------------------|

// ResolvedAxis ----------------------------------------------------------------------------------------------------------|
// Output wavelength axis after measured-channel input has been resolved. Explicit samples override the base              |
// grid but must have exactly the same row count, so downstream product buffers keep one shared sample_count.             |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 40 B (0.039 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..23] base                    : SpectralGrid                                                                        |
// [24..39] explicit_wavelengths_nm : []const f64                                                                         |
//                                                                                                                        |
// explicit_wavelengths_nm references external storage and is not included in the 40 B struct size.                       |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 40 B (0.039 KiB); total also includes referenced storage above                               |
pub const ResolvedAxis = struct {
    base: SpectralGrid,
    explicit_wavelengths_nm: []const f64 = &.{},

    pub fn validate(self: ResolvedAxis) Error!void {
        // ResolvedAxis.validate -----------------------------------------------------------------------------------------|
        // Validate the base grid and, when measured wavelengths are present, require a strict one-to-one                 |
        // replacement for each output row.                                                                               |
        // ---------------------------------------------------------------------------------------------------------------|

        try self.base.validate();
        if (self.explicit_wavelengths_nm.len == 0) return;
        if (self.explicit_wavelengths_nm.len != self.base.sample_count) return Error.InvalidExplicitSamples;
        try validateExplicitSamples(self.explicit_wavelengths_nm);
    }

    pub fn sampleAt(self: ResolvedAxis, index: u32) Error!f64 {
        // ResolvedAxis.sampleAt -----------------------------------------------------------------------------------------|
        // Resolve one output wavelength. Measured-channel scenes use the explicit wavelength table; native               |
        // scenes fall back to the uniform SpectralGrid formula.                                                          |
        // ---------------------------------------------------------------------------------------------------------------|

        try self.validate();
        if (self.explicit_wavelengths_nm.len != 0) return sampleAtExplicit(self.explicit_wavelengths_nm, index);
        return self.base.sampleAt(index);
    }
};
// -----------------------------------------------------------------------------------------------------------------------|

pub fn validateExplicitSamples(wavelengths_nm: []const f64) Error!void {
    // validateExplicitSamples -------------------------------------------------------------------------------------------|
    // Check measured-channel wavelengths before they are used as output-grid addresses. Strictly increasing              |
    // finite samples keep interpolation, cache keys, and product ordering unambiguous.                                   |
    // -------------------------------------------------------------------------------------------------------------------|

    if (wavelengths_nm.len == 0) return error.InvalidExplicitSamples;

    var previous: ?f64 = null;
    for (wavelengths_nm) |wavelength_nm| {
        if (!std.math.isFinite(wavelength_nm)) return error.InvalidExplicitSamples;
        if (previous) |earlier| {
            if (wavelength_nm <= earlier) return error.InvalidExplicitSamples;
        }
        previous = wavelength_nm;
    }
}

pub fn sampleAtExplicit(wavelengths_nm: []const f64, index: u32) Error!f64 {
    // sampleAtExplicit --------------------------------------------------------------------------------------------------|
    // Return one already-validated measured-channel wavelength. This helper still validates its input so                 |
    // direct test and internal call sites fail before reading an invalid index.                                          |
    // -------------------------------------------------------------------------------------------------------------------|

    try validateExplicitSamples(wavelengths_nm);
    if (index >= wavelengths_nm.len) return error.IndexOutOfRange;
    return wavelengths_nm[index];
}
