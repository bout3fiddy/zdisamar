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

const std = @import("std");
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

/// Purpose:
///   Resolve the highest Fourier index required by the phase coefficients.
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

fn reuseLayerKernelIndex(
    layers: []const common.LayerInput,
    source_interface: common.SourceInterfaceInput,
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

/// Purpose:
///   Compute TOA reflectance from the resolved LABOS internal radiation field.
pub fn calcReflectance(
    ud: []const basis.UDField,
    end_level: usize,
    geo: *const basis.Geometry,
) f64 {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    return ud[end_level].U.col[solar_col].get(view_idx);
}

/// Purpose:
///   Compute the integrated reflectance using source-interface or quadrature
///   carriers.
///
/// Physics:
///   Integrates the local source term against the LABOS upwelling and
///   downwelling fields, including the zero-Fourier direct term.
///
/// Vendor:
///   `LABOS reflectance extraction`
///
/// Inputs:
///   `layers` and `source_interfaces` describe the transport grid, `ud`
///   carries the internal radiation field, and `i_fourier` selects the phase
///   term.
///
/// Outputs:
///   Returns the total reflectance contribution for the requested Fourier term.
///
/// Assumptions:
///   The carrier arrays are aligned with the transport grid and any quadrature
///   grid is already normalized to that layout.
///
/// Validation:
///   `tests/unit/transport_labos_test.zig`
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
    );
}

/// Purpose:
///   Compute the integrated reflectance using a caller-provided Fourier basis
///   and optional layer phase-kernel cache.
///
/// Physics:
///   Reuses the exact phase-kernel basis across interfaces and reuses already
///   materialized layer kernels when the source-interface carrier is identical
///   to the layer-above phase contract.
pub fn calcIntegratedReflectanceWithBasis(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    end_level: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    layer_phase_kernel_cache: ?[]const basis.PhaseKernel,
    layer_phase_kernel_valid: ?[]const bool,
) f64 {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const view_mu = @max(geo.u[view_idx], 1.0e-12);
    var reflectance: f64 = 0.0;
    const use_rtm_quadrature = rtm_quadrature.isValidFor(layers.len);

    for (0..end_level + 1) |ilevel| {
        // DECISION:
        //   Prefer the quadrature carrier when it is aligned with the layer
        //   grid; otherwise fall back to the source-interface contract.
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
            // PARITY:
            //   Higher Fourier orders are skipped when the active phase
            //   coefficients cannot support them.
            continue;
        }

        const z = blk: {
            if (!use_rtm_quadrature) {
                if (reuseLayerKernelIndex(layers, source_interface, ilevel)) |above_index| {
                    if (layer_phase_kernel_cache) |cache| {
                        if (layer_phase_kernel_valid) |valid| {
                            const cache_index = above_index + 1;
                            if (cache_index < cache.len and cache_index < valid.len and valid[cache_index]) {
                                break :blk cache[cache_index];
                            }
                        }
                    }
                }
            }
            break :blk basis.fillZplusZminFromBasis(i_fourier, phase_coefficients, geo, plm_basis);
        };
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
        // PARITY:
        //   Keep the vendor scalar direct term in the zero-Fourier closure.
        reflectance += ud[0].E.get(view_idx) * ud[0].U.col[solar_col].get(view_idx);
    }

    return reflectance;
}

/// Purpose:
///   Return the total non-negative scattering optical depth of the layer set.
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

/// Purpose:
///   Resolve the highest phase-coefficient index needed by the current
///   transport input.
pub fn resolvedPhaseCoefficientMax(input: common.ForwardInput) usize {
    var max_index = maxFourierIndex(input.layers);
    if (input.rtm_quadrature.isValidFor(input.layers.len)) {
        max_index = @max(max_index, maxFourierIndexQuadrature(input.rtm_quadrature));
    } else if (input.source_interfaces.len == input.layers.len + 1) {
        max_index = @max(max_index, maxFourierIndexInterfaces(input.source_interfaces));
    }
    return max_index;
}

