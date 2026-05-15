use zdisamar::{
    forward_model::{
        jacobian::{self, State},
        optical_properties::shared::phase_functions,
        radiative_transfer::{
            common_route,
            common_types::{
                DispatchRequest, Error, ForwardInput, LayerInput, RadiativeTransferControls,
                ScatteringMode,
            },
            labos::{Workspace, execute, execute_with_workspace},
        },
    },
    input::scene::DerivativeMode,
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

fn scalar_route(
    scattering: ScatteringMode,
) -> zdisamar::forward_model::radiative_transfer::common_types::Route {
    common_route::prepare_route(DispatchRequest {
        rtm_controls: RadiativeTransferControls {
            scattering,
            n_streams: 4,
            ..RadiativeTransferControls::default()
        },
        ..DispatchRequest::default()
    })
    .unwrap()
}

#[test]
fn no_scattering_execute_matches_direct_surface_formula() {
    let route = scalar_route(ScatteringMode::None);
    let input = ForwardInput {
        mu0: 0.62,
        muv: 0.74,
        surface_albedo: 0.23,
        optical_depth: 0.31,
        ..ForwardInput::default()
    };

    let result = execute(route, &input).unwrap();
    let expected = input.surface_albedo
        * (-input.optical_depth / input.mu0).exp()
        * (-input.optical_depth / input.muv).exp();

    assert_close(result.toa_reflectance_factor, expected, 1.0e-14);
    assert!(result.jacobian.is_none());
}

#[test]
fn no_scattering_surface_albedo_tangent_matches_direct_path() {
    let mut route = scalar_route(ScatteringMode::None);
    route.derivative_mode = DerivativeMode::SemiAnalytical;
    route.derivative_state_mask = jacobian::state_mask(State::SurfaceAlbedo);
    let input = ForwardInput {
        mu0: 0.62,
        muv: 0.74,
        surface_albedo: 0.23,
        optical_depth: 0.31,
        ..ForwardInput::default()
    };

    let result = execute(route, &input).unwrap();
    let expected =
        (-input.optical_depth / input.mu0).exp() * (-input.optical_depth / input.muv).exp();

    assert_close(
        jacobian::get(result.jacobian.unwrap(), State::SurfaceAlbedo),
        expected,
        1.0e-14,
    );
}

#[test]
fn layer_resolved_execute_matches_workspace_and_stays_physical() {
    let route = scalar_route(ScatteringMode::Multiple);
    let mut phase = phase_functions::zero_phase_coefficients();
    phase[1] = 0.22;
    phase[2] = 0.05;
    let input = ForwardInput {
        mu0: 0.61,
        muv: 0.72,
        surface_albedo: 0.21,
        relative_azimuth_rad: 0.0,
        layers: vec![LayerInput {
            optical_depth: 0.18,
            scattering_optical_depth: 0.12,
            single_scatter_albedo: 0.7,
            solar_mu: 0.61,
            view_mu: 0.72,
            phase_coefficients: phase,
            ..LayerInput::default()
        }],
        optical_depth: 0.18,
        ..ForwardInput::default()
    };
    let plain = execute(route, &input).unwrap();
    let mut workspace = Workspace::new();
    let cached = execute_with_workspace(route, &input, Some(&mut workspace)).unwrap();

    assert_close(
        plain.toa_reflectance_factor,
        cached.toa_reflectance_factor,
        1.0e-14,
    );
    assert!(plain.toa_reflectance_factor >= 0.0);
    assert!(plain.toa_reflectance_factor <= 2.0);
}

#[test]
fn unported_aerosol_derivative_states_are_rejected_explicitly() {
    let mut route = scalar_route(ScatteringMode::Multiple);
    route.derivative_mode = DerivativeMode::SemiAnalytical;
    route.derivative_state_mask = jacobian::state_mask(State::AerosolOpticalDepth);
    let input = ForwardInput::default();

    assert_eq!(
        execute(route, &input),
        Err(Error::UnsupportedDerivativeMode)
    );
}
