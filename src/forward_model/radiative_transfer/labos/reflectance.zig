const std = @import("std");
const basis = @import("basis.zig");
const common = @import("../root.zig");

const math = std.math;

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: zplus=16 B, zmin=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: zplus, zmin carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above
const PhaseRows = struct {
    zplus: []const f64,
    zmin: []const f64,
};

// layout(64-bit):
//   size: 2408 B, align: 8 B
//   field storage: rows=2400 B, n=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: n=8 B
//   inline arrays: rows:[12]src.forward_model.radiative_transfer.labos.phase_basis.PhaseKernelRow=2400 B
//   cache span: 38 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 2408 B (2.352 KiB); total = per instance * live instance count
const PhaseRowCache = struct {
    rows: [basis.max_nmutot]basis.PhaseKernelRow,
    n: usize,
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: coefficients=8 B, max_index=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: coefficients points at prepared phase storage; referenced storage is not included in size
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
const UnitPhase = struct {
    coefficients: *const [basis.max_phase_coef]f64,
    max_index: usize,
};

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: pplusplus_ed=8 B, pminplus_ed=8 B, pminmin_u=8 B, pplusmin_u=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count
const ScatteringSourceRowSums = struct {
    pplusplus_ed: f64,
    pminplus_ed: f64,
    pminmin_u: f64,
    pplusmin_u: f64,
};

fn sourceInterfaceAtLevelPtr(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    ilevel: usize,
) ?*const common.SourceInterfaceInput {
    if (source_interfaces.len == layers.len + 1 and ilevel < source_interfaces.len) {
        return &source_interfaces[ilevel];
    }
    return null;
}

fn maxPhaseCoefficientIndex(phase_coefficients: *const [basis.max_phase_coef]f64) usize {
    var max_index: usize = 0;
    for (1..basis.max_phase_coef) |idx| {
        if (@abs(phase_coefficients[idx]) > 1.0e-12) {
            max_index = idx;
        }
    }
    return max_index;
}

fn maxWeightedPhaseCoefficientIndex(
    aerosol_weight: f64,
    cloud_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefficients: *const [basis.max_phase_coef]f64,
    cloud_phase_coefficients: *const [basis.max_phase_coef]f64,
) usize {
    var max_index: usize = 0;
    if (@abs(rayleigh2_weight) > 1.0e-12) max_index = 2;
    if (@abs(aerosol_weight) > 1.0e-12) {
        max_index = @max(max_index, maxPhaseCoefficientIndex(aerosol_phase_coefficients));
    }
    if (@abs(cloud_weight) > 1.0e-12) {
        max_index = @max(max_index, maxPhaseCoefficientIndex(cloud_phase_coefficients));
    }
    return max_index;
}

fn maxRtmQuadraturePhaseCoefficientIndex(
    level: *const common.RtmQuadratureLevel,
    rtm_quadrature: common.RtmQuadratureGrid,
) usize {
    return maxWeightedPhaseCoefficientIndex(
        level.phase_aerosol_weight,
        level.phase_cloud_weight,
        level.phase_rayleigh2_weight,
        rtm_quadrature.aerosol_phase_coefficients,
        rtm_quadrature.cloud_phase_coefficients,
    );
}

fn fillRtmQuadraturePhaseRow(
    rtm_quadrature: common.RtmQuadratureGrid,
    level: *const common.RtmQuadratureLevel,
    i_fourier: usize,
    max_phase_index: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    row_index: usize,
) basis.PhaseKernelRow {
    return basis.fillZplusZminRowFromWeightedPhaseLimited(
        i_fourier,
        level.phase_aerosol_weight,
        level.phase_cloud_weight,
        level.phase_rayleigh2_weight,
        rtm_quadrature.aerosol_phase_coefficients,
        rtm_quadrature.cloud_phase_coefficients,
        max_phase_index,
        geo,
        plm_basis,
        row_index,
    );
}

fn maxInterfacePhaseCoefficientIndex(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    ilevel: usize,
) usize {
    var fallback_source_interface: common.SourceInterfaceInput = undefined;
    const source_interface = sourceInterfaceAtLevelPtr(layers, source_interfaces, ilevel) orelse blk: {
        fallback_source_interface = common.sourceInterfaceFromLayers(layers, ilevel);
        break :blk &fallback_source_interface;
    };
    const above_max = maxPhaseCoefficientIndex(&source_interface.phase_coefficients_above);
    const below_max = source_interface.phase_max_index_below;
    if (layers.len == 0 or ilevel == 0 or ilevel > layers.len - 1) return @max(above_max, below_max);
    return @max(above_max, below_max);
}

fn adjacentLayerPhaseCoefficientIndex(
    layers: []const common.LayerInput,
    ilevel: usize,
) usize {
    if (layers.len == 0) return 0;
    if (ilevel == 0) return maxPhaseCoefficientIndex(&layers[0].phase_coefficients);
    if (ilevel >= layers.len) return maxPhaseCoefficientIndex(&layers[layers.len - 1].phase_coefficients);
    return @max(
        maxPhaseCoefficientIndex(&layers[ilevel - 1].phase_coefficients),
        maxPhaseCoefficientIndex(&layers[ilevel].phase_coefficients),
    );
}

pub fn fillAdjacentLayerPhaseMaxIndices(
    source_phase_max_indices: []usize,
    layer_phase_max_indices: []const usize,
) void {
    const nlayer = layer_phase_max_indices.len;
    std.debug.assert(source_phase_max_indices.len >= nlayer + 1);
    if (nlayer == 0) {
        if (source_phase_max_indices.len != 0) source_phase_max_indices[0] = 0;
        return;
    }

    source_phase_max_indices[0] = layer_phase_max_indices[0];
    for (1..nlayer) |ilevel| {
        source_phase_max_indices[ilevel] = @max(
            layer_phase_max_indices[ilevel - 1],
            layer_phase_max_indices[ilevel],
        );
    }
    source_phase_max_indices[nlayer] = layer_phase_max_indices[nlayer - 1];
}

fn reuseLayerKernelIndex(
    layers: []const common.LayerInput,
    source_interface: *const common.SourceInterfaceInput,
    ilevel: usize,
) ?usize {
    if (layers.len == 0) return null;
    const above_index = @min(ilevel, layers.len - 1);
    if (!std.mem.eql(
        f64,
        source_interface.phase_coefficients_above[0..],
        layers[above_index].phase_coefficients[0..],
    )) {
        return null;
    }
    return above_index;
}

pub fn calcReflectance(
    ud: []const basis.UDField,
    end_level: usize,
    geo: *const basis.Geometry,
) f64 {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    return ud[end_level].U.col[solar_col].get(view_idx);
}

pub fn calcReflectanceTangent(
    ud_tangent: []const basis.UDField,
    end_level: usize,
    geo: *const basis.Geometry,
) f64 {
    return calcReflectance(ud_tangent, end_level, geo);
}

pub fn calcIntegratedReflectance(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    end_level: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
) f64 {
    const max_phase_index = if (rtm_quadrature.isValidFor(layers.len))
        @max(maxFourierIndex(layers), maxFourierIndexQuadrature(rtm_quadrature))
    else
        @max(maxFourierIndex(layers), maxFourierIndexInterfaces(source_interfaces));
    const plm_basis = basis.FourierPlmBasis.init(i_fourier, max_phase_index, geo);
    return calcIntegratedReflectanceWithBasis(
        layers,
        source_interfaces,
        rtm_quadrature,
        ud,
        end_level,
        i_fourier,
        geo,
        &plm_basis,
        null,
        null,
        null,
    );
}

// hot path:
//   when: after each LABOS Fourier/order solve contributes to top-of-atmosphere reflectance
//   work: integrates reflectance over levels, phase rows, and Gauss stream reductions
//   data: layer inputs, order contribution arrays, phase rows, attenuation arrays
//   follow: buildPhaseRowCache and scattering-source weighting callers
pub fn calcIntegratedReflectanceWithBasis(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    end_level: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    adjacent_layer_phase_max_indices: ?[]const usize,
    layer_phase_row_cache: ?[]const basis.PhaseKernelRow,
    layer_phase_row_valid: ?[]const bool,
) f64 {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const view_mu = @max(geo.u[view_idx], 1.0e-12);
    var reflectance: f64 = 0.0;
    const use_rtm_quadrature = rtm_quadrature.isValidFor(layers.len);

    for (0..end_level + 1) |ilevel| {
        var fallback_source_interface: common.SourceInterfaceInput = undefined;
        const source_interface = if (use_rtm_quadrature)
            null
        else
            sourceInterfaceAtLevelPtr(layers, source_interfaces, ilevel) orelse blk: {
                fallback_source_interface = common.sourceInterfaceFromLayers(layers, ilevel);
                break :blk &fallback_source_interface;
            };
        const source_rtm_weight = if (use_rtm_quadrature)
            rtm_quadrature.levels[ilevel].weight
        else if (source_interface.?.rtm_weight > 0.0 and source_interface.?.ksca_above > 0.0)
            source_interface.?.rtm_weight
        else
            source_interface.?.source_weight;
        const source_ksca = if (use_rtm_quadrature)
            rtm_quadrature.levels[ilevel].ksca
        else if (source_interface.?.rtm_weight > 0.0 and source_interface.?.ksca_above > 0.0)
            source_interface.?.ksca_above
        else
            1.0;
        if (source_rtm_weight <= 0.0 or source_ksca <= 0.0) continue;
        const source_max_phase_index = if (adjacent_layer_phase_max_indices) |indices|
            indices[ilevel]
        else if (layers.len != 0)
            adjacentLayerPhaseCoefficientIndex(layers, ilevel)
        else if (use_rtm_quadrature)
            maxRtmQuadraturePhaseCoefficientIndex(&rtm_quadrature.levels[ilevel], rtm_quadrature)
        else
            maxInterfacePhaseCoefficientIndex(layers, source_interfaces, ilevel);
        if (i_fourier > source_max_phase_index) {
            // PARITY:
            //   DISAMAR gates an integrated-source level by the max phase
            //   order of its adjacent reduced layers, then uses the interface
            //   carrier only up to that same ceiling.
            continue;
        }

        var computed_row: basis.PhaseKernelRow = undefined;
        const phase_rows: PhaseRows = blk: {
            if (!use_rtm_quadrature) {
                if (reuseLayerKernelIndex(layers, source_interface.?, ilevel)) |above_index| {
                    if (layer_phase_row_cache) |cache| {
                        if (layer_phase_row_valid) |valid| {
                            const cache_index = above_index + 1;
                            if (cache_index < cache.len and cache_index < valid.len and valid[cache_index]) {
                                const row = &cache[cache_index];
                                break :blk PhaseRows{
                                    .zplus = row.zplus[0..row.n],
                                    .zmin = row.zmin[0..row.n],
                                };
                            }
                        }
                    }
                }
            }
            computed_row = if (use_rtm_quadrature)
                fillRtmQuadraturePhaseRow(
                    rtm_quadrature,
                    &rtm_quadrature.levels[ilevel],
                    i_fourier,
                    source_max_phase_index,
                    geo,
                    plm_basis,
                    view_idx,
                )
            else
                basis.fillZplusZminRowFromBasisLimited(
                    i_fourier,
                    &source_interface.?.phase_coefficients_above,
                    source_max_phase_index,
                    geo,
                    plm_basis,
                    view_idx,
                );
            break :blk PhaseRows{
                .zplus = computed_row.zplus[0..computed_row.n],
                .zmin = computed_row.zmin[0..computed_row.n],
            };
        };

        var pmin_ed: f64 = 0.0;

        const level = ud[ilevel];
        const level_d = level.D.col[solar_col].data;
        const level_u = level.U.col[solar_col].data;
        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], 1.0e-12);
            const pmin = (0.25 * phase_rows.zmin[imu] / view_mu) / mu;
            pmin_ed += pmin * level_d[imu];
        }

        const solar_mu = @max(geo.u[solar_idx], 1.0e-12);
        const pmin_direct = (0.25 * phase_rows.zmin[solar_idx] / view_mu) / solar_mu;
        pmin_ed += pmin_direct * level.E.data[solar_idx];

        var pplusst_u: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], 1.0e-12);
            const pplusst = (0.25 * phase_rows.zplus[imu] / view_mu) / mu;
            pplusst_u += pplusst * level_u[imu];
        }

        // PARITY: `LabosModule::CalcReflectance` forms the level source as
        // `E * ksca * (...)`, then applies `RTMweight` in a separate reduction.
        const contribution = level.E.data[view_idx] *
            source_ksca *
            (pmin_ed + pplusst_u);
        reflectance += source_rtm_weight * contribution;
    }

    if (i_fourier == 0) {
        // PARITY:
        //   Keep the vendor scalar direct term in the zero-Fourier closure.
        reflectance += ud[0].E.get(view_idx) * ud[0].U.col[solar_col].get(view_idx);
    }

    return reflectance;
}

