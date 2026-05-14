use crate::{
    forward_model::{
        jacobian::{self, State, StateMask, Vector},
        optical_properties::shared::phase_functions,
        radiative_transfer::{
            Error, ForwardInput, ForwardResult, LayerInput, RadiativeTransferControls, Result,
            Route, ScatteringMode, TransportFamily,
        },
    },
    input::DerivativeMode,
};

use super::{
    FourierPlmBasis, Geometry, LayerRt, Mat, OrdersWorkspace, PhaseKernel,
    attenuation::{
        fill_attenuation, fill_attenuation_dynamic_with_grid, fill_attenuation_tangent_dynamic,
    },
    calc_aerosol_layer_pressure_shift_weighting_with_basis,
    calc_aerosol_optical_depth_weighting_with_basis, calc_integrated_reflectance_with_basis,
    calc_reflectance, calc_reflectance_tangent, calc_rt_layers, calc_rt_layers_into_with_basis,
    calc_rt_layers_tangent_into_with_basis, fill_surface, orders_scat_into,
    orders_scat_into_with_local_sum, orders_scat_tangent, orders_scat_transport_into,
    resolved_fourier_max, resolved_phase_coefficient_max, total_scattering_optical_depth,
};

#[derive(Debug, Clone, Copy, PartialEq)]
struct LabosComputation {
    reflectance: f64,
    jacobian: Vector,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct DirectSurfaceOnlyComputation {
    reflectance: f64,
    surface_albedo_tangent: f64,
}

pub fn execute(route: Route, input: &ForwardInput) -> Result<ForwardResult> {
    assert_eq!(route.family, TransportFamily::Labos);

    let controls = route.rtm_controls;
    let compute_jacobian = route.derivative_mode != DerivativeMode::None;
    let wants_surface_albedo =
        compute_jacobian && jacobian::includes(route.derivative_state_mask, State::SurfaceAlbedo);
    let computation = if controls.scattering == ScatteringMode::None {
        let direct = direct_surface_only_resolved(input, controls, wants_surface_albedo)?;
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
    } else if input.layers.is_empty() {
        single_layer_labos(
            input,
            controls,
            compute_jacobian,
            route.derivative_state_mask,
        )?
    } else {
        layer_resolved_labos(
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
        jacobian: match route.derivative_mode {
            DerivativeMode::None => None,
            DerivativeMode::SemiAnalytical | DerivativeMode::Numerical => {
                Some(computation.jacobian)
            }
        },
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

fn direct_surface_only_resolved(
    input: &ForwardInput,
    controls: RadiativeTransferControls,
    compute_surface_albedo_tangent: bool,
) -> Result<DirectSurfaceOnlyComputation> {
    if input.layers.is_empty() {
        return Ok(direct_surface_only(input, compute_surface_albedo_tangent));
    }

    let mu0 = input.mu0.max(0.05);
    let muv = input.muv.max(0.05);
    let geo = Geometry::init(usize::from(controls.n_gauss()), mu0, muv)
        .map_err(|_| Error::UnsupportedRadiativeTransferControls)?;
    let atten = fill_attenuation_dynamic_with_grid(
        &input.layers,
        &input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    let view_idx = geo.view_idx();
    let solar_idx = geo.n_gauss + 1;
    let surface = fill_surface(0, input.surface_albedo, &geo);
    let mut upward_path = 1.0;
    for ilevel in 1..=input.layers.len() {
        upward_path *= atten.get(view_idx, ilevel - 1, ilevel);
    }

    let path = atten.get(solar_idx, input.layers.len(), 0) * upward_path;
    let reflectance = surface.r.get(view_idx, solar_idx) * path;
    let surface_albedo_tangent =
        if compute_surface_albedo_tangent && (0.0..2.0).contains(&reflectance) {
            let surface_derivative = fill_surface(0, 1.0, &geo);
            surface_derivative.r.get(view_idx, solar_idx) * path
        } else {
            0.0
        };
    Ok(DirectSurfaceOnlyComputation {
        reflectance: reflectance.clamp(0.0, 2.0),
        surface_albedo_tangent,
    })
}

fn layer_resolved_labos(
    input: &ForwardInput,
    controls: RadiativeTransferControls,
    compute_jacobian: bool,
    derivative_state_mask: StateMask,
) -> Result<LabosComputation> {
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

    let mu0 = input.mu0.max(0.05);
    let muv = input.muv.max(0.05);
    let geo = Geometry::init(usize::from(controls.n_gauss()), mu0, muv)
        .map_err(|_| Error::UnsupportedRadiativeTransferControls)?;
    let atten = fill_attenuation_dynamic_with_grid(
        &input.layers,
        &input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    let mut rt = vec![zero_layer_rt(geo.nmutot); nlayer + 1];
    let num_orders_max = usize::from(
        controls.resolved_num_orders_max(total_scattering_optical_depth(&input.layers)),
    );
    let fourier_max = resolved_fourier_max(input, controls);
    let phase_max = resolved_phase_coefficient_max(input);
    let wants_surface_albedo =
        compute_jacobian && jacobian::includes(derivative_state_mask, State::SurfaceAlbedo);
    let wants_aerosol_optical_depth =
        compute_jacobian && jacobian::includes(derivative_state_mask, State::AerosolOpticalDepth);
    let wants_aerosol_layer_mid_pressure = compute_jacobian
        && jacobian::includes(derivative_state_mask, State::AerosolLayerMidPressureHpa);
    let mut reflectance = 0.0;
    let mut surface_albedo_tangent = 0.0;
    let mut aerosol_optical_depth_tangent = 0.0;
    let mut aerosol_layer_mid_pressure_tangent = 0.0;
    let mut orders_workspace = OrdersWorkspace::new(nlayer + 1, geo.nmutot);
    let mut layer_phase_kernels = if use_integrated_source {
        Some(vec![
            PhaseKernel {
                zplus: Mat::zero(geo.nmutot),
                zmin: Mat::zero(geo.nmutot),
            };
            nlayer + 1
        ])
    } else {
        None
    };
    let mut layer_phase_kernel_valid = if use_integrated_source {
        Some(vec![false; nlayer + 1])
    } else {
        None
    };

    for i_fourier in 0..=fourier_max {
        let plm_basis = FourierPlmBasis::init(i_fourier, phase_max, &geo);
        calc_rt_layers_into_with_basis(
            &mut rt,
            &input.layers,
            i_fourier,
            &geo,
            controls,
            &plm_basis,
            None,
            None,
            layer_phase_kernels.as_deref_mut(),
            layer_phase_kernel_valid.as_deref_mut(),
            None,
        );
        rt[0] = fill_surface(i_fourier, input.surface_albedo, &geo);

        let orders_result = if use_integrated_source && compute_jacobian {
            orders_scat_into_with_local_sum(
                &mut orders_workspace,
                0,
                nlayer,
                &geo,
                &atten,
                &rt,
                controls,
                num_orders_max,
            )
        } else if use_integrated_source {
            orders_scat_into(
                &mut orders_workspace,
                0,
                nlayer,
                &geo,
                &atten,
                &rt,
                controls,
                num_orders_max,
            )
        } else {
            orders_scat_transport_into(
                &mut orders_workspace,
                0,
                nlayer,
                &geo,
                &atten,
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
                &geo,
                &plm_basis,
                None,
                layer_phase_kernels.as_deref(),
                layer_phase_kernel_valid.as_deref(),
            )
        } else {
            calc_reflectance(orders_result.ud, nlayer, &geo)
        };
        let fourier_weight = if i_fourier == 0 {
            1.0
        } else {
            2.0 * ((i_fourier as f64) * input.relative_azimuth_rad).cos()
        };
        reflectance += fourier_weight * refl_fc;

        if wants_surface_albedo && i_fourier == 0 {
            surface_albedo_tangent += surface_albedo_weighting_function(orders_result.ud, &geo);
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
                    &geo,
                    &plm_basis,
                    None,
                )
            } else {
                non_integrated_reflectance_tangent(
                    &input.layers,
                    State::AerosolOpticalDepth,
                    i_fourier,
                    &geo,
                    &atten,
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
                    &geo,
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
                    &geo,
                    &atten,
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
    jacobian::set(
        &mut result_jacobian,
        State::SurfaceAlbedo,
        surface_albedo_tangent,
    );
    jacobian::set(
        &mut result_jacobian,
        State::AerosolOpticalDepth,
        aerosol_optical_depth_tangent,
    );
    jacobian::set(
        &mut result_jacobian,
        State::AerosolLayerMidPressureHpa,
        aerosol_layer_mid_pressure_tangent,
    );
    Ok(LabosComputation {
        reflectance: reflectance.clamp(0.0, 2.0),
        jacobian: result_jacobian,
    })
}

#[allow(clippy::too_many_arguments)]
fn non_integrated_reflectance_tangent<A>(
    layers: &[LayerInput],
    state: State,
    i_fourier: usize,
    geo: &Geometry,
    atten: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    plm_basis: &FourierPlmBasis,
    num_orders_max: usize,
) -> f64
where
    A: super::AttenuationAccess,
{
    let atten_tangent = fill_attenuation_tangent_dynamic(layers, state, geo);
    let mut rt_tangent = vec![zero_layer_rt(geo.nmutot); layers.len() + 1];
    calc_rt_layers_tangent_into_with_basis(
        &mut rt_tangent,
        layers,
        state,
        i_fourier,
        geo,
        controls,
        plm_basis,
    );
    let tangent_orders = orders_scat_tangent(
        0,
        layers.len(),
        geo,
        atten,
        &atten_tangent,
        rt,
        &rt_tangent,
        controls,
        num_orders_max,
    );
    calc_reflectance_tangent(&tangent_orders.ud, layers.len(), geo)
}

fn single_layer_labos(
    input: &ForwardInput,
    controls: RadiativeTransferControls,
    compute_jacobian: bool,
    derivative_state_mask: StateMask,
) -> Result<LabosComputation> {
    let mu0 = input.mu0.max(0.05);
    let muv = input.muv.max(0.05);
    let geo = Geometry::init(usize::from(controls.n_gauss()), mu0, muv)
        .map_err(|_| Error::UnsupportedRadiativeTransferControls)?;
    let layer = LayerInput {
        optical_depth: input.optical_depth,
        single_scatter_albedo: input.single_scatter_albedo,
        solar_mu: mu0,
        view_mu: muv,
        phase_coefficients: phase_functions::zero_phase_coefficients(),
        ..LayerInput::default()
    };
    let layers = [layer];
    let atten = fill_attenuation(&layers, &geo, controls.use_spherical_correction);
    let num_orders_max =
        usize::from(controls.resolved_num_orders_max(layer.scattering_optical_depth));
    let fourier_max = resolved_fourier_max(input, controls);
    let wants_surface_albedo =
        compute_jacobian && jacobian::includes(derivative_state_mask, State::SurfaceAlbedo);
    let mut reflectance = 0.0;
    let mut surface_albedo_tangent = 0.0;
    let mut orders_workspace = OrdersWorkspace::new(2, geo.nmutot);

    for i_fourier in 0..=fourier_max {
        let mut rt = calc_rt_layers(&layers, i_fourier, &geo, controls);
        rt[0] = fill_surface(i_fourier, input.surface_albedo, &geo);
        let orders_result = orders_scat_transport_into(
            &mut orders_workspace,
            0,
            1,
            &geo,
            &atten,
            &rt,
            controls,
            num_orders_max,
        );
        let refl_fc = calc_reflectance(orders_result.ud, 1, &geo);
        let fourier_weight = if i_fourier == 0 {
            1.0
        } else {
            2.0 * ((i_fourier as f64) * input.relative_azimuth_rad).cos()
        };
        reflectance += fourier_weight * refl_fc;
        if wants_surface_albedo && i_fourier == 0 {
            surface_albedo_tangent += surface_albedo_weighting_function(orders_result.ud, &geo);
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

fn has_layer_jacobian(layers: &[LayerInput], state: State) -> bool {
    layers.iter().any(|layer| {
        jacobian::get(layer.optical_depth_jacobian, state) != 0.0
            || jacobian::get(layer.scattering_optical_depth_jacobian, state) != 0.0
            || jacobian::get(layer.single_scatter_albedo_jacobian, state) != 0.0
    })
}

fn surface_albedo_weighting_function(ud: &[super::UdField], geo: &Geometry) -> f64 {
    let surface_level = 0;
    let view_col = 0;
    let solar_col = 1;
    let mut diffuse_view = 0.0;
    let mut diffuse_solar = 0.0;
    for i_gauss in 0..geo.n_gauss {
        diffuse_view += ud[surface_level].d.col[view_col].get(i_gauss) * geo.w[i_gauss];
        diffuse_solar += ud[surface_level].d.col[solar_col].get(i_gauss) * geo.w[i_gauss];
    }
    let view_direct = ud[surface_level].e.get(geo.view_idx());
    let solar_direct = ud[surface_level].e.get(geo.n_gauss + 1);
    (view_direct + diffuse_view) * (solar_direct + diffuse_solar)
}

fn zero_layer_rt(n: usize) -> LayerRt {
    LayerRt {
        r: Mat::zero(n),
        t: Mat::zero(n),
    }
}
