const std = @import("std");
const basis = @import("basis.zig");
const common = @import("../root.zig");

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
    const below_max = maxPhaseCoefficientIndex(source_interface.phase_coefficients_below);
    if (layers.len == 0 or ilevel == 0 or ilevel > layers.len - 1) return @max(above_max, below_max);
    return @max(above_max, below_max);
}

fn adjacentLayerPhaseCoefficientIndex(
    layers: []const common.LayerInput,
    ilevel: usize,
) usize {
    if (layers.len == 0) return 0;
    if (ilevel == 0) return maxPhaseCoefficientIndex(layers[0].phase_coefficients);
    if (ilevel >= layers.len) return maxPhaseCoefficientIndex(layers[layers.len - 1].phase_coefficients);
    return @max(
        maxPhaseCoefficientIndex(layers[ilevel - 1].phase_coefficients),
        maxPhaseCoefficientIndex(layers[ilevel].phase_coefficients),
    );
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
        const source_rtm_weight = if (use_rtm_quadrature)
            rtm_quadrature.levels[ilevel].weight
        else if (source_interface.rtm_weight > 0.0 and source_interface.ksca_above > 0.0)
            source_interface.rtm_weight
        else
            source_interface.source_weight;
        const source_ksca = if (use_rtm_quadrature)
            rtm_quadrature.levels[ilevel].ksca
        else if (source_interface.rtm_weight > 0.0 and source_interface.ksca_above > 0.0)
            source_interface.ksca_above
        else
            1.0;
        if (source_rtm_weight <= 0.0 or source_ksca <= 0.0) continue;
        const phase_coefficients = if (use_rtm_quadrature)
            rtm_quadrature.levels[ilevel].phase_coefficients
        else
            source_interface.phase_coefficients_above;
        const source_max_phase_index = if (use_rtm_quadrature)
            adjacentLayerPhaseCoefficientIndex(layers, ilevel)
        else if (layers.len != 0)
            adjacentLayerPhaseCoefficientIndex(layers, ilevel)
        else
            maxInterfacePhaseCoefficientIndex(layers, source_interfaces, ilevel);
        if (i_fourier > source_max_phase_index) {
            // PARITY:
            //   DISAMAR gates an integrated-source level by the max phase
            //   order of its adjacent reduced layers, then uses the interface
            //   carrier only up to that same ceiling.
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
            break :blk basis.fillZplusZminFromBasisLimited(
                i_fourier,
                phase_coefficients,
                source_max_phase_index,
                geo,
                plm_basis,
            );
        };
        var pmin_ed: f64 = 0.0;

        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], 1.0e-12);
            const pmin = 0.25 * z.Zmin.get(view_idx, imu) / (view_mu * mu);
            pmin_ed += pmin * ud[ilevel].D.col[solar_col].get(imu);
        }

        const solar_mu = @max(geo.u[solar_idx], 1.0e-12);
        const pmin_direct = 0.25 * z.Zmin.get(view_idx, solar_idx) / (view_mu * solar_mu);
        pmin_ed += pmin_direct * ud[ilevel].E.get(solar_idx);

        var pplusst_u: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], 1.0e-12);
            const pplusst = 0.25 * z.Zplus.get(view_idx, imu) / (view_mu * mu);
            pplusst_u += pplusst * ud[ilevel].U.col[solar_col].get(imu);
        }

        // PARITY: `LabosModule::CalcReflectance` forms the level source as
        // `E * ksca * (...)`, then applies `RTMweight` in a separate reduction.
        const contribution = ud[ilevel].E.get(view_idx) *
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
        max_index = @max(max_index, maxPhaseCoefficientIndex(source_interface.phase_coefficients_below));
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

pub fn resolvedPhaseCoefficientMax(input: common.ForwardInput) usize {
    var max_index = maxFourierIndex(input.layers);
    if (input.rtm_quadrature.isValidFor(input.layers.len)) {
        max_index = @max(max_index, maxFourierIndexQuadrature(input.rtm_quadrature));
    } else if (input.source_interfaces.len == input.layers.len + 1) {
        max_index = @max(max_index, maxFourierIndexInterfaces(input.source_interfaces));
    }
    return max_index;
}

pub fn resolvedFourierMax(input: common.ForwardInput, controls: common.RadiativeTransferControls) usize {
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