// hot path:
//   when: aerosol/cloud optical-depth Jacobians include absorption-interface weighting
//   work: reduces Gauss source terms and pseudo-spherical direct attenuation into one weighting value
//   data: order fields, layer inputs, attenuation arrays, geometry, layer index
//   follow: calcAerosolOpticalDepthWeightingWithBasis and active derivative rows
fn absorptionInterfaceWeighting(
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    rtm_quadrature: common.RtmQuadratureGrid,
    ilevel: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
) f64 {
    const view_col: usize = 0;
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const level = ud[ilevel];
    var sum: f64 = 0.0;
    for (0..geo.n_gauss) |i_gauss| {
        const mu = @max(geo.u[i_gauss], 1.0e-12);
        sum -= (level.U.col[view_col].get(i_gauss) * level.D.col[solar_col].get(i_gauss) +
            level.D.col[view_col].get(i_gauss) * level.U.col[solar_col].get(i_gauss)) / mu;
    }
    sum -= level.U.col[solar_col].get(view_idx) * level.E.get(view_idx) /
        @max(geo.u[view_idx], 1.0e-12);
    if (use_pseudo_spherical and
        ud_sum_local.len >= ud.len and
        rtm_quadrature.levels.len >= ud.len)
    {
        const earth_radius_km = 6371.0;
        const solar_mu = @max(geo.u[solar_idx], 1.0e-12);
        const y_k = earth_radius_km + rtm_quadrature.levels[ilevel].altitude_km;
        var pseudo_direct_sum: f64 = 0.0;
        var level_index = ilevel + 1;
        while (level_index > 0) {
            level_index -= 1;
            const y_l = earth_radius_km + rtm_quadrature.levels[level_index].altitude_km;
            const denominator = @sqrt(@abs(y_k * y_k - y_l * y_l * (1.0 - solar_mu * solar_mu)));
            const solar_slant_inverse = if (denominator > 0.0) y_k / denominator else 0.0;
            pseudo_direct_sum += ud_sum_local[level_index].U.col[view_col].get(solar_idx) *
                ud[level_index].E.get(solar_idx) *
                solar_slant_inverse;
        }
        sum -= pseudo_direct_sum;
    } else {
        sum -= level.U.col[view_col].get(solar_idx) * level.E.get(solar_idx) /
            @max(geo.u[solar_idx], 1.0e-12);
    }
    return sum;
}

