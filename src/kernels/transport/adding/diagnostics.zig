//! Purpose:
//!   Produce vendor-shaped diagnostics from the adding-method composition
//!   state.
//!
//! Physics:
//!   Derives the top-down boundary quantities used to compare local source,
//!   attenuation, and surface-reflection behavior against the vendor layout.
//!
//! Vendor:
//!   `adding` boundary diagnostics
//!
//! Design:
//!   Diagnostics are separated from field reconstruction so the boundary view
//!   can be queried without materializing the full surface-up state.
//!
//! Invariants:
//!   Fourier-0 diagnostics expose scalar source terms; higher Fourier orders
//!   must zero the scalar summary fields.
//!
//! Validation:
//!   `tests/unit/transport_adding_test.zig` and transport integration suites.

const std = @import("std");
const common = @import("../common.zig");
const fields = @import("fields.zig");
const labos = @import("../labos.zig");

/// Purpose:
///   Capture the vendor-style top-down boundary diagnostics for one level.
///
/// Physics:
///   Returns the black-surface matrix and local transport summaries that
///   characterize the composed atmosphere at the requested boundary level.
///
/// Vendor:
///   `adding::calcTopDownBoundarySurfaceDiagnostics`
pub const BoundarySurfaceDiagnostics = struct {
    r0: labos.Mat,
    td: labos.Vec,
    expt: labos.Vec,
    s_star: f64,
};

/// Purpose:
///   Compute the top-down boundary diagnostics at a chosen level.
///
/// Physics:
///   Extracts the vendor-style black-surface matrix, top-down source term, and
///   attenuation summaries from the composed atmosphere at the requested level.
///
/// Vendor:
///   `adding::calcTopDownBoundarySurfaceDiagnostics`
pub fn calcTopDownBoundarySurfaceDiagnostics(
    allocator: std.mem.Allocator,
    level: usize,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError!BoundarySurfaceDiagnostics {
    if (level > end_level) return error.UnsupportedRtmControls;

    const part_upper = try fields.buildTopDownPartAtmosphere(
        allocator,
        end_level,
        i_fourier,
        atten,
        rt,
        geo,
        threshold_mul,
    );
    defer allocator.free(part_upper);

    var r0 = labos.Mat.zero(geo.nmutot);
    for (0..geo.nmutot) |imu| {
        for (0..geo.nmutot) |imu0| {
            r0.set(
                imu,
                imu0,
                part_upper[level].R.get(imu, imu0) / @max(geo.w[imu] * geo.w[imu0], 1.0e-12),
            );
        }
    }

    var td = labos.Vec.zero(geo.nmutot);
    var expt = labos.Vec.zero(geo.nmutot);
    var s_star: f64 = 0.0;
    if (i_fourier == 0) {
        td = part_upper[level].tpl;
        s_star = part_upper[level].sst;
        for (0..geo.nmutot) |imu| {
            expt.set(imu, atten.get(imu, end_level, level));
        }
    }

    return .{
        .r0 = r0,
        .td = td,
        .expt = expt,
        .s_star = s_star,
    };
}
