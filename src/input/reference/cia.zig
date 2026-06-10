const std = @import("std");
const cross_sections = @import("cross_sections.zig");
const spline = @import("../../common/math/interpolation/spline.zig");
const Allocator = std.mem.Allocator;

const max_spline_window_points: usize = 256;

// cia.zig ----------------------------------------------------------------------------------------------------|
// O2-O2 collision-induced absorption table sampling for prepared optical state and CIA diagnostics.           |
//                                                                                                             |
// called by                                                                                                   |
//   ReferenceData.zig re-exports the point/table types used by input models and tests.                        |
//   input/reference_data/ingest, bundled loaders, fixed_asset_cache, and o2a_reference/run.zig load or retain |
//   O2-O2 CIA assets before optical-state preparation begins.                                                 |
//   optical_properties/state_build/context.zig borrows or clones the table into PreparedOpticalState;         |
//   state_spectroscopy.zig, layer_accumulation.zig, and state_optical_depth.zig sample it for support rows,   |
//   layer means, and temperature derivative paths.                                                            |
//   input/instrument/cross_section_lut.zig can fold this table into operational LUT products, while           |
//   output/o2_o2_cia.zig reports the same sampled quantities as diagnostics.                                  |
//                                                                                                             |
// main paths                                                                                                  |
//   sigmaAt evaluates one wavelength/temperature sample from interpolated a0/a1/a2 coefficients.              |
//   dSigmaDTemperatureAt returns the derivative of the clamped temperature polynomial when the raw sigma is   |
//   positive. meanSigmaInRange scans stored points for setup-time interval means.                             |
//   effectiveSigmaAtSamples builds a differential CIA vector by sampling every instrument wavelength and      |
//   delegating polynomial baseline removal to cross_sections.zig.                                             |
//                                                                                                             |
// runtime shape                                                                                               |
//   CollisionInducedAbsorptionTable is a small header over sorted out-of-line coefficient rows plus a unit    |
//   scale. clone/deinit own that storage when the prepared state needs to retain it; borrowed tables stay     |
//   under their input/reference-data owner.                                                                   |
//                                                                                                             |
// hot path                                                                                                    |
//   Support-row evaluation repeatedly calls sigmaAt and the temperature derivative. Coefficient interpolation |
//   uses bounded stack windows and no heap allocation; only clone and effectiveSigmaAtSamples allocate.       |
//                                                                                                             |
// units                                                                                                       |
//   scale_factor_cm5_per_molecule2 converts the table coefficients into cm5 per molecule^2.                   |
// ------------------------------------------------------------------------------------------------------------|