inline fn scatteringSourceRowSums(
    scaled_phase_coefficients: *const [basis.max_phase_coef]f64,
    max_phase_index: usize,
    level: *const basis.UDField,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    row_index: usize,
) ScatteringSourceRowSums {
    const solar_col: usize = 1;
    const solar_idx = geo.n_gauss + 1;
    const rows = basis.fillZplusZminRowFromBasisLimited(
        i_fourier,
        scaled_phase_coefficients,
        max_phase_index,
        geo,
        plm_basis,
        row_index,
    );
    const mu_row = @max(geo.u[row_index], 1.0e-12);
    var sums = ScatteringSourceRowSums{
        .pplusplus_ed = 0.0,
        .pminplus_ed = 0.0,
        .pminmin_u = 0.0,
        .pplusmin_u = 0.0,
    };
    for (0..geo.n_gauss) |imu| {
        const mu_col = @max(geo.u[imu], 1.0e-12);
        const pplus = (0.25 * rows.zplus[imu] / mu_row) / mu_col;
        const pmin = (0.25 * rows.zmin[imu] / mu_row) / mu_col;
        sums.pplusplus_ed += pplus * level.D.col[solar_col].get(imu);
        sums.pminplus_ed += pmin * level.D.col[solar_col].get(imu);
        sums.pminmin_u += pplus * level.U.col[solar_col].get(imu);
        sums.pplusmin_u += pmin * level.U.col[solar_col].get(imu);
    }
    const mu_solar = @max(geo.u[solar_idx], 1.0e-12);
    const pplus_direct = (0.25 * rows.zplus[solar_idx] / mu_row) / mu_solar;
    const pmin_direct = (0.25 * rows.zmin[solar_idx] / mu_row) / mu_solar;
    sums.pplusplus_ed += pplus_direct * level.E.get(solar_idx);
    sums.pminplus_ed += pmin_direct * level.E.get(solar_idx);
    return sums;
}

