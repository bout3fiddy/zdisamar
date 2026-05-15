use zdisamar::{
    forward_model::optical_properties::shared::phase_functions,
    input::{
        aerosol::Aerosol, atmosphere::Atmosphere, cloud::Cloud, reference::rayleigh, scene::Scene,
    },
};

#[test]
fn rayleigh_air_helpers_return_physical_positive_values() {
    let depol = rayleigh::depolarization_factor_air(760.0);
    assert!(depol > 0.0 && depol < 0.1);
    assert!(rayleigh::refractive_index_dry_air(760.0) > 1.0);
    assert!(rayleigh::cross_section_cm2(760.0) > 0.0);
    assert_eq!(
        rayleigh::scattering_optical_depth_for_column(760.0, -1.0),
        0.0
    );
}

#[test]
fn phase_coefficients_preserve_zero_and_compact_conventions() {
    let zero = phase_functions::zero_phase_coefficients();
    assert_eq!(zero[0], 1.0);
    assert_eq!(phase_functions::max_phase_coefficient_index(&zero), 0);

    let compact = phase_functions::phase_coefficients_from_compact([9.0, 0.2, 0.3, 0.4]);
    assert_eq!(compact[0], 1.0);
    assert_eq!(compact[1], 0.2);
    assert_eq!(compact[3], 0.4);
}

#[test]
fn hg_and_combined_phase_coefficients_match_expected_moments() {
    let hg = phase_functions::hg_phase_coefficients_with_threshold(0.5, 1.0e-12);
    assert_eq!(hg[0], 1.0);
    assert_eq!(hg[1], 1.5);
    assert!(phase_functions::max_phase_coefficient_index(&hg) > 1);

    let gas = phase_functions::gas_phase_coefficients_from_rayleigh2(0.5);
    let combined =
        phase_functions::combine_phase_coefficients_with_rayleigh2(0.5, 1.0, 1.0, 0.0, &hg, &gas);
    assert_eq!(combined[0], 1.0);
    assert_eq!(combined[1], 0.75);
    assert_eq!(combined[2], (0.5 + hg[2]) / 2.0);
}

#[test]
fn scene_phase_helpers_mix_particles_and_layer_depolarization() {
    let scene = Scene {
        atmosphere: Atmosphere {
            has_aerosols: true,
            has_clouds: true,
            ..Atmosphere::default()
        },
        aerosol: Aerosol {
            single_scatter_albedo: 0.8,
            asymmetry_factor: 0.6,
            ..Aerosol::default()
        },
        cloud: Cloud {
            single_scatter_albedo: 0.7,
            asymmetry_factor: 0.8,
            ..Cloud::default()
        },
        ..Scene::default()
    };
    let ssa = phase_functions::compute_single_scatter_albedo(&scene, 760.0);
    assert!((ssa - 0.83).abs() < 1.0e-14);
    let depol = phase_functions::compute_layer_depolarization(&scene, 1.0, 1.0, 2.0);
    assert!(depol > 0.0);
}
