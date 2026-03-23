//! Purpose:
//!   Reconstruct adding-method transport fields from composed layer state.
//!
//! Physics:
//!   Turns the accumulated layer recurrence state into upward and downward
//!   field arrays and local source summaries on the transport grid.
//!
//! Vendor:
//!   `adding` field-reconstruction stage
//!
//! Design:
//!   Field reconstruction is separated from composition so the directional
//!   recurrences can be reasoned about independently from the execution front
//!   door.
//!
//! Invariants:
//!   Top-down and surface-up field arrays must preserve the vendor ordering of
//!   levels and the Fourier-0 local-source closure behavior.
//!
//! Validation:
//!   `tests/unit/transport_adding_test.zig` and transport integration suites.

const std = @import("std");
const common = @import("../common.zig");
const composition = @import("composition.zig");
const labos = @import("../labos.zig");

const Allocator = std.mem.Allocator;

/// Purpose:
///   Hold the full top-down reconstructed field state and its per-level local
///   source summaries.
///
/// Physics:
///   Captures the directional fields after the adding recursion has been
///   resolved from the top of the column downward.
///
/// Vendor:
///   `adding` top-down field reconstruction
pub const TopDownField = struct {
    ud: []labos.UDField,
    ud_sum_local: []labos.UDLocal,

    pub fn deinit(self: TopDownField, allocator: Allocator) void {
        allocator.free(self.ud);
        allocator.free(self.ud_sum_local);
    }
};