// hot path:
//   when: active aerosol/cloud scattering-source weighting columns are assembled
//   work: reduces scaled phase rows into Jacobian source weighting terms
//   data: phase row cache, source row sums, Gauss weights, derivative output row
//   follow: scatteringSourceWeightingFromPhaseRows and buildPhaseRowCache
fn scatteringSourceWeightingFromScaledPhase(
    scaled_phase_coefficients: *const [basis.max_phase_coef]f64,
    max_phase_index: usize,
    ud: []const basis.UDField,
    ilevel: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) f64 {
    const view_col: usize = 0;
    const view_idx = geo.viewIdx();
    const level = &ud[ilevel];

    var sum: f64 = 0.0;
    for (0..geo.n_gauss) |row_index| {
        const row = scatteringSourceRowSums(
            scaled_phase_coefficients,
            max_phase_index,
            level,
            i_fourier,
            geo,
            plm_basis,
            row_index,
        );
        sum += level.D.col[view_col].get(row_index) * (row.pminplus_ed + row.pminmin_u) +
            level.U.col[view_col].get(row_index) * (row.pplusplus_ed + row.pplusmin_u);
    }
    const view_row = scatteringSourceRowSums(
        scaled_phase_coefficients,
        max_phase_index,
        level,
        i_fourier,
        geo,
        plm_basis,
        view_idx,
    );
    sum += level.E.get(view_idx) * (view_row.pminplus_ed + view_row.pminmin_u);
    return sum;
}

