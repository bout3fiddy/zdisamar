use crate::forward_model::{
    jacobian::{self, State},
    optical_properties::shared::phase_functions,
    radiative_transfer::{
        ForwardInput, LayerInput, RadiativeTransferControls, RtmQuadratureGrid,
        SourceInterfaceInput, source_interface_from_layers,
    },
};

use super::{
    FourierPlmBasis, Geometry, MAX_NMUTOT, PhaseKernel, UdField, UdLocal,
    fill_zplus_zmin_row_from_basis_limited,
};

#[derive(Debug, Clone, Copy, PartialEq)]
struct ScatteringSourceRowSums {
    pplusplus_ed: f64,
    pminplus_ed: f64,
    pminmin_u: f64,
    pplusmin_u: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct AerosolIntervalBounds {
    bottom: usize,
    top: usize,
}

fn source_interface_at_level(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    ilevel: usize,
) -> SourceInterfaceInput {
    if source_interfaces.len() == layers.len() + 1 && ilevel < source_interfaces.len() {
        return source_interfaces[ilevel];
    }
    source_interface_from_layers(layers, ilevel)
}

fn max_phase_coefficient_index(phase_coefficients: phase_functions::PhaseCoefficients) -> usize {
    phase_functions::max_phase_coefficient_index(phase_coefficients)
}

fn max_interface_phase_coefficient_index(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    ilevel: usize,
) -> usize {
    let source_interface = source_interface_at_level(layers, source_interfaces, ilevel);
    max_phase_coefficient_index(source_interface.phase_coefficients_above).max(
        max_phase_coefficient_index(source_interface.phase_coefficients_below),
    )
}

fn adjacent_layer_phase_coefficient_index(layers: &[LayerInput], ilevel: usize) -> usize {
    if layers.is_empty() {
        return 0;
    }
    if ilevel == 0 {
        return max_phase_coefficient_index(layers[0].phase_coefficients);
    }
    if ilevel >= layers.len() {
        return max_phase_coefficient_index(layers[layers.len() - 1].phase_coefficients);
    }
    max_phase_coefficient_index(layers[ilevel - 1].phase_coefficients).max(
        max_phase_coefficient_index(layers[ilevel].phase_coefficients),
    )
}

pub fn fill_adjacent_layer_phase_max_indices(
    source_phase_max_indices: &mut [usize],
    layer_phase_max_indices: &[usize],
) {
    let nlayer = layer_phase_max_indices.len();
    assert!(source_phase_max_indices.len() > nlayer);
    if nlayer == 0 {
        if !source_phase_max_indices.is_empty() {
            source_phase_max_indices[0] = 0;
        }
        return;
    }

    source_phase_max_indices[0] = layer_phase_max_indices[0];
    for ilevel in 1..nlayer {
        source_phase_max_indices[ilevel] =
            layer_phase_max_indices[ilevel - 1].max(layer_phase_max_indices[ilevel]);
    }
    source_phase_max_indices[nlayer] = layer_phase_max_indices[nlayer - 1];
}

fn reuse_layer_kernel_index(
    layers: &[LayerInput],
    source_interface: SourceInterfaceInput,
    ilevel: usize,
) -> Option<usize> {
    if layers.is_empty() {
        return None;
    }
    let above_index = ilevel.min(layers.len() - 1);
    if source_interface.phase_coefficients_above != layers[above_index].phase_coefficients {
        return None;
    }
    Some(above_index)
}

pub fn calc_reflectance(ud: &[UdField], end_level: usize, geo: &Geometry) -> f64 {
    let solar_col = 1;
    let view_idx = geo.view_idx();
    ud[end_level].u.col[solar_col].get(view_idx)
}

pub fn calc_reflectance_tangent(ud_tangent: &[UdField], end_level: usize, geo: &Geometry) -> f64 {
    calc_reflectance(ud_tangent, end_level, geo)
}

pub fn calc_integrated_reflectance(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    rtm_quadrature: &RtmQuadratureGrid,
    ud: &[UdField],
    end_level: usize,
    i_fourier: usize,
    geo: &Geometry,
) -> f64 {
    let max_phase_index = if rtm_quadrature.is_valid_for(layers.len()) {
        max_fourier_index(layers).max(max_fourier_index_quadrature(rtm_quadrature))
    } else {
        max_fourier_index(layers).max(max_fourier_index_interfaces(source_interfaces))
    };
    let plm_basis = FourierPlmBasis::init(i_fourier, max_phase_index, geo);
    calc_integrated_reflectance_with_basis(
        layers,
        source_interfaces,
        rtm_quadrature,
        ud,
        end_level,
        i_fourier,
        geo,
        &plm_basis,
        None,
        None,
        None,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn calc_integrated_reflectance_with_basis(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    rtm_quadrature: &RtmQuadratureGrid,
    ud: &[UdField],
    end_level: usize,
    i_fourier: usize,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
    adjacent_layer_phase_max_indices: Option<&[usize]>,
    layer_phase_kernel_cache: Option<&[PhaseKernel]>,
    layer_phase_kernel_valid: Option<&[bool]>,
) -> f64 {
    let solar_col = 1;
    let view_idx = geo.view_idx();
    let solar_idx = geo.n_gauss + 1;
    let view_mu = geo.u[view_idx].max(1.0e-12);
    let use_rtm_quadrature = rtm_quadrature.is_valid_for(layers.len());
    let mut reflectance = 0.0;

    for ilevel in 0..=end_level {
        // Use the quadrature carrier when it matches the layer grid; otherwise use source interfaces.
        let source_interface = if use_rtm_quadrature {
            SourceInterfaceInput::default()
        } else {
            source_interface_at_level(layers, source_interfaces, ilevel)
        };
        let source_rtm_weight = if use_rtm_quadrature {
            rtm_quadrature.levels[ilevel].weight
        } else if source_interface.rtm_weight > 0.0 && source_interface.ksca_above > 0.0 {
            source_interface.rtm_weight
        } else {
            source_interface.source_weight
        };
        let source_ksca = if use_rtm_quadrature {
            rtm_quadrature.levels[ilevel].ksca
        } else if source_interface.rtm_weight > 0.0 && source_interface.ksca_above > 0.0 {
            source_interface.ksca_above
        } else {
            1.0
        };
        if source_rtm_weight <= 0.0 || source_ksca <= 0.0 {
            continue;
        }

        let phase_coefficients = if use_rtm_quadrature {
            rtm_quadrature.levels[ilevel].phase_coefficients
        } else {
            source_interface.phase_coefficients_above
        };
        let source_max_phase_index = if let Some(indices) = adjacent_layer_phase_max_indices {
            indices[ilevel]
        } else if use_rtm_quadrature || !layers.is_empty() {
            adjacent_layer_phase_coefficient_index(layers, ilevel)
        } else {
            max_interface_phase_coefficient_index(layers, source_interfaces, ilevel)
        };
        if i_fourier > source_max_phase_index {
            continue;
        }

        let (zplus, zmin, row_n) = phase_rows_for_level(
            layers,
            source_interface,
            use_rtm_quadrature,
            ilevel,
            i_fourier,
            phase_coefficients,
            source_max_phase_index,
            geo,
            plm_basis,
            layer_phase_kernel_cache,
            layer_phase_kernel_valid,
        );

        let level = ud[ilevel];
        let level_d = level.d.col[solar_col].data;
        let level_u = level.u.col[solar_col].data;
        let mut pmin_ed = 0.0;
        for imu in 0..geo.n_gauss {
            let mu = geo.u[imu].max(1.0e-12);
            let pmin = (0.25 * zmin[imu] / view_mu) / mu;
            pmin_ed += pmin * level_d[imu];
        }

        let solar_mu = geo.u[solar_idx].max(1.0e-12);
        let pmin_direct = (0.25 * zmin[solar_idx] / view_mu) / solar_mu;
        pmin_ed += pmin_direct * level.e.data[solar_idx];

        let mut pplusst_u = 0.0;
        for imu in 0..geo.n_gauss {
            let mu = geo.u[imu].max(1.0e-12);
            let pplusst = (0.25 * zplus[imu] / view_mu) / mu;
            pplusst_u += pplusst * level_u[imu];
        }

        let contribution = level.e.data[view_idx] * source_ksca * (pmin_ed + pplusst_u);
        reflectance += source_rtm_weight * contribution;
        debug_assert!(row_n >= geo.nmutot);
    }

    if i_fourier == 0 {
        reflectance += ud[0].e.get(view_idx) * ud[0].u.col[solar_col].get(view_idx);
    }

    reflectance
}

fn absorption_interface_weighting(
    ud: &[UdField],
    ud_sum_local: &[UdLocal],
    rtm_quadrature: &RtmQuadratureGrid,
    ilevel: usize,
    use_pseudo_spherical: bool,
    geo: &Geometry,
) -> f64 {
    let view_col = 0;
    let solar_col = 1;
    let view_idx = geo.view_idx();
    let solar_idx = geo.n_gauss + 1;
    let level = ud[ilevel];
    let mut sum = 0.0;

    for i_gauss in 0..geo.n_gauss {
        let mu = geo.u[i_gauss].max(1.0e-12);
        sum -= (level.u.col[view_col].get(i_gauss) * level.d.col[solar_col].get(i_gauss)
            + level.d.col[view_col].get(i_gauss) * level.u.col[solar_col].get(i_gauss))
            / mu;
    }
    sum -=
        level.u.col[solar_col].get(view_idx) * level.e.get(view_idx) / geo.u[view_idx].max(1.0e-12);

    if use_pseudo_spherical
        && ud_sum_local.len() >= ud.len()
        && rtm_quadrature.levels.len() >= ud.len()
    {
        let earth_radius_km = 6371.0;
        let solar_mu = geo.u[solar_idx].max(1.0e-12);
        let y_k = earth_radius_km + rtm_quadrature.levels[ilevel].altitude_km;
        let mut pseudo_direct_sum = 0.0;
        for level_index in (0..=ilevel).rev() {
            let y_l = earth_radius_km + rtm_quadrature.levels[level_index].altitude_km;
            let denominator = (y_k * y_k - y_l * y_l * (1.0 - solar_mu * solar_mu))
                .abs()
                .sqrt();
            let solar_slant_inverse = if denominator > 0.0 {
                y_k / denominator
            } else {
                0.0
            };
            pseudo_direct_sum += ud_sum_local[level_index].u.col[view_col].get(solar_idx)
                * ud[level_index].e.get(solar_idx)
                * solar_slant_inverse;
        }
        sum -= pseudo_direct_sum;
    } else {
        sum -= level.u.col[view_col].get(solar_idx) * level.e.get(solar_idx)
            / geo.u[solar_idx].max(1.0e-12);
    }

    sum
}

fn scattering_source_row_sums(
    scaled_phase_coefficients: phase_functions::PhaseCoefficients,
    max_phase_index: usize,
    level: &UdField,
    i_fourier: usize,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
    row_index: usize,
) -> ScatteringSourceRowSums {
    let solar_col = 1;
    let solar_idx = geo.n_gauss + 1;
    let rows = fill_zplus_zmin_row_from_basis_limited(
        i_fourier,
        &scaled_phase_coefficients,
        max_phase_index,
        geo,
        plm_basis,
        row_index,
    );
    let mu_row = geo.u[row_index].max(1.0e-12);
    let mut sums = ScatteringSourceRowSums {
        pplusplus_ed: 0.0,
        pminplus_ed: 0.0,
        pminmin_u: 0.0,
        pplusmin_u: 0.0,
    };

    for imu in 0..geo.n_gauss {
        let mu_col = geo.u[imu].max(1.0e-12);
        let pplus = (0.25 * rows.zplus[imu] / mu_row) / mu_col;
        let pmin = (0.25 * rows.zmin[imu] / mu_row) / mu_col;
        sums.pplusplus_ed += pplus * level.d.col[solar_col].get(imu);
        sums.pminplus_ed += pmin * level.d.col[solar_col].get(imu);
        sums.pminmin_u += pplus * level.u.col[solar_col].get(imu);
        sums.pplusmin_u += pmin * level.u.col[solar_col].get(imu);
    }

    let mu_solar = geo.u[solar_idx].max(1.0e-12);
    let pplus_direct = (0.25 * rows.zplus[solar_idx] / mu_row) / mu_solar;
    let pmin_direct = (0.25 * rows.zmin[solar_idx] / mu_row) / mu_solar;
    sums.pplusplus_ed += pplus_direct * level.e.get(solar_idx);
    sums.pminplus_ed += pmin_direct * level.e.get(solar_idx);
    sums
}

fn scattering_source_weighting_from_scaled_phase(
    scaled_phase_coefficients: phase_functions::PhaseCoefficients,
    max_phase_index: usize,
    ud: &[UdField],
    ilevel: usize,
    i_fourier: usize,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
) -> f64 {
    let view_col = 0;
    let view_idx = geo.view_idx();
    let level = &ud[ilevel];
    let mut sum = 0.0;

    for row_index in 0..geo.n_gauss {
        let row = scattering_source_row_sums(
            scaled_phase_coefficients,
            max_phase_index,
            level,
            i_fourier,
            geo,
            plm_basis,
            row_index,
        );
        sum += level.d.col[view_col].get(row_index) * (row.pminplus_ed + row.pminmin_u)
            + level.u.col[view_col].get(row_index) * (row.pplusplus_ed + row.pplusmin_u);
    }

    let view_row = scattering_source_row_sums(
        scaled_phase_coefficients,
        max_phase_index,
        level,
        i_fourier,
        geo,
        plm_basis,
        view_idx,
    );
    sum += level.e.get(view_idx) * (view_row.pminplus_ed + view_row.pminmin_u);
    sum
}

fn active_aerosol_interior_bounds(
    rtm_quadrature: &RtmQuadratureGrid,
    end_level: usize,
) -> Option<AerosolIntervalBounds> {
    let state_index = jacobian::state_index(State::AerosolOpticalDepth);
    let mut first_active = None;
    let mut last_active = None;
    for ilevel in 0..=end_level {
        if rtm_quadrature.levels[ilevel].ksca_phase_coefficient_jacobian[state_index][0] <= 0.0 {
            continue;
        }
        if first_active.is_none() {
            first_active = Some(ilevel);
        }
        last_active = Some(ilevel);
    }

    let first = first_active?;
    let last = last_active?;
    if first == 0 || last + 1 > end_level {
        return None;
    }
    Some(AerosolIntervalBounds {
        bottom: first - 1,
        top: last + 1,
    })
}

fn aerosol_single_scattering_albedo(layers: &[LayerInput]) -> f64 {
    let mut aerosol_optical_depth = 0.0;
    let mut aerosol_scattering_optical_depth = 0.0;
    for layer in layers {
        aerosol_optical_depth += layer.aerosol_optical_depth.max(0.0);
        aerosol_scattering_optical_depth += layer.aerosol_scattering_optical_depth.max(0.0);
    }
    if aerosol_optical_depth <= 0.0 {
        return 1.0;
    }
    (aerosol_scattering_optical_depth / aerosol_optical_depth).clamp(0.0, 1.0)
}

fn unit_phase_coefficients_from_scaled(
    scaled_phase_coefficients: phase_functions::PhaseCoefficients,
) -> phase_functions::PhaseCoefficients {
    let mut unit = [0.0; phase_functions::PHASE_COEFFICIENT_COUNT];
    let scale = scaled_phase_coefficients[0];
    if scale <= 0.0 {
        return unit;
    }
    for index in 0..phase_functions::PHASE_COEFFICIENT_COUNT {
        unit[index] = scaled_phase_coefficients[index] / scale;
    }
    unit
}

#[allow(clippy::too_many_arguments)]
fn scattering_coefficient_interface_weighting(
    scaled_phase_coefficients: phase_functions::PhaseCoefficients,
    ud: &[UdField],
    ud_sum_local: &[UdLocal],
    rtm_quadrature: &RtmQuadratureGrid,
    ilevel: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
) -> f64 {
    let unit_phase_coefficients = unit_phase_coefficients_from_scaled(scaled_phase_coefficients);
    if unit_phase_coefficients[0] == 0.0 {
        return 0.0;
    }
    let max_phase_index = max_phase_coefficient_index(unit_phase_coefficients);
    if i_fourier > max_phase_index {
        return 0.0;
    }
    scattering_source_weighting_from_scaled_phase(
        unit_phase_coefficients,
        max_phase_index,
        ud,
        ilevel,
        i_fourier,
        geo,
        plm_basis,
    ) + absorption_interface_weighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        ilevel,
        use_pseudo_spherical,
        geo,
    )
}

fn aerosol_total_extinction_interface_weighting(
    scattering_weighting: f64,
    absorption_weighting: f64,
    aerosol_ssa: f64,
) -> f64 {
    aerosol_ssa * scattering_weighting + (1.0 - aerosol_ssa) * absorption_weighting
}

#[allow(clippy::too_many_arguments)]
pub fn calc_aerosol_optical_depth_weighting_with_basis(
    layers: &[LayerInput],
    rtm_quadrature: &RtmQuadratureGrid,
    ud: &[UdField],
    ud_sum_local: &[UdLocal],
    end_level: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
    adjacent_layer_phase_max_indices: Option<&[usize]>,
) -> f64 {
    let _ = adjacent_layer_phase_max_indices;
    if !rtm_quadrature.is_valid_for(layers.len()) {
        return 0.0;
    }

    if let Some(bounds) = active_aerosol_interior_bounds(rtm_quadrature, end_level) {
        if bounds.top <= bounds.bottom + 1 {
            return 0.0;
        }
        let aerosol_ssa = aerosol_single_scattering_albedo(layers);
        let needs_absorption_weighting = (1.0 - aerosol_ssa) != 0.0;
        let denominator = rtm_quadrature.levels[bounds.top - 1].altitude_km
            - rtm_quadrature.levels[bounds.bottom].altitude_km;
        if denominator <= 0.0 {
            return 0.0;
        }

        let mut integral = 0.0;
        let mut previous = aerosol_total_extinction_interface_weighting(
            scattering_coefficient_interface_weighting(
                rtm_quadrature.levels[bounds.bottom].aerosol_ksca_phase_above_per_km,
                ud,
                ud_sum_local,
                rtm_quadrature,
                bounds.bottom,
                i_fourier,
                use_pseudo_spherical,
                geo,
                plm_basis,
            ),
            if needs_absorption_weighting {
                absorption_interface_weighting(
                    ud,
                    ud_sum_local,
                    rtm_quadrature,
                    bounds.bottom,
                    use_pseudo_spherical,
                    geo,
                )
            } else {
                0.0
            },
            aerosol_ssa,
        );

        for ilevel in bounds.bottom + 1..bounds.top {
            let current = aerosol_total_extinction_interface_weighting(
                scattering_coefficient_interface_weighting(
                    rtm_quadrature.levels[ilevel].aerosol_ksca_phase_above_per_km,
                    ud,
                    ud_sum_local,
                    rtm_quadrature,
                    ilevel,
                    i_fourier,
                    use_pseudo_spherical,
                    geo,
                    plm_basis,
                ),
                if needs_absorption_weighting {
                    absorption_interface_weighting(
                        ud,
                        ud_sum_local,
                        rtm_quadrature,
                        ilevel,
                        use_pseudo_spherical,
                        geo,
                    )
                } else {
                    0.0
                },
                aerosol_ssa,
            );
            let dz = rtm_quadrature.levels[ilevel].altitude_km
                - rtm_quadrature.levels[ilevel - 1].altitude_km;
            if dz > 0.0 {
                integral += 0.5 * (previous + current) * dz;
            }
            previous = current;
        }
        return integral / denominator;
    }

    let state_index = jacobian::state_index(State::AerosolOpticalDepth);
    let mut weighting = 0.0;
    for ilevel in 0..=end_level {
        let level = &rtm_quadrature.levels[ilevel];
        if level.weight <= 0.0 {
            continue;
        }
        let scaled_phase_coefficients = level.ksca_phase_coefficient_jacobian[state_index];
        let d_sca_d_tau = scaled_phase_coefficients[0];
        if d_sca_d_tau == 0.0 {
            continue;
        }
        let source_max_phase_index = max_phase_coefficient_index(scaled_phase_coefficients);
        if i_fourier > source_max_phase_index {
            continue;
        }
        let source_weighting = scattering_source_weighting_from_scaled_phase(
            scaled_phase_coefficients,
            source_max_phase_index,
            ud,
            ilevel,
            i_fourier,
            geo,
            plm_basis,
        );
        let extinction_weighting = d_sca_d_tau
            * absorption_interface_weighting(
                ud,
                ud_sum_local,
                rtm_quadrature,
                ilevel,
                use_pseudo_spherical,
                geo,
            );
        weighting += level.weight * (source_weighting + extinction_weighting);
    }
    weighting
}

#[allow(clippy::too_many_arguments)]
pub fn calc_aerosol_layer_pressure_shift_weighting_with_basis(
    layers: &[LayerInput],
    rtm_quadrature: &RtmQuadratureGrid,
    ud: &[UdField],
    ud_sum_local: &[UdLocal],
    end_level: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
) -> f64 {
    if !rtm_quadrature.is_valid_for(layers.len()) {
        return 0.0;
    }
    let Some(bounds) = active_aerosol_interior_bounds(rtm_quadrature, end_level) else {
        return 0.0;
    };
    let aerosol_ssa = aerosol_single_scattering_albedo(layers);
    let top_sca_weighting = scattering_coefficient_interface_weighting(
        rtm_quadrature.levels[bounds.top].aerosol_ksca_phase_below_per_km,
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.top,
        i_fourier,
        use_pseudo_spherical,
        geo,
        plm_basis,
    );
    let bottom_sca_weighting = scattering_coefficient_interface_weighting(
        rtm_quadrature.levels[bounds.bottom].aerosol_ksca_phase_above_per_km,
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.bottom,
        i_fourier,
        use_pseudo_spherical,
        geo,
        plm_basis,
    );
    let ksca = rtm_quadrature.levels[bounds.top].aerosol_ksca_phase_below_per_km[0];
    let kabs = if aerosol_ssa > 0.0 {
        ksca * (1.0 - aerosol_ssa) / aerosol_ssa
    } else {
        0.0
    };
    if kabs == 0.0 {
        return (top_sca_weighting - bottom_sca_weighting) * ksca;
    }

    let top_abs_weighting = absorption_interface_weighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.top,
        use_pseudo_spherical,
        geo,
    );
    let bottom_abs_weighting = absorption_interface_weighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.bottom,
        use_pseudo_spherical,
        geo,
    );
    (top_sca_weighting - bottom_sca_weighting) * ksca
        + (top_abs_weighting - bottom_abs_weighting) * kabs
}