/// Purpose:
///   Resolve the highest Fourier term needed by the active transport input.
///
/// Vendor:
///   `LABOS reflectance extraction`
///
/// Assumptions:
///   The route has already resolved its layer and source-interface contract.
///
/// Validation:
///   `tests/unit/transport_labos_test.zig`
pub fn resolvedFourierMax(input: common.ForwardInput, controls: common.RtmControls) usize {
    _ = controls;
    if (input.layers.len == 0) return 0;
    // PARITY:
    //   Near-nadir and near-normal geometries collapse to the scalar Fourier
    //   term in the vendor path.
    if ((1.0 - input.muv) < 1.0e-5 or (1.0 - input.mu0) < 1.0e-5) return 0;
    if (input.rtm_quadrature.isValidFor(input.layers.len)) {
        return maxFourierIndexQuadrature(input.rtm_quadrature);
    }
    if (input.source_interfaces.len == input.layers.len + 1) {
        return maxFourierIndexInterfaces(input.source_interfaces);
    }
    return maxFourierIndex(input.layers);
}

test "cached layer kernels preserve integrated reflectance when source interfaces mirror layers" {
    const geo = basis.Geometry.init(4, 0.58, 0.64);
    const layers = [_]common.LayerInput{
        .{
            .scattering_optical_depth = 0.22,
            .phase_coefficients = .{ 1.0, 0.56, 0.24, 0.09 } ++
                .{0.0} ** (basis.max_phase_coef - 4),
        },
        .{
            .scattering_optical_depth = 0.18,
            .phase_coefficients = .{ 1.0, 0.41, 0.17, 0.05 } ++
                .{0.0} ** (basis.max_phase_coef - 4),
        },
    };
    var ud: [3]basis.UDField = undefined;
    for (&ud) |*field| {
        field.* = .{
            .E = basis.Vec.zero(geo.nmutot),
            .U = basis.Vec2.zero(geo.nmutot),
            .D = basis.Vec2.zero(geo.nmutot),
        };
    }
    for (0..ud.len) |ilevel| {
        for (0..geo.nmutot) |imu| {
            ud[ilevel].E.set(imu, 0.8 - 0.1 * @as(f64, @floatFromInt(ilevel)));
            for (0..2) |imu0| {
                ud[ilevel].U.col[imu0].set(imu, 0.02 * @as(f64, @floatFromInt((ilevel + 1) * (imu + 1) * (imu0 + 1))));
                ud[ilevel].D.col[imu0].set(imu, 0.01 * @as(f64, @floatFromInt((ilevel + 2) * (imu + 1) * (imu0 + 1))));
            }
        }
    }

    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    common.fillSourceInterfacesFromLayers(&layers, &source_interfaces);
    const input: common.ForwardInput = .{
        .layers = &layers,
        .source_interfaces = &source_interfaces,
    };
    const i_fourier: usize = 1;
    const plm_basis = basis.FourierPlmBasis.init(i_fourier, resolvedPhaseCoefficientMax(input), &geo);
    var kernel_cache: [3]basis.PhaseKernel = undefined;
    var kernel_valid = [_]bool{false} ** 3;
    for (0..layers.len) |layer_idx| {
        kernel_cache[layer_idx + 1] = basis.fillZplusZminFromBasis(
            i_fourier,
            layers[layer_idx].phase_coefficients,
            &geo,
            &plm_basis,
        );
        kernel_valid[layer_idx + 1] = true;
    }

    const baseline = calcIntegratedReflectance(
        &layers,
        &source_interfaces,
        .{},
        &ud,
        layers.len,
        i_fourier,
        &geo,
    );
    const cached = calcIntegratedReflectanceWithBasis(
        &layers,
        &source_interfaces,
        .{},
        &ud,
        layers.len,
        i_fourier,
        &geo,
        &plm_basis,
        &kernel_cache,
        &kernel_valid,
    );

    try std.testing.expectApproxEqAbs(baseline, cached, 1.0e-12);
}