// CollisionInducedAbsorptionPoint ----------------------------------------------------------------------------|
// One CIA coefficient row.                                                                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm : f64                                                                                |
// [ 8..15] a0            : f64                                                                                |
// [16..23] a1            : f64                                                                                |
// [24..31] a2            : f64                                                                                |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total = per instance * live point count                         |
pub const CollisionInducedAbsorptionPoint = struct {
    wavelength_nm: f64,
    a0: f64,
    a1: f64,
    a2: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// CollisionInducedAbsorptionTable ----------------------------------------------------------------------------|
// Owner header for CIA coefficient rows.                                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] scale_factor_cm5_per_molecule2 : f64                                                               |
// [ 8..23] points                         : []const CollisionInducedAbsorptionPoint                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   points stores out-of-line CIA coefficient rows and is released by deinit.                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 24 B (0.023 KiB); total also includes owned point rows                            |
pub const CollisionInducedAbsorptionTable = struct {
    scale_factor_cm5_per_molecule2: f64,
    points: []const CollisionInducedAbsorptionPoint,

    pub fn deinit(self: *CollisionInducedAbsorptionTable, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    pub fn clone(self: CollisionInducedAbsorptionTable, allocator: Allocator) !CollisionInducedAbsorptionTable {
        return .{
            .scale_factor_cm5_per_molecule2 = self.scale_factor_cm5_per_molecule2,
            .points = try allocator.dupe(CollisionInducedAbsorptionPoint, self.points),
        };
    }

    pub fn sigmaAt(self: CollisionInducedAbsorptionTable, wavelength_nm: f64, temperature_k: f64) f64 {
        // CollisionInducedAbsorptionTable.sigmaAt ------------------------------------------------------------|
        // Evaluate CIA sigma for one wavelength and temperature.                                              |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : support-row carrier evaluation when O2-O2 CIA absorption is enabled                    |
        //   work     : interpolate coefficients and evaluate a quadratic temperature polynomial               |
        //   memory   : reads a small coefficient window, then returns one scalar                              |
        // ----------------------------------------------------------------------------------------------------|

        const coefficients = self.interpolateCoefficients(wavelength_nm);
        const temperature_c = temperature_k - 273.15;
        const raw_sigma = coefficients.a0 +
            coefficients.a1 * temperature_c +
            coefficients.a2 * temperature_c * temperature_c;
        return self.scale_factor_cm5_per_molecule2 * @max(raw_sigma, 0.0);
    }

    pub fn dSigmaDTemperatureAt(
        self: CollisionInducedAbsorptionTable,
        wavelength_nm: f64,
        temperature_k: f64,
    ) f64 {
        const coefficients = self.interpolateCoefficients(wavelength_nm);
        const temperature_c = temperature_k - 273.15;
        const raw_sigma = coefficients.a0 +
            coefficients.a1 * temperature_c +
            coefficients.a2 * temperature_c * temperature_c;
        if (raw_sigma <= 0.0) return 0.0;
        return self.scale_factor_cm5_per_molecule2 *
            (coefficients.a1 + 2.0 * coefficients.a2 * temperature_c);
    }

    pub fn meanSigmaInRange(
        self: CollisionInducedAbsorptionTable,
        start_nm: f64,
        end_nm: f64,
        temperature_k: f64,
    ) f64 {
        var total: f64 = 0.0;
        var count: usize = 0;
        for (self.points) |point| {
            if (point.wavelength_nm < start_nm or point.wavelength_nm > end_nm) continue;
            total += self.sigmaAt(point.wavelength_nm, temperature_k);
            count += 1;
        }

        if (count > 0) return total / @as(f64, @floatFromInt(count));
        return self.sigmaAt((start_nm + end_nm) * 0.5, temperature_k);
    }

    pub fn interpolateCoefficients(
        self: CollisionInducedAbsorptionTable,
        wavelength_nm: f64,
    ) CollisionInducedAbsorptionPoint {
        // CollisionInducedAbsorptionTable.interpolateCoefficients --------------------------------------------|
        // Bracket the CIA table and interpolate the a0/a1/a2 coefficient triplet.                             |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : sigma and temperature-derivative samples for CIA wavelengths                           |
        //   work     : lower-bound search, bounded spline window, or two-point linear fallback                |
        //   memory   : stack window arrays are capped by max_spline_window_points                             |
        // ----------------------------------------------------------------------------------------------------|

        if (self.points.len == 0) {
            return .{
                .wavelength_nm = wavelength_nm,
                .a0 = 0.0,
                .a1 = 0.0,
                .a2 = 0.0,
            };
        }

        if (wavelength_nm <= self.points[0].wavelength_nm) return self.points[0];
        if (wavelength_nm >= self.points[self.points.len - 1].wavelength_nm) {
            return self.points[self.points.len - 1];
        }

        const right_index = lowerBoundPointIndex(self.points, wavelength_nm);
        const window = splineWindow(self.points.len, right_index);

        if (window.count >= 3) {
            const points = self.points[window.start .. window.start + window.count];
            return .{
                .wavelength_nm = wavelength_nm,
                .a0 = sampleCoefficientSpline(points, wavelength_nm, .a0),
                .a1 = sampleCoefficientSpline(points, wavelength_nm, .a1),
                .a2 = sampleCoefficientSpline(points, wavelength_nm, .a2),
            };
        }
        return interpolateCoefficientsLinear(self.points[right_index - 1], self.points[right_index], wavelength_nm);
    }
};
// ------------------------------------------------------------------------------------------------------------|

const CoefficientKind = enum { a0, a1, a2 };

// SplineWindow -----------------------------------------------------------------------------------------------|
// Bounded coefficient-window descriptor for stack spline sampling.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] start : usize                                                                                       |
// [8..15] count : usize                                                                                       |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per stack/local value count                             |
const SplineWindow = struct {
    start: usize,
    count: usize,
};

fn splineWindow(point_count: usize, right_index: usize) SplineWindow {
    const count = @min(point_count, max_spline_window_points);
    if (point_count <= max_spline_window_points) return .{ .start = 0, .count = count };

    const half_window = max_spline_window_points / 2;
    var start: usize = if (right_index > half_window) right_index - half_window else 0;
    if (start + count > point_count) start = point_count - count;
    return .{ .start = start, .count = count };
}

fn sampleCoefficientSpline(
    points: []const CollisionInducedAbsorptionPoint,
    wavelength_nm: f64,
    coefficient_kind: CoefficientKind,
) f64 {
    // sampleCoefficientSpline --------------------------------------------------------------------------------|
    // Copy one coefficient window into stack arrays and sample the endpoint-secant spline.                    |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : CIA coefficient interpolation when the local window has at least three points              |
    //   work     : copy wavelength and one selected coefficient field, then call spline.sampleEndpointSecant  |
    //   memory   : x and y stack arrays are capped at max_spline_window_points f64 values each                |
    // --------------------------------------------------------------------------------------------------------|

    var x: [max_spline_window_points]f64 = undefined;
    var y: [max_spline_window_points]f64 = undefined;
    for (points, 0..) |point, index| {
        x[index] = point.wavelength_nm;
        y[index] = switch (coefficient_kind) {
            .a0 => point.a0,
            .a1 => point.a1,
            .a2 => point.a2,
        };
    }
    return spline.sampleEndpointSecant(x[0..points.len], y[0..points.len], wavelength_nm) catch unreachable;
}

fn interpolateCoefficientsLinear(
    left: CollisionInducedAbsorptionPoint,
    right: CollisionInducedAbsorptionPoint,
    wavelength_nm: f64,
) CollisionInducedAbsorptionPoint {
    const span = right.wavelength_nm - left.wavelength_nm;
    if (span == 0.0) return right;
    const weight = (wavelength_nm - left.wavelength_nm) / span;
    return .{
        .wavelength_nm = wavelength_nm,
        .a0 = left.a0 + weight * (right.a0 - left.a0),
        .a1 = left.a1 + weight * (right.a1 - left.a1),
        .a2 = left.a2 + weight * (right.a2 - left.a2),
    };
}

fn lowerBoundPointIndex(points: []const CollisionInducedAbsorptionPoint, wavelength_nm: f64) usize {
    var low: usize = 0;
    var high: usize = points.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (points[middle].wavelength_nm < wavelength_nm) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low;
}

pub fn effectiveSigmaAtSamples(
    allocator: Allocator,
    table: CollisionInducedAbsorptionTable,
    wavelengths_nm: []const f64,
    temperature_k: f64,
    weights: []const f64,
    polynomial_order: u32,
) ![]f64 {
    // effectiveSigmaAtSamples --------------------------------------------------------------------------------|
    // Build a differential CIA sigma vector over instrument samples.                                          |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : output or preprocessing evaluates effective CIA over sample wavelengths                    |
    //   work     : evaluate sigma for each sample, then remove a weighted polynomial baseline                 |
    //   memory   : sigma scratch is one f64 per wavelength before cross_sections.differentialVector owns      |
    //              the returned result                                                                        |
    // --------------------------------------------------------------------------------------------------------|

    if (wavelengths_nm.len != weights.len) return error.ShapeMismatch;

    const sigma = try allocator.alloc(f64, wavelengths_nm.len);
    defer allocator.free(sigma);
    for (sigma, wavelengths_nm) |*slot, wavelength_nm| {
        slot.* = table.sigmaAt(wavelength_nm, temperature_k);
    }
    return cross_sections.differentialVector(allocator, wavelengths_nm, sigma, weights, polynomial_order);
}