#[allow(clippy::too_many_arguments)]
fn phase_rows_for_level(
    layers: &[LayerInput],
    source_interface: SourceInterfaceInput,
    use_rtm_quadrature: bool,
    ilevel: usize,
    i_fourier: usize,
    phase_coefficients: phase_functions::PhaseCoefficients,
    source_max_phase_index: usize,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
    layer_phase_kernel_cache: Option<&[PhaseKernel]>,
    layer_phase_kernel_valid: Option<&[bool]>,
) -> ([f64; MAX_NMUTOT], [f64; MAX_NMUTOT], usize) {
    let view_idx = geo.view_idx();
    if !use_rtm_quadrature
        && let Some(above_index) = reuse_layer_kernel_index(layers, source_interface, ilevel)
        && let (Some(cache), Some(valid)) = (layer_phase_kernel_cache, layer_phase_kernel_valid)
    {
        let cache_index = above_index + 1;
        if cache_index < cache.len() && cache_index < valid.len() && valid[cache_index] {
            let z = cache[cache_index];
            let row_offset = view_idx * z.zplus.n;
            let mut zplus = [0.0; MAX_NMUTOT];
            let mut zmin = [0.0; MAX_NMUTOT];
            zplus[..z.zplus.n].copy_from_slice(&z.zplus.data[row_offset..row_offset + z.zplus.n]);
            zmin[..z.zmin.n].copy_from_slice(&z.zmin.data[row_offset..row_offset + z.zmin.n]);
            return (zplus, zmin, z.zplus.n);
        }
    }

    let rows = fill_zplus_zmin_row_from_basis_limited(
        i_fourier,
        &phase_coefficients,
        source_max_phase_index,
        geo,
        plm_basis,
        view_idx,
    );
    (rows.zplus, rows.zmin, rows.n)
}

