use super::{
    attenuation::{
        fill_attenuation, fill_attenuation_dynamic_with_grid, fill_attenuation_tangent_dynamic,
    },
    layers::{
        calc_rt_layers, calc_rt_layers_into_with_basis, calc_rt_layers_tangent_into_with_basis,
        fill_layer_effective_scattering_suffixes, fill_layer_phase_max_indices, fill_surface,
    },
    orders::{
        AttenuationLookup, OrdersWorkspace, orders_scat_into_with_active,
        orders_scat_into_with_active_local_sum, orders_scat_tangent, orders_scat_transport_into,
    },
    phase_basis::{FourierPlmBasis, PhaseKernel},
    reflectance::{
        calc_aerosol_layer_pressure_shift_weighting_with_basis,
        calc_aerosol_optical_depth_weighting_with_basis, calc_integrated_reflectance_with_basis,
        calc_reflectance, calc_reflectance_tangent, fill_adjacent_layer_phase_max_indices,
        resolved_fourier_max, resolved_phase_coefficient_max, total_scattering_optical_depth,
    },
    types::{Geometry, LayerRt, Mat, UdField},
    workspace::Workspace,
};
use crate::{
    forward_model::{
        jacobian::{self, State},
        optical_properties::shared::phase_functions,
        radiative_transfer::common_types::{
            Error, ForwardInput, ForwardResult, LayerInput, RadiativeTransferControls, Route,
            ScatteringMode,
        },
    },
    input::scene::DerivativeMode,
};