fn aerosolInterfaceWeightingFromScaledPhase(
    scaled_phase_coefficients: *const [basis.max_phase_coef]f64,
    ud: []const basis.UDField,
    ilevel: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) f64 {
    const d_sca_d_altitude = scaled_phase_coefficients[0];
    if (d_sca_d_altitude == 0.0) return 0.0;
    const max_phase_index = maxPhaseCoefficientIndex(scaled_phase_coefficients);
    if (i_fourier > max_phase_index) return 0.0;
    return scatteringSourceWeightingFromScaledPhase(
        scaled_phase_coefficients,
        max_phase_index,
        ud,
        ilevel,
        i_fourier,
        geo,
        plm_basis,
    ) + d_sca_d_altitude * absorptionInterfaceWeighting(ud, &.{}, .{}, ilevel, false, geo);
}

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: bottom=8 B, top=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
const AerosolIntervalBounds = struct {
    bottom: usize,
    top: usize,
};

fn activeAerosolInteriorBounds(
    rtm_quadrature: common.RtmQuadratureGrid,
    end_level: usize,
) ?AerosolIntervalBounds {
    var first_active: ?usize = null;
    var last_active: ?usize = null;
    for (0..end_level + 1) |ilevel| {
        if (rtm_quadrature.levels[ilevel].aerosol_ksca_jacobian <= 0.0) continue;
        if (first_active == null) first_active = ilevel;
        last_active = ilevel;
    }
    const first = first_active orelse return null;
    const last = last_active orelse return null;
    if (first == 0 or last + 1 > end_level) return null;
    return .{ .bottom = first - 1, .top = last + 1 };
}

fn aerosolSingleScatteringAlbedo(layers: []const common.LayerInput) f64 {
    var aerosol_optical_depth: f64 = 0.0;
    var aerosol_scattering_optical_depth: f64 = 0.0;
    for (layers) |*layer| {
        aerosol_optical_depth += @max(layer.aerosol_optical_depth, 0.0);
        aerosol_scattering_optical_depth += @max(layer.aerosol_scattering_optical_depth, 0.0);
    }
    if (aerosol_optical_depth <= 0.0) return 1.0;
    return math.clamp(aerosol_scattering_optical_depth / aerosol_optical_depth, 0.0, 1.0);
}

fn unitAerosolPhase(rtm_quadrature: common.RtmQuadratureGrid) ?UnitPhase {
    const coefficients = rtm_quadrature.aerosol_phase_coefficients;
    if (coefficients[0] <= 0.0) return null;
    return .{
        .coefficients = coefficients,
        .max_index = maxPhaseCoefficientIndex(coefficients),
    };
}

fn commonActiveAerosolUnitPhase(
    rtm_quadrature: common.RtmQuadratureGrid,
    bounds: AerosolIntervalBounds,
) ?UnitPhase {
    for (bounds.bottom..bounds.top) |ilevel| {
        if (rtm_quadrature.levels[ilevel].aerosol_ksca_above_per_km > 0.0) return unitAerosolPhase(rtm_quadrature);
    }
    return null;
}

// hot path:
//   when: reflectance or Jacobian weighting reuses phase rows for one layer/Fourier term
//   work: materializes Z+/Z- phase rows and row sums into a compact cache
//   data: phase coefficients, phase basis, geometry, phase row cache output
//   follow: scatteringSourceWeightingFromPhaseRows and calcIntegratedReflectanceWithBasis
fn buildPhaseRowCache(
    phase_coefficients: *const [basis.max_phase_coef]f64,
    max_phase_index: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) PhaseRowCache {
    var cache = PhaseRowCache{
        .rows = undefined,
        .n = geo.nmutot,
    };
    for (0..geo.nmutot) |row_index| {
        cache.rows[row_index] = basis.fillZplusZminRowFromBasisLimited(
            i_fourier,
            phase_coefficients,
            max_phase_index,
            geo,
            plm_basis,
            row_index,
        );
    }
    return cache;
}