pub fn total_scattering_optical_depth(layers: &[LayerInput]) -> f64 {
    layers
        .iter()
        .map(|layer| layer.scattering_optical_depth.max(0.0))
        .sum()
}

fn max_fourier_index(layers: &[LayerInput]) -> usize {
    layers
        .iter()
        .map(|layer| max_phase_coefficient_index(layer.phase_coefficients))
        .max()
        .unwrap_or(0)
}

fn max_fourier_index_interfaces(source_interfaces: &[SourceInterfaceInput]) -> usize {
    source_interfaces
        .iter()
        .map(|source_interface| {
            max_phase_coefficient_index(source_interface.phase_coefficients_above).max(
                max_phase_coefficient_index(source_interface.phase_coefficients_below),
            )
        })
        .max()
        .unwrap_or(0)
}

fn max_fourier_index_quadrature(rtm_quadrature: &RtmQuadratureGrid) -> usize {
    rtm_quadrature
        .levels
        .iter()
        .filter(|level| level.weight > 0.0 && level.ksca > 0.0)
        .map(|level| max_phase_coefficient_index(level.phase_coefficients))
        .max()
        .unwrap_or(0)
}

pub fn resolved_phase_coefficient_max(input: &ForwardInput) -> usize {
    let mut max_index = max_fourier_index(&input.layers);
    if input.rtm_quadrature.is_valid_for(input.layers.len()) {
        max_index = max_index.max(max_fourier_index_quadrature(&input.rtm_quadrature));
    } else if input.source_interfaces.len() == input.layers.len() + 1 {
        max_index = max_index.max(max_fourier_index_interfaces(&input.source_interfaces));
    }
    max_index
}

pub fn resolved_fourier_max(input: &ForwardInput, controls: RadiativeTransferControls) -> usize {
    if input.layers.is_empty() {
        return 0;
    }
    if (1.0 - input.muv) < 1.0e-5 || (1.0 - input.mu0) < 1.0e-5 {
        return 0;
    }
    let resolved_max = if input.rtm_quadrature.is_valid_for(input.layers.len()) {
        max_fourier_index_quadrature(&input.rtm_quadrature)
    } else if input.source_interfaces.len() == input.layers.len() + 1 {
        max_fourier_index_interfaces(&input.source_interfaces)
    } else {
        max_fourier_index(&input.layers)
    };
    controls
        .performance_thresholds
        .capped_fourier_max(resolved_max)
}
