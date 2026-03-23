//! Purpose:
//!   Own LABOS reflectance extraction and Fourier-resolution selection.
//!
//! Physics:
//!   Converts the internal radiation field into TOA reflectance and chooses
//!   the Fourier terms required by the prepared transport input.
//!
//! Vendor:
//!   LABOS reflectance extraction stage
//!
//! Design:
//!   Reflectance extraction is separated from the orders recursion so the
//!   higher-level facade can re-use the same Fourier and source-interface
//!   policy without a monolithic solver file.
//!
//! Invariants:
//!   Scalar LABOS uses the solar column for reflectance extraction. Fourier
//!   truncation is driven by the active phase coefficients and transport input.
//!
//! Validation:
//!   See `tests/unit/transport_labos_test.zig` for reflectance and Fourier
//!   selection coverage.

const basis = @import("basis.zig");
const common = @import("../common.zig");

fn sourceInterfaceAtLevel(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    ilevel: usize,
) common.SourceInterfaceInput {
    if (source_interfaces.len == layers.len + 1 and ilevel < source_interfaces.len) {
        return source_interfaces[ilevel];
    }
    return common.sourceInterfaceFromLayers(layers, ilevel);
}

fn maxPhaseCoefficientIndex(phase_coefficients: [basis.max_phase_coef]f64) usize {
    var max_index: usize = 0;
    for (1..basis.max_phase_coef) |idx| {
        if (@abs(phase_coefficients[idx]) > 1.0e-12) {
            max_index = idx;
        }
    }
    return max_index;
}

fn maxInterfacePhaseCoefficientIndex(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    ilevel: usize,
) usize {
    const source_interface = sourceInterfaceAtLevel(layers, source_interfaces, ilevel);
    const above_max = maxPhaseCoefficientIndex(source_interface.phase_coefficients_above);
    if (layers.len == 0 or ilevel == 0 or ilevel > layers.len - 1) return above_max;
    const below_max = maxPhaseCoefficientIndex(layers[ilevel - 1].phase_coefficients);
    return @max(above_max, below_max);
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

pub fn calcIntegratedReflectance(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    end_level: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
) f64 {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const view_mu = @max(geo.u[view_idx], 1.0e-12);
    var reflectance: f64 = 0.0;
    const use_rtm_quadrature = rtm_quadrature.isValidFor(layers.len);

    for (0..end_level + 1) |ilevel| {
        const source_interface = if (use_rtm_quadrature)
            common.SourceInterfaceInput{}
        else
            sourceInterfaceAtLevel(layers, source_interfaces, ilevel);
        const source_weight = if (use_rtm_quadrature)
            rtm_quadrature.levels[ilevel].weightedScattering()
        else
            source_interface.effectiveWeight();
        if (source_weight <= 0.0) continue;
        const phase_coefficients = if (use_rtm_quadrature)
            rtm_quadrature.levels[ilevel].phase_coefficients
        else
            source_interface.phase_coefficients_above;
        if (i_fourier > if (use_rtm_quadrature)
            maxPhaseCoefficientIndex(phase_coefficients)
        else
            maxInterfacePhaseCoefficientIndex(layers, source_interfaces, ilevel))
        {
            continue;
        }

        const z = basis.fillZplusZmin(i_fourier, phase_coefficients, geo);
        var pmin_ed: f64 = 0.0;
        var pplusst_u: f64 = 0.0;

        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], 1.0e-12);
            const pmin = 0.25 * z.Zmin.get(view_idx, imu) / (view_mu * mu);
            const pplusst = 0.25 * z.Zplus.get(view_idx, imu) / (view_mu * mu);
            pmin_ed += pmin * ud[ilevel].D.col[solar_col].get(imu);
            pplusst_u += pplusst * ud[ilevel].U.col[solar_col].get(imu);
        }

        const solar_mu = @max(geo.u[solar_idx], 1.0e-12);
        pmin_ed += 0.25 * z.Zmin.get(view_idx, solar_idx) /
            (view_mu * solar_mu) * ud[ilevel].E.get(solar_idx);

        reflectance += ud[ilevel].E.get(view_idx) *
            source_weight *
            (pmin_ed + pplusst_u);
    }

    if (i_fourier == 0) {
        reflectance += ud[0].E.get(view_idx) * ud[0].U.col[solar_col].get(view_idx);
    }

    return reflectance;
}

pub fn totalScatteringOpticalDepth(layers: []const common.LayerInput) f64 {
    var total: f64 = 0.0;
    for (layers) |layer| total += @max(layer.scattering_optical_depth, 0.0);
    return total;
}

fn maxFourierIndex(layers: []const common.LayerInput) usize {
    var max_index: usize = 0;
    for (layers) |layer| {
        max_index = @max(max_index, maxPhaseCoefficientIndex(layer.phase_coefficients));
    }
    return max_index;
}

fn maxFourierIndexInterfaces(source_interfaces: []const common.SourceInterfaceInput) usize {
    var max_index: usize = 0;
    for (source_interfaces) |source_interface| {
        max_index = @max(max_index, maxPhaseCoefficientIndex(source_interface.phase_coefficients_above));
    }
    return max_index;
}

fn maxFourierIndexQuadrature(rtm_quadrature: common.RtmQuadratureGrid) usize {
    var max_index: usize = 0;
    for (rtm_quadrature.levels) |level| {
        if (level.weight <= 0.0 or level.ksca <= 0.0) continue;
        max_index = @max(max_index, maxPhaseCoefficientIndex(level.phase_coefficients));
    }
    return max_index;
}

pub fn resolvedFourierMax(input: common.ForwardInput, controls: common.RtmControls) usize {
    _ = controls;
    if (input.layers.len == 0) return 0;
    if ((1.0 - input.muv) < 1.0e-5 or (1.0 - input.mu0) < 1.0e-5) return 0;
    if (input.rtm_quadrature.isValidFor(input.layers.len)) {
        return maxFourierIndexQuadrature(input.rtm_quadrature);
    }
    if (input.source_interfaces.len == input.layers.len + 1) {
        return maxFourierIndexInterfaces(input.source_interfaces);
    }
    return maxFourierIndex(input.layers);
}