inline fn scatteringSourceRowSumsFromRows(
    rows: PhaseRows,
    level: *const basis.UDField,
    geo: *const basis.Geometry,
    row_index: usize,
) ScatteringSourceRowSums {
    const solar_col: usize = 1;
    const solar_idx = geo.n_gauss + 1;
    const mu_row = @max(geo.u[row_index], 1.0e-12);
    var sums = ScatteringSourceRowSums{
        .pplusplus_ed = 0.0,
        .pminplus_ed = 0.0,
        .pminmin_u = 0.0,
        .pplusmin_u = 0.0,
    };
    for (0..geo.n_gauss) |imu| {
        const mu_col = @max(geo.u[imu], 1.0e-12);
        const pplus = (0.25 * rows.zplus[imu] / mu_row) / mu_col;
        const pmin = (0.25 * rows.zmin[imu] / mu_row) / mu_col;
        sums.pplusplus_ed += pplus * level.D.col[solar_col].get(imu);
        sums.pminplus_ed += pmin * level.D.col[solar_col].get(imu);
        sums.pminmin_u += pplus * level.U.col[solar_col].get(imu);
        sums.pplusmin_u += pmin * level.U.col[solar_col].get(imu);
    }
    const mu_solar = @max(geo.u[solar_idx], 1.0e-12);
    const pplus_direct = (0.25 * rows.zplus[solar_idx] / mu_row) / mu_solar;
    const pmin_direct = (0.25 * rows.zmin[solar_idx] / mu_row) / mu_solar;
    sums.pplusplus_ed += pplus_direct * level.E.get(solar_idx);
    sums.pminplus_ed += pmin_direct * level.E.get(solar_idx);
    return sums;
}

fn scatteringCoefficientInterfaceWeighting(
    aerosol_ksca_per_km: f64,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    rtm_quadrature: common.RtmQuadratureGrid,
    ilevel: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) f64 {
    if (aerosol_ksca_per_km <= 0.0) return 0.0;
    const unit_phase = unitAerosolPhase(rtm_quadrature) orelse return 0.0;
    const max_phase_index = unit_phase.max_index;
    if (i_fourier > max_phase_index) return 0.0;
    return scatteringSourceWeightingFromScaledPhase(
        unit_phase.coefficients,
        max_phase_index,
        ud,
        ilevel,
        i_fourier,
        geo,
        plm_basis,
    ) + absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        ilevel,
        use_pseudo_spherical,
        geo,
    );
}

fn scatteringCoefficientInterfaceWeightingFromPhaseRows(
    phase_rows: *const PhaseRowCache,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    rtm_quadrature: common.RtmQuadratureGrid,
    ilevel: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
) f64 {
    return scatteringSourceWeightingFromPhaseRows(
        phase_rows,
        ud,
        ilevel,
        geo,
    ) + absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        ilevel,
        use_pseudo_spherical,
        geo,
    );
}

fn aerosolTotalExtinctionInterfaceWeighting(
    scattering_weighting: f64,
    absorption_weighting: f64,
    aerosol_ssa: f64,
) f64 {
    return aerosol_ssa * scattering_weighting + (1.0 - aerosol_ssa) * absorption_weighting;
}

// hot path:
//   when: Jacobian weighting can reuse precomputed phase rows
//   work: combines phase rows, order fields, and direct source terms into scattering-source weighting
//   data: phase row cache, order fields, layer/source geometry, derivative target level
//   follow: calcAerosolOpticalDepthWeightingWithBasis and pressure-shift weighting
fn scatteringSourceWeightingFromPhaseRows(
    phase_rows: *const PhaseRowCache,
    ud: []const basis.UDField,
    ilevel: usize,
    geo: *const basis.Geometry,
) f64 {
    const view_col: usize = 0;
    const view_idx = geo.viewIdx();
    const level = &ud[ilevel];

    var sum: f64 = 0.0;
    for (0..geo.n_gauss) |row_index| {
        const cached_row = &phase_rows.rows[row_index];
        const row = scatteringSourceRowSumsFromRows(
            .{
                .zplus = cached_row.zplus[0..phase_rows.n],
                .zmin = cached_row.zmin[0..phase_rows.n],
            },
            level,
            geo,
            row_index,
        );
        sum += level.D.col[view_col].get(row_index) * (row.pminplus_ed + row.pminmin_u) +
            level.U.col[view_col].get(row_index) * (row.pplusplus_ed + row.pplusmin_u);
    }
    const cached_view_row = &phase_rows.rows[view_idx];
    const view_row = scatteringSourceRowSumsFromRows(
        .{
            .zplus = cached_view_row.zplus[0..phase_rows.n],
            .zmin = cached_view_row.zmin[0..phase_rows.n],
        },
        level,
        geo,
        view_idx,
    );
    sum += level.E.get(view_idx) * (view_row.pminplus_ed + view_row.pminmin_u);
    return sum;
}