/// Purpose:
///   Rebuild the top-down field arrays for a layered transport scene.
///
/// Physics:
///   Propagates the composed atmosphere downward to recover the full field
///   arrays and the vendor local-source accumulation at each level.
///
/// Vendor:
///   `adding::calcTopDownField`
pub fn calcTopDownField(
    allocator: Allocator,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError!TopDownField {
    const part_upper = try buildTopDownPartAtmosphere(
        allocator,
        end_level,
        i_fourier,
        atten,
        rt,
        geo,
        threshold_mul,
    );
    defer allocator.free(part_upper);

    const nlevel = end_level + 1;
    const ud = try allocator.alloc(labos.UDField, nlevel);
    errdefer allocator.free(ud);
    const ud_sum_local = try allocator.alloc(labos.UDLocal, nlevel);
    errdefer allocator.free(ud_sum_local);

    calcUD_FromTopDown(ud, part_upper, end_level, atten, geo);
    calcUDsumLocal(ud_sum_local, rt, ud, end_level, atten, geo);
    return .{
        .ud = ud,
        .ud_sum_local = ud_sum_local,
    };
}

/// Purpose:
///   Rebuild the surface-up field arrays for a layered transport scene.
///
/// Physics:
///   Propagates the composed atmosphere upward from the lower boundary to
///   recover the full directional field on the transport grid.
///
/// Vendor:
///   `adding::calcSurfaceUpField`
pub fn calcSurfaceUpField(
    allocator: Allocator,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError![]labos.UDField {
    const nlevel = end_level + 1;
    const part_lower = try allocator.alloc(composition.PartAtmosphere, nlevel);
    defer allocator.free(part_lower);
    for (part_lower) |*entry| entry.* = composition.PartAtmosphere.zero(geo.nmutot);

    const ud = try allocator.alloc(labos.UDField, nlevel);
    errdefer allocator.free(ud);

    try composition.addingFromSurfaceUp(part_lower, end_level, i_fourier, atten, rt, geo, threshold_mul);
    calcUD_FromSurfaceUp(ud, part_lower, end_level, atten, geo);
    return ud;
}

/// Purpose:
///   Materialize the top-down composed atmosphere without expanding it into
///   field arrays.
///
/// Physics:
///   Produces the intermediate layer-composition state needed by diagnostics
///   and top-down field reconstruction.
///
/// Vendor:
///   `adding::buildTopDownPartAtmosphere`
pub fn buildTopDownPartAtmosphere(
    allocator: Allocator,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError![]composition.PartAtmosphere {
    const nlevel = end_level + 1;
    const part_upper = try allocator.alloc(composition.PartAtmosphere, nlevel);
    errdefer allocator.free(part_upper);
    for (part_upper) |*entry| entry.* = composition.PartAtmosphere.zero(geo.nmutot);
    try composition.addingFromTopDown(part_upper, end_level, i_fourier, atten, rt, geo, threshold_mul);
    return part_upper;
}

fn calcUD_FromTopDown(
    ud: []labos.UDField,
    part_upper: []const composition.PartAtmosphere,
    end_level: usize,
    atten: *const labos.DynamicAttenArray,
    geo: *const labos.Geometry,
) void {
    const n = geo.nmutot;
    for (0..end_level + 1) |ilevel| {
        ud[ilevel] = .{
            .E = labos.Vec.zero(n),
            .U = labos.Vec2.zero(n),
            .D = labos.Vec2.zero(n),
        };
        for (0..n) |imu| {
            ud[ilevel].E.set(imu, atten.get(imu, end_level, ilevel));
        }
    }

    for (0..2) |imu0| {
        const col_idx = geo.n_gauss + imu0;
        for (0..n) |imu| {
            ud[0].D.col[imu0].set(imu, part_upper[0].D.get(imu, col_idx));
            ud[0].U.col[imu0].set(imu, part_upper[0].U.get(imu, col_idx));
        }
    }

    for (1..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = geo.n_gauss + imu0;
            for (0..n) |imu| {
                const down = labos.dotGauss(&part_upper[ilevel].Ust, imu, &ud[ilevel - 1].U.col[imu0], geo.n_gauss) +
                    part_upper[ilevel].D.get(imu, col_idx);
                const up = labos.dotGauss(&part_upper[ilevel].Dst, imu, &ud[ilevel - 1].U.col[imu0], geo.n_gauss) +
                    atten.get(imu, ilevel - 1, ilevel) * ud[ilevel - 1].U.col[imu0].get(imu) +
                    part_upper[ilevel].U.get(imu, col_idx);
                ud[ilevel].D.col[imu0].set(imu, down);
                ud[ilevel].U.col[imu0].set(imu, up);
            }
        }
    }
}

fn calcUDsumLocal(
    ud_sum_local: []labos.UDLocal,
    rt: []const labos.LayerRT,
    ud: []const labos.UDField,
    end_level: usize,
    atten: *const labos.DynamicAttenArray,
    geo: *const labos.Geometry,
) void {
    const n = geo.nmutot;
    for (0..end_level + 1) |ilevel| {
        ud_sum_local[ilevel] = .{
            .U = labos.Vec2.zero(n),
            .D = labos.Vec2.zero(n),
        };
    }

    ud_sum_local[0].U = ud[0].U;

    for (1..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = geo.n_gauss + imu0;
            for (0..n) |imu| {
                const local_up =
                    labos.dotGauss(&rt[ilevel].R, imu, &ud[ilevel].D.col[imu0], geo.n_gauss) +
                    labos.dotGauss(&rt[ilevel].T, imu, &ud[ilevel - 1].U.col[imu0], geo.n_gauss) +
                    rt[ilevel].R.get(imu, col_idx) * atten.get(col_idx, end_level, ilevel);
                ud_sum_local[ilevel].U.col[imu0].set(imu, local_up);
            }
        }
    }
}

fn calcUD_FromSurfaceUp(
    ud: []labos.UDField,
    part_lower: []const composition.PartAtmosphere,
    end_level: usize,
    atten: *const labos.DynamicAttenArray,
    geo: *const labos.Geometry,
) void {
    const n = geo.nmutot;
    for (0..end_level + 1) |ilevel| {
        ud[ilevel] = .{
            .E = labos.Vec.zero(n),
            .U = labos.Vec2.zero(n),
            .D = labos.Vec2.zero(n),
        };
        for (0..n) |imu| {
            ud[ilevel].E.set(imu, atten.get(imu, end_level, ilevel));
        }
    }

    for (0..n) |imu| {
        ud[end_level].E.set(imu, 1.0);
    }
    ud[end_level].D = labos.Vec2.zero(n);
    for (0..2) |imu0| {
        const col_idx = geo.n_gauss + imu0;
        for (0..n) |imu| {
            ud[end_level].U.col[imu0].set(imu, part_lower[end_level].R.get(imu, col_idx));
        }
    }

    var ilevel = end_level;
    while (ilevel > 0) {
        ilevel -= 1;
        for (0..2) |imu0| {
            const col_idx = geo.n_gauss + imu0;
            const direct_att = atten.get(col_idx, end_level, ilevel + 1);
            for (0..n) |imu| {
                const down = labos.dotGauss(&part_lower[ilevel + 1].D, imu, &ud[ilevel + 1].D.col[imu0], geo.n_gauss) +
                    atten.get(imu, ilevel, ilevel + 1) * ud[ilevel + 1].D.col[imu0].get(imu) +
                    part_lower[ilevel + 1].D.get(imu, col_idx) * direct_att;
                const up = labos.dotGauss(&part_lower[ilevel + 1].U, imu, &ud[ilevel + 1].D.col[imu0], geo.n_gauss) +
                    part_lower[ilevel + 1].U.get(imu, col_idx) * direct_att;
                ud[ilevel].D.col[imu0].set(imu, down);
                ud[ilevel].U.col[imu0].set(imu, up);
            }
        }
    }
}
