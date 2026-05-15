use super::{
    phase_basis::{FourierPlmBasis, PhaseKernel, fill_zplus_zmin_row_from_basis_limited},
    types::{Geometry, MAX_NMUTOT, UdField},
};
use crate::forward_model::{
    optical_properties::shared::phase_functions::{self, PhaseCoefficients},
    radiative_transfer::{
        common_route,
        common_types::{
            ForwardInput, LayerInput, RadiativeTransferControls, RtmQuadratureGrid,
            SourceInterfaceInput,
        },
    },
};

struct PhaseRows {
    zplus: [f64; MAX_NMUTOT],
    zmin: [f64; MAX_NMUTOT],
}

pub fn fill_adjacent_layer_phase_max_indices(
    source_phase_max_indices: &mut [usize],
    layer_phase_max_indices: &[usize],
) {
    let nlayer = layer_phase_max_indices.len();
    debug_assert!(source_phase_max_indices.len() > nlayer);
    if nlayer == 0 {
        if let Some(first) = source_phase_max_indices.first_mut() {
            *first = 0;
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

pub fn calc_reflectance(ud: &[UdField], end_level: usize, geometry: &Geometry) -> f64 {
    let solar_col = 1;
    let view_idx = geometry.view_idx();
    ud[end_level].u.col[solar_col].get(view_idx)
}

pub fn calc_reflectance_tangent(
    ud_tangent: &[UdField],
    end_level: usize,
    geometry: &Geometry,
) -> f64 {
    calc_reflectance(ud_tangent, end_level, geometry)
}

pub fn calc_integrated_reflectance(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    rtm_quadrature: &RtmQuadratureGrid,
    ud: &[UdField],
    end_level: usize,
    i_fourier: usize,
    geometry: &Geometry,
) -> f64 {
    let max_phase_index = if rtm_quadrature.is_valid_for(layers.len()) {
        max_fourier_index(layers).max(max_fourier_index_quadrature(rtm_quadrature))
    } else {
        max_fourier_index(layers).max(max_fourier_index_interfaces(source_interfaces))
    };
    let plm_basis = FourierPlmBasis::init(i_fourier, max_phase_index, geometry);
    calc_integrated_reflectance_with_basis(
        layers,
        source_interfaces,
        rtm_quadrature,
        ud,
        end_level,
        i_fourier,
        geometry,
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
    geometry: &Geometry,
    plm_basis: &FourierPlmBasis,
    adjacent_layer_phase_max_indices: Option<&[usize]>,
    layer_phase_kernel_cache: Option<&[PhaseKernel]>,
    layer_phase_kernel_valid: Option<&[bool]>,
) -> f64 {
    let solar_col = 1;
    let view_idx = geometry.view_idx();
    let solar_idx = geometry.n_gauss + 1;
    let view_mu = geometry.u[view_idx].max(1.0e-12);
    let use_rtm_quadrature = rtm_quadrature.is_valid_for(layers.len());
    let mut reflectance = 0.0;

    for (ilevel, level) in ud[..=end_level].iter().copied().enumerate() {
        let source = level_source(
            layers,
            source_interfaces,
            rtm_quadrature,
            ilevel,
            use_rtm_quadrature,
        );
        let Some((source_rtm_weight, source_ksca, phase_coefficients)) = source else {
            continue;
        };

        let source_max_phase_index = source_phase_max_index(
            layers,
            source_interfaces,
            adjacent_layer_phase_max_indices,
            ilevel,
            use_rtm_quadrature,
        );
        if i_fourier > source_max_phase_index {
            continue;
        }

        let phase_rows = phase_rows_for_level(
            layers,
            source_interfaces,
            i_fourier,
            geometry,
            plm_basis,
            layer_phase_kernel_cache,
            layer_phase_kernel_valid,
            ilevel,
            source_max_phase_index,
            phase_coefficients,
            use_rtm_quadrature,
        );

        let mut pmin_ed = 0.0;
        for imu in 0..geometry.n_gauss {
            let mu = geometry.u[imu].max(1.0e-12);
            let pmin = (0.25 * phase_rows.zmin[imu] / view_mu) / mu;
            pmin_ed += pmin * level.d.col[solar_col].data[imu];
        }

        let solar_mu = geometry.u[solar_idx].max(1.0e-12);
        let pmin_direct = (0.25 * phase_rows.zmin[solar_idx] / view_mu) / solar_mu;
        pmin_ed += pmin_direct * level.e.data[solar_idx];

        let mut pplusst_u = 0.0;
        for imu in 0..geometry.n_gauss {
            let mu = geometry.u[imu].max(1.0e-12);
            let pplusst = (0.25 * phase_rows.zplus[imu] / view_mu) / mu;
            pplusst_u += pplusst * level.u.col[solar_col].data[imu];
        }

        reflectance +=
            source_rtm_weight * level.e.data[view_idx] * source_ksca * (pmin_ed + pplusst_u);
    }

    if i_fourier == 0 {
        // Vendor LABOS keeps the scalar direct term in the zero-Fourier closure.
        reflectance += ud[0].e.get(view_idx) * ud[0].u.col[solar_col].get(view_idx);
    }
    reflectance
}

fn level_source(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    rtm_quadrature: &RtmQuadratureGrid,
    ilevel: usize,
    use_rtm_quadrature: bool,
) -> Option<(f64, f64, PhaseCoefficients)> {
    if use_rtm_quadrature {
        let level = &rtm_quadrature.levels[ilevel];
        return (level.weight > 0.0 && level.ksca > 0.0).then_some((
            level.weight,
            level.ksca,
            level.phase_coefficients,
        ));
    }

    let source_interface = source_interface_at_level(layers, source_interfaces, ilevel);
    let (source_rtm_weight, source_ksca) =
        if source_interface.rtm_weight > 0.0 && source_interface.ksca_above > 0.0 {
            (source_interface.rtm_weight, source_interface.ksca_above)
        } else {
            (source_interface.source_weight, 1.0)
        };
    (source_rtm_weight > 0.0 && source_ksca > 0.0).then_some((
        source_rtm_weight,
        source_ksca,
        source_interface.phase_coefficients_above,
    ))
}

#[allow(clippy::too_many_arguments)]
fn phase_rows_for_level(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    i_fourier: usize,
    geometry: &Geometry,
    plm_basis: &FourierPlmBasis,
    layer_phase_kernel_cache: Option<&[PhaseKernel]>,
    layer_phase_kernel_valid: Option<&[bool]>,
    ilevel: usize,
    source_max_phase_index: usize,
    phase_coefficients: PhaseCoefficients,
    use_rtm_quadrature: bool,
) -> PhaseRows {
    let view_idx = geometry.view_idx();
    if !use_rtm_quadrature {
        let source_interface = source_interface_at_level(layers, source_interfaces, ilevel);
        if let Some(above_index) = reuse_layer_kernel_index(layers, source_interface, ilevel)
            && let (Some(cache), Some(valid)) = (layer_phase_kernel_cache, layer_phase_kernel_valid)
        {
            let cache_index = above_index + 1;
            if cache_index < cache.len() && cache_index < valid.len() && valid[cache_index] {
                return row_from_cached_kernel(&cache[cache_index], view_idx);
            }
        }
    }

    let row = fill_zplus_zmin_row_from_basis_limited(
        i_fourier,
        phase_coefficients,
        source_max_phase_index,
        geometry,
        plm_basis,
        view_idx,
    );
    PhaseRows {
        zplus: row.zplus,
        zmin: row.zmin,
    }
}

fn row_from_cached_kernel(kernel: &PhaseKernel, row_index: usize) -> PhaseRows {
    let n = kernel.zplus.n;
    let mut rows = PhaseRows {
        zplus: [0.0; MAX_NMUTOT],
        zmin: [0.0; MAX_NMUTOT],
    };
    let row_offset = row_index * n;
    rows.zplus[..n].copy_from_slice(&kernel.zplus.data[row_offset..row_offset + n]);
    rows.zmin[..n].copy_from_slice(&kernel.zmin.data[row_offset..row_offset + n]);
    rows
}

fn source_phase_max_index(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    adjacent_layer_phase_max_indices: Option<&[usize]>,
    ilevel: usize,
    use_rtm_quadrature: bool,
) -> usize {
    if let Some(indices) = adjacent_layer_phase_max_indices {
        return indices[ilevel];
    }
    if use_rtm_quadrature || !layers.is_empty() {
        return adjacent_layer_phase_coefficient_index(layers, ilevel);
    }
    max_interface_phase_coefficient_index(layers, source_interfaces, ilevel)
}

fn source_interface_at_level(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    ilevel: usize,
) -> SourceInterfaceInput {
    if source_interfaces.len() == layers.len() + 1 && ilevel < source_interfaces.len() {
        return source_interfaces[ilevel].clone();
    }
    common_route::source_interface_from_layers(layers, ilevel)
}

fn max_phase_coefficient_index(phase_coefficients: &PhaseCoefficients) -> usize {
    phase_functions::max_phase_coefficient_index(phase_coefficients)
}

fn max_interface_phase_coefficient_index(
    layers: &[LayerInput],
    source_interfaces: &[SourceInterfaceInput],
    ilevel: usize,
) -> usize {
    let source_interface = source_interface_at_level(layers, source_interfaces, ilevel);
    max_phase_coefficient_index(&source_interface.phase_coefficients_above).max(
        max_phase_coefficient_index(&source_interface.phase_coefficients_below),
    )
}

fn adjacent_layer_phase_coefficient_index(layers: &[LayerInput], ilevel: usize) -> usize {
    if layers.is_empty() {
        return 0;
    }
    if ilevel == 0 {
        return max_phase_coefficient_index(&layers[0].phase_coefficients);
    }
    if ilevel >= layers.len() {
        return max_phase_coefficient_index(&layers[layers.len() - 1].phase_coefficients);
    }
    max_phase_coefficient_index(&layers[ilevel - 1].phase_coefficients).max(
        max_phase_coefficient_index(&layers[ilevel].phase_coefficients),
    )
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
    (source_interface.phase_coefficients_above == layers[above_index].phase_coefficients)
        .then_some(above_index)
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
        .map(|layer| max_phase_coefficient_index(&layer.phase_coefficients))
        .max()
        .unwrap_or(0)
}

fn max_fourier_index_interfaces(source_interfaces: &[SourceInterfaceInput]) -> usize {
    source_interfaces
        .iter()
        .map(|source_interface| {
            max_phase_coefficient_index(&source_interface.phase_coefficients_above).max(
                max_phase_coefficient_index(&source_interface.phase_coefficients_below),
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
        .map(|level| max_phase_coefficient_index(&level.phase_coefficients))
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