// hot path:
//   when: aerosol optical-depth derivative columns are requested
//   work: assembles per-level reflectance weighting from attenuation, orders, and phase rows
//   data: active levels, layer inputs, attenuation arrays, phase basis, Jacobian output
//   follow: absorptionInterfaceWeighting and scatteringSourceWeightingFromPhaseRows
pub fn calcAerosolOpticalDepthWeightingWithBasis(
    layers: []const common.LayerInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    end_level: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    adjacent_layer_phase_max_indices: ?[]const usize,
) f64 {
    _ = adjacent_layer_phase_max_indices;
    if (!rtm_quadrature.isValidFor(layers.len)) return 0.0;
    if (activeAerosolInteriorBounds(rtm_quadrature, end_level)) |bounds| {
        if (bounds.top <= bounds.bottom + 1) return 0.0;
        const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);
        const needs_absorption_weighting = (1.0 - aerosol_ssa) != 0.0;
        const denominator =
            rtm_quadrature.levels[bounds.top - 1].altitude_km -
            rtm_quadrature.levels[bounds.bottom].altitude_km;
        if (denominator <= 0.0) return 0.0;
        const cached_phase_rows = if (commonActiveAerosolUnitPhase(rtm_quadrature, bounds)) |unit_phase|
            if (i_fourier <= unit_phase.max_index)
                buildPhaseRowCache(unit_phase.coefficients, unit_phase.max_index, i_fourier, geo, plm_basis)
            else
                return 0.0
        else
            null;
        var integral: f64 = 0.0;
        var previous = aerosolTotalExtinctionInterfaceWeighting(
            if (cached_phase_rows) |phase_rows|
                scatteringCoefficientInterfaceWeightingFromPhaseRows(
                    &phase_rows,
                    ud,
                    ud_sum_local,
                    rtm_quadrature,
                    bounds.bottom,
                    use_pseudo_spherical,
                    geo,
                )
            else
                scatteringCoefficientInterfaceWeighting(
                    rtm_quadrature.levels[bounds.bottom].aerosol_ksca_above_per_km,
                    ud,
                    ud_sum_local,
                    rtm_quadrature,
                    bounds.bottom,
                    i_fourier,
                    use_pseudo_spherical,
                    geo,
                    plm_basis,
                ),
            if (needs_absorption_weighting)
                absorptionInterfaceWeighting(
                    ud,
                    ud_sum_local,
                    rtm_quadrature,
                    bounds.bottom,
                    use_pseudo_spherical,
                    geo,
                )
            else
                0.0,
            aerosol_ssa,
        );
        for (bounds.bottom + 1..bounds.top) |ilevel| {
            const current = aerosolTotalExtinctionInterfaceWeighting(
                if (cached_phase_rows) |phase_rows|
                    scatteringCoefficientInterfaceWeightingFromPhaseRows(
                        &phase_rows,
                        ud,
                        ud_sum_local,
                        rtm_quadrature,
                        ilevel,
                        use_pseudo_spherical,
                        geo,
                    )
                else
                    scatteringCoefficientInterfaceWeighting(
                        rtm_quadrature.levels[ilevel].aerosol_ksca_above_per_km,
                        ud,
                        ud_sum_local,
                        rtm_quadrature,
                        ilevel,
                        i_fourier,
                        use_pseudo_spherical,
                        geo,
                        plm_basis,
                    ),
                if (needs_absorption_weighting)
                    absorptionInterfaceWeighting(
                        ud,
                        ud_sum_local,
                        rtm_quadrature,
                        ilevel,
                        use_pseudo_spherical,
                        geo,
                    )
                else
                    0.0,
                aerosol_ssa,
            );
            const dz = rtm_quadrature.levels[ilevel].altitude_km -
                rtm_quadrature.levels[ilevel - 1].altitude_km;
            if (dz > 0.0) integral += 0.5 * (previous + current) * dz;
            previous = current;
        }
        return integral / denominator;
    }

    var weighting: f64 = 0.0;
    const unit_phase = unitAerosolPhase(rtm_quadrature) orelse return 0.0;
    for (0..end_level + 1) |ilevel| {
        const level = &rtm_quadrature.levels[ilevel];
        if (level.weight <= 0.0) continue;
        const d_sca_d_tau = level.aerosol_ksca_jacobian;
        if (d_sca_d_tau == 0.0) continue;
        const source_max_phase_index = unit_phase.max_index;
        if (i_fourier > source_max_phase_index) continue;
        const source_weighting = d_sca_d_tau * scatteringSourceWeightingFromScaledPhase(
            unit_phase.coefficients,
            source_max_phase_index,
            ud,
            ilevel,
            i_fourier,
            geo,
            plm_basis,
        );
        const extinction_weighting = d_sca_d_tau * absorptionInterfaceWeighting(
            ud,
            ud_sum_local,
            rtm_quadrature,
            ilevel,
            use_pseudo_spherical,
            geo,
        );
        weighting += level.weight * (source_weighting + extinction_weighting);
    }
    return weighting;
}