#[derive(Debug, Clone, PartialEq)]
struct LabosComputation {
    reflectance: f64,
    jacobian: jacobian::Vector,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct DirectSurfaceOnlyComputation {
    reflectance: f64,
    surface_albedo_tangent: f64,
}

pub fn execute(route: Route, input: &ForwardInput) -> Result<ForwardResult, Error> {
    execute_with_workspace(route, input, None)
}

pub fn execute_with_workspace(
    route: Route,
    input: &ForwardInput,
    workspace: Option<&mut Workspace>,
) -> Result<ForwardResult, Error> {
    let controls = route.rtm_controls;
    let compute_jacobian = route.derivative_mode != DerivativeMode::None;

    let wants_surface_albedo =
        compute_jacobian && jacobian::includes(route.derivative_state_mask, State::SurfaceAlbedo);
    let computation = if controls.scattering == ScatteringMode::None {
        let direct = direct_surface_only_resolved_with_workspace(
            input,
            controls,
            workspace,
            wants_surface_albedo,
        );
        let mut direct_jacobian = jacobian::zero();
        if wants_surface_albedo {
            jacobian::set(
                &mut direct_jacobian,
                State::SurfaceAlbedo,
                direct.surface_albedo_tangent,
            );
        }
        LabosComputation {
            reflectance: direct.reflectance,
            jacobian: direct_jacobian,
        }
    } else if !input.layers.is_empty() {
        layer_resolved_labos_with_workspace(
            input,
            controls,
            compute_jacobian,
            route.derivative_state_mask,
            workspace,
        )?
    } else {
        single_layer_labos(
            input,
            controls,
            compute_jacobian,
            route.derivative_state_mask,
        )?
    };

    Ok(ForwardResult {
        family: route.family,
        regime: route.regime,
        execution_mode: route.execution_mode,
        derivative_mode: route.derivative_mode,
        toa_reflectance_factor: computation.reflectance,
        jacobian: (route.derivative_mode != DerivativeMode::None).then_some(computation.jacobian),
    })
}

fn direct_surface_only(
    input: &ForwardInput,
    compute_surface_albedo_tangent: bool,
) -> DirectSurfaceOnlyComputation {
    let mu0 = input.mu0.max(0.05);
    let muv = input.muv.max(0.05);
    let direct = (-input.optical_depth / mu0).exp() * (-input.optical_depth / muv).exp();
    let reflectance = input.surface_albedo * direct;
    DirectSurfaceOnlyComputation {
        reflectance: reflectance.clamp(0.0, 2.0),
        surface_albedo_tangent: if compute_surface_albedo_tangent
            && (0.0..2.0).contains(&reflectance)
        {
            direct
        } else {
            0.0
        },
    }
}

fn direct_surface_only_resolved_with_workspace(
    input: &ForwardInput,
    controls: RadiativeTransferControls,
    workspace: Option<&mut Workspace>,
    compute_surface_albedo_tangent: bool,
) -> DirectSurfaceOnlyComputation {
    if input.layers.is_empty() {
        return direct_surface_only(input, compute_surface_albedo_tangent);
    }

    let mu0 = input.mu0.max(0.05);
    let muv = input.muv.max(0.05);
    let geometry = workspace
        .map(|scratch| *scratch.geometry(usize::from(controls.n_gauss()), mu0, muv))
        .unwrap_or_else(|| Geometry::init(usize::from(controls.n_gauss()), mu0, muv));
    let attenuation = fill_attenuation_dynamic_with_grid(
        &input.layers,
        &input.pseudo_spherical_grid,
        &geometry,
        controls.use_spherical_correction,
    );

    let view_idx = geometry.view_idx();
    let solar_idx = geometry.n_gauss + 1;
    let surface = fill_surface(0, input.surface_albedo, &geometry);
    let mut upward_path = 1.0;
    for ilevel in 1..=input.layers.len() {
        upward_path *= attenuation.get(view_idx, ilevel - 1, ilevel);
    }

    let path = attenuation.get(solar_idx, input.layers.len(), 0) * upward_path;
    let reflectance = surface.r.get(view_idx, solar_idx) * path;
    let surface_albedo_tangent =
        if compute_surface_albedo_tangent && (0.0..2.0).contains(&reflectance) {
            let surface_derivative = fill_surface(0, 1.0, &geometry);
            surface_derivative.r.get(view_idx, solar_idx) * path
        } else {
            0.0
        };

    DirectSurfaceOnlyComputation {
        reflectance: reflectance.clamp(0.0, 2.0),
        surface_albedo_tangent,
    }
}

fn layer_resolved_labos_with_workspace(
    input: &ForwardInput,
    controls: RadiativeTransferControls,
    compute_jacobian: bool,
    derivative_state_mask: jacobian::StateMask,
    workspace: Option<&mut Workspace>,
) -> Result<LabosComputation, Error> {
    let nlayer = input.layers.len();
    if nlayer == 0 {
        return Ok(LabosComputation {
            reflectance: 0.0,
            jacobian: jacobian::zero(),
        });
    }
    let use_integrated_source = controls.integrate_source_function
        && nlayer > 1
        && (input.source_interfaces.len() == nlayer + 1
            || input.rtm_quadrature.is_valid_for(input.layers.len()));
    if compute_jacobian && !use_integrated_source && controls.use_spherical_correction {
        return Err(Error::UnsupportedDerivativeMode);
    }

    let wants_surface_albedo =
        compute_jacobian && jacobian::includes(derivative_state_mask, State::SurfaceAlbedo);
    let mu0 = input.mu0.max(0.05);
    let muv = input.muv.max(0.05);
    let geometry = workspace
        .map(|scratch| *scratch.geometry(usize::from(controls.n_gauss()), mu0, muv))
        .unwrap_or_else(|| Geometry::init(usize::from(controls.n_gauss()), mu0, muv));
    let attenuation = fill_attenuation_dynamic_with_grid(
        &input.layers,
        &input.pseudo_spherical_grid,
        &geometry,
        controls.use_spherical_correction,
    );
    let mut rt = vec![zero_layer_rt(geometry.nmutot); nlayer + 1];
    let num_orders_max = usize::from(
        controls.resolved_num_orders_max(total_scattering_optical_depth(&input.layers)),
    );
    let fourier_max = resolved_fourier_max(input, controls);
    let phase_max = resolved_phase_coefficient_max(input);
    let mut orders_workspace = OrdersWorkspace::new(nlayer + 1);
    let mut layer_phase_max_indices = vec![0; nlayer];
    fill_layer_phase_max_indices(&mut layer_phase_max_indices, &input.layers);
    let mut layer_effective_scattering_suffixes = vec![0.0; nlayer * super::types::MAX_PHASE_COEF];
    fill_layer_effective_scattering_suffixes(
        &mut layer_effective_scattering_suffixes,
        &input.layers,
        &layer_phase_max_indices,
    );
    let mut adjacent_layer_phase_max_indices = vec![0; nlayer + 1];
    fill_adjacent_layer_phase_max_indices(
        &mut adjacent_layer_phase_max_indices,
        &layer_phase_max_indices,
    );
    let mut phase_kernel_cache =
        use_integrated_source.then(|| vec![zero_phase_kernel(geometry.nmutot); nlayer + 1]);
    let mut phase_kernel_valid = use_integrated_source.then(|| vec![false; nlayer + 1]);

    let mut reflectance = 0.0;
    let mut surface_albedo_tangent = 0.0;
    let wants_aerosol_optical_depth =
        compute_jacobian && jacobian::includes(derivative_state_mask, State::AerosolOpticalDepth);
    let wants_aerosol_layer_mid_pressure = compute_jacobian
        && jacobian::includes(derivative_state_mask, State::AerosolLayerMidPressureHpa);
    let mut aerosol_optical_depth_tangent = 0.0;
    let mut aerosol_layer_mid_pressure_tangent = 0.0;
    for i_fourier in 0..=fourier_max {
        let plm_basis = FourierPlmBasis::init(i_fourier, phase_max, &geometry);
        calc_rt_layers_into_with_basis(
            &mut rt,
            &input.layers,
            i_fourier,
            &geometry,
            controls,
            &plm_basis,
            Some(&layer_phase_max_indices),
            Some(&layer_effective_scattering_suffixes),
            phase_kernel_cache.as_deref_mut(),
            phase_kernel_valid.as_deref_mut(),
            Some(&mut orders_workspace.rt_active),
        );
        rt[0] = fill_surface(i_fourier, input.surface_albedo, &geometry);
        orders_workspace.rt_active[0] = i_fourier == 0 && input.surface_albedo != 0.0;

        let orders_result = if use_integrated_source && compute_jacobian {
            orders_scat_into_with_active_local_sum(
                &mut orders_workspace,
                0,
                nlayer,
                &geometry,
                &attenuation,
                &rt,
                controls,
                num_orders_max,
            )
        } else if use_integrated_source {
            orders_scat_into_with_active(
                &mut orders_workspace,
                0,
                nlayer,
                &geometry,
                &attenuation,
                &rt,
                controls,
                num_orders_max,
            )
        } else {
            orders_scat_transport_into(
                &mut orders_workspace,
                0,
                nlayer,
                &geometry,
                &attenuation,
                &rt,
                controls,
                num_orders_max,
            )
        };

        let refl_fc = if use_integrated_source {
            calc_integrated_reflectance_with_basis(
                &input.layers,
                &input.source_interfaces,
                &input.rtm_quadrature,
                orders_result.ud,
                nlayer,
                i_fourier,
                &geometry,
                &plm_basis,
                Some(&adjacent_layer_phase_max_indices),
                phase_kernel_cache.as_deref(),
                phase_kernel_valid.as_deref(),
            )
        } else {
            calc_reflectance(orders_result.ud, nlayer, &geometry)
        };
        let fourier_weight = if i_fourier == 0 {
            1.0
        } else {
            2.0 * (i_fourier as f64 * input.relative_azimuth_rad).cos()
        };
        reflectance += fourier_weight * refl_fc;
        if wants_surface_albedo && i_fourier == 0 {
            surface_albedo_tangent +=
                surface_albedo_weighting_function(orders_result.ud, &geometry);
        }
        if wants_aerosol_optical_depth {
            let tangent_refl_fc = if use_integrated_source {
                calc_aerosol_optical_depth_weighting_with_basis(
                    &input.layers,
                    &input.rtm_quadrature,
                    orders_result.ud,
                    orders_result.ud_sum_local,
                    nlayer,
                    i_fourier,
                    controls.use_spherical_correction,
                    &geometry,
                    &plm_basis,
                    Some(&adjacent_layer_phase_max_indices),
                )
            } else {
                non_integrated_reflectance_tangent(
                    &input.layers,
                    State::AerosolOpticalDepth,
                    i_fourier,
                    &geometry,
                    &attenuation,
                    &rt,
                    controls,
                    &plm_basis,
                    num_orders_max,
                )
            };
            aerosol_optical_depth_tangent += fourier_weight * tangent_refl_fc;
        }
        if wants_aerosol_layer_mid_pressure {
            let pressure_tangent_refl_fc = if use_integrated_source {
                calc_aerosol_layer_pressure_shift_weighting_with_basis(
                    &input.layers,
                    &input.rtm_quadrature,
                    orders_result.ud,
                    orders_result.ud_sum_local,
                    nlayer,
                    i_fourier,
                    controls.use_spherical_correction,
                    &geometry,
                    &plm_basis,
                )
            } else {
                if !has_layer_jacobian(&input.layers, State::AerosolLayerMidPressureHpa) {
                    return Err(Error::UnsupportedDerivativeMode);
                }
                non_integrated_reflectance_tangent(
                    &input.layers,
                    State::AerosolLayerMidPressureHpa,
                    i_fourier,
                    &geometry,
                    &attenuation,
                    &rt,
                    controls,
                    &plm_basis,
                    num_orders_max,
                )
            };
            aerosol_layer_mid_pressure_tangent += fourier_weight * pressure_tangent_refl_fc;
        }
        if i_fourier >= usize::from(controls.performance_thresholds.fourier_floor_scalar)
            && refl_fc.abs()
                <= controls
                    .performance_thresholds
                    .fourier_tail_reflectance_epsilon
        {
            break;
        }
    }

    let mut result_jacobian = jacobian::zero();
    if wants_surface_albedo {
        jacobian::set(
            &mut result_jacobian,
            State::SurfaceAlbedo,
            surface_albedo_tangent,
        );
    }
    if wants_aerosol_optical_depth {
        jacobian::set(
            &mut result_jacobian,
            State::AerosolOpticalDepth,
            aerosol_optical_depth_tangent,
        );
    }
    if wants_aerosol_layer_mid_pressure {
        jacobian::set(
            &mut result_jacobian,
            State::AerosolLayerMidPressureHpa,
            aerosol_layer_mid_pressure_tangent,
        );
    }
    Ok(LabosComputation {
        reflectance: reflectance.clamp(0.0, 2.0),
        jacobian: result_jacobian,
    })
}

#[allow(clippy::too_many_arguments)]
fn non_integrated_reflectance_tangent<A: AttenuationLookup>(
    layers: &[LayerInput],
    state: State,
    i_fourier: usize,
    geometry: &Geometry,
    attenuation: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    plm_basis: &FourierPlmBasis,
    num_orders_max: usize,
) -> f64 {
    let attenuation_tangent = fill_attenuation_tangent_dynamic(layers, state, geometry);
    let mut rt_tangent = vec![zero_layer_rt(geometry.nmutot); layers.len() + 1];
    calc_rt_layers_tangent_into_with_basis(
        &mut rt_tangent,
        layers,
        state,
        i_fourier,
        geometry,
        controls,
        plm_basis,
    );
    let tangent_orders = orders_scat_tangent(
        0,
        layers.len(),
        geometry,
        attenuation,
        &attenuation_tangent,
        rt,
        &rt_tangent,
        controls,
        num_orders_max,
    );
    calc_reflectance_tangent(&tangent_orders.ud, layers.len(), geometry)
}

fn has_layer_jacobian(layers: &[LayerInput], state: State) -> bool {
    layers.iter().any(|layer| {
        jacobian::get(layer.optical_depth_jacobian, state) != 0.0
            || jacobian::get(layer.scattering_optical_depth_jacobian, state) != 0.0
            || jacobian::get(layer.single_scatter_albedo_jacobian, state) != 0.0
    })
}

fn single_layer_labos(
    input: &ForwardInput,
    controls: RadiativeTransferControls,
    compute_jacobian: bool,
    derivative_state_mask: jacobian::StateMask,
) -> Result<LabosComputation, Error> {
    let mu0 = input.mu0.max(0.05);
    let muv = input.muv.max(0.05);
    let geometry = Geometry::init(usize::from(controls.n_gauss()), mu0, muv);
    let layer = LayerInput {
        optical_depth: input.optical_depth,
        single_scatter_albedo: input.single_scatter_albedo,
        solar_mu: mu0,
        view_mu: muv,
        phase_coefficients: phase_functions::zero_phase_coefficients(),
        ..LayerInput::default()
    };
    let num_orders_max =
        usize::from(controls.resolved_num_orders_max(layer.scattering_optical_depth));
    let layers = [layer];
    let attenuation = fill_attenuation(&layers, &geometry, controls.use_spherical_correction);
    let fourier_max = resolved_fourier_max(input, controls);
    let wants_surface_albedo =
        compute_jacobian && jacobian::includes(derivative_state_mask, State::SurfaceAlbedo);

    let mut reflectance = 0.0;
    let mut surface_albedo_tangent = 0.0;
    let mut orders_workspace = OrdersWorkspace::new(2);
    for i_fourier in 0..=fourier_max {
        let mut rt = calc_rt_layers(&layers, i_fourier, &geometry, controls);
        rt[0] = fill_surface(i_fourier, input.surface_albedo, &geometry);
        let orders_result = orders_scat_transport_into(
            &mut orders_workspace,
            0,
            1,
            &geometry,
            &attenuation,
            &rt[..2],
            controls,
            num_orders_max,
        );
        let refl_fc = calc_reflectance(orders_result.ud, 1, &geometry);
        let fourier_weight = if i_fourier == 0 {
            1.0
        } else {
            2.0 * (i_fourier as f64 * input.relative_azimuth_rad).cos()
        };
        reflectance += fourier_weight * refl_fc;
        if wants_surface_albedo && i_fourier == 0 {
            surface_albedo_tangent +=
                surface_albedo_weighting_function(orders_result.ud, &geometry);
        }
    }

    let mut result_jacobian = jacobian::zero();
    if wants_surface_albedo {
        jacobian::set(
            &mut result_jacobian,
            State::SurfaceAlbedo,
            surface_albedo_tangent,
        );
    }
    Ok(LabosComputation {
        reflectance: reflectance.clamp(0.0, 2.0),
        jacobian: result_jacobian,
    })
}

fn surface_albedo_weighting_function(ud: &[UdField], geometry: &Geometry) -> f64 {
    let surface_level = 0;
    let view_col = 0;
    let solar_col = 1;
    let mut diffuse_view = 0.0;
    let mut diffuse_solar = 0.0;
    for i_gauss in 0..geometry.n_gauss {
        diffuse_view += ud[surface_level].d.col[view_col].get(i_gauss) * geometry.w[i_gauss];
        diffuse_solar += ud[surface_level].d.col[solar_col].get(i_gauss) * geometry.w[i_gauss];
    }
    let view_direct = ud[surface_level].e.get(geometry.view_idx());
    let solar_direct = ud[surface_level].e.get(geometry.n_gauss + 1);
    (view_direct + diffuse_view) * (solar_direct + diffuse_solar)
}

fn zero_layer_rt(n: usize) -> LayerRt {
    LayerRt {
        r: Mat::zero(n),
        t: Mat::zero(n),
    }
}

fn zero_phase_kernel(n: usize) -> PhaseKernel {
    PhaseKernel {
        zplus: Mat::zero(n),
        zmin: Mat::zero(n),
    }
}