// hot path:
//   when: aerosol layer-pressure derivative columns are requested
//   work: assembles pressure-shift reflectance weighting from order and phase data
//   data: active layer levels, pressure-shift factors, phase rows, Jacobian output
//   follow: active derivative mask routing and shared phase row construction
pub fn calcAerosolLayerPressureShiftWeightingWithBasis(
    layers: []const common.LayerInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    end_level: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) f64 {
    if (!rtm_quadrature.isValidFor(layers.len)) return 0.0;
    const bounds = activeAerosolInteriorBounds(rtm_quadrature, end_level) orelse return 0.0;
    const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);
    const top_sca_weighting = scatteringCoefficientInterfaceWeighting(
        rtm_quadrature.levels[bounds.top].aerosol_ksca_below_per_km,
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.top,
        i_fourier,
        use_pseudo_spherical,
        geo,
        plm_basis,
    );
    const bottom_sca_weighting = scatteringCoefficientInterfaceWeighting(
        rtm_quadrature.levels[bounds.bottom].aerosol_ksca_above_per_km,
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.bottom,
        i_fourier,
        use_pseudo_spherical,
        geo,
        plm_basis,
    );
    const ksca = rtm_quadrature.levels[bounds.top].aerosol_ksca_below_per_km;
    const kabs = if (aerosol_ssa > 0.0) ksca * (1.0 - aerosol_ssa) / aerosol_ssa else 0.0;
    if (kabs == 0.0) return (top_sca_weighting - bottom_sca_weighting) * ksca;
    const top_abs_weighting = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.top,
        use_pseudo_spherical,
        geo,
    );
    const bottom_abs_weighting = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.bottom,
        use_pseudo_spherical,
        geo,
    );
    return (top_sca_weighting - bottom_sca_weighting) * ksca +
        (top_abs_weighting - bottom_abs_weighting) * kabs;
}

pub fn totalScatteringOpticalDepth(layers: []const common.LayerInput) f64 {
    var total: f64 = 0.0;
    for (layers) |*layer| total += @max(layer.scattering_optical_depth, 0.0);
    return total;
}

fn maxFourierIndex(layers: []const common.LayerInput) usize {
    var max_index: usize = 0;
    for (layers) |*layer| {
        max_index = @max(max_index, maxPhaseCoefficientIndex(&layer.phase_coefficients));
    }
    return max_index;
}

fn maxFourierIndexInterfaces(source_interfaces: []const common.SourceInterfaceInput) usize {
    var max_index: usize = 0;
    for (source_interfaces) |*source_interface| {
        max_index = @max(max_index, maxPhaseCoefficientIndex(&source_interface.phase_coefficients_above));
        max_index = @max(max_index, source_interface.phase_max_index_below);
    }
    return max_index;
}

fn maxFourierIndexQuadrature(rtm_quadrature: common.RtmQuadratureGrid) usize {
    var max_index: usize = 0;
    for (rtm_quadrature.levels) |*level| {
        if (level.weight <= 0.0 or level.ksca <= 0.0) continue;
        max_index = @max(max_index, maxRtmQuadraturePhaseCoefficientIndex(level, rtm_quadrature));
    }
    return max_index;
}

pub fn resolvedPhaseCoefficientMax(input: common.ForwardInput) usize {
    var max_index = maxFourierIndex(input.layers);
    if (input.rtm_quadrature.isValidFor(input.layers.len)) {
        max_index = @max(max_index, maxFourierIndexQuadrature(input.rtm_quadrature));
    } else if (input.source_interfaces.len == input.layers.len + 1) {
        max_index = @max(max_index, maxFourierIndexInterfaces(input.source_interfaces));
    }
    return max_index;
}

// hot path:
//   when: LABOS sets Fourier loop bounds for a high-resolution forward sample
//   work: resolves the maximum Fourier term from phase coefficient support and route controls
//   data: forward input phase coefficients, control limits, resolved phase maximum
//   follow: layerResolvedLabosWithWorkspace Fourier loop
pub fn resolvedFourierMax(input: common.ForwardInput, controls: common.RadiativeTransferControls) usize {
    if (input.layers.len == 0) return 0;
    // PARITY:
    //   Near-nadir and near-normal geometries collapse to the scalar Fourier
    //   term in the vendor path.
    if ((1.0 - input.muv) < 1.0e-5 or (1.0 - input.mu0) < 1.0e-5) return 0;
    const resolved_max = if (input.rtm_quadrature.isValidFor(input.layers.len))
        maxFourierIndexQuadrature(input.rtm_quadrature)
    else if (input.source_interfaces.len == input.layers.len + 1)
        maxFourierIndexInterfaces(input.source_interfaces)
    else
        maxFourierIndex(input.layers);
    return controls.performance_thresholds.cappedFourierMax(resolved_max);
}
