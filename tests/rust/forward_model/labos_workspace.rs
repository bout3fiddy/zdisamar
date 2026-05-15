use zdisamar::forward_model::{
    optical_properties::shared::phase_functions::{self, PhaseCoefficients},
    radiative_transfer::{
        common_types::{LayerInput, PseudoSphericalGrid},
        labos::{MAX_PHASE_COEF, Workspace},
    },
};

fn phase_coefficients(entries: &[(usize, f64)]) -> PhaseCoefficients {
    let mut coefficients = phase_functions::zero_phase_coefficients();
    for &(index, value) in entries {
        coefficients[index] = value;
    }
    coefficients
}

#[test]
fn geometry_cache_reports_hits_and_invalidates_phase_dependent_caches() {
    let mut workspace = Workspace::new();

    let first_hit = workspace.geometry_with_status(4, 0.58, 0.64).hit;
    let second_hit = workspace.geometry_with_status(4, 0.58, 0.64).hit;
    let geometry = *workspace.geometry(4, 0.58, 0.64);
    assert!(!first_hit);
    assert!(second_hit);

    let first_basis = workspace.fourier_plm_basis_with_status(1, 2, &geometry);
    assert!(!first_basis.hit);
    assert!(!first_basis.extended);

    let changed_geometry_hit = workspace.geometry_with_status(4, 0.59, 0.64).hit;
    assert!(!changed_geometry_hit);

    let changed_geometry = *workspace.geometry(4, 0.59, 0.64);
    let basis_after_geometry_change =
        workspace.fourier_plm_basis_with_status(1, 2, &changed_geometry);
    assert!(!basis_after_geometry_change.hit);
}

#[test]
fn fourier_plm_basis_cache_reports_hits_and_extensions() {
    let mut workspace = Workspace::new();
    let geometry = *workspace.geometry(4, 0.58, 0.64);

    let first = workspace.fourier_plm_basis_with_status(1, 2, &geometry);
    assert!(!first.hit);
    assert!(!first.extended);
    assert_eq!(first.plm_basis.max_phase_index, 2);

    let second = workspace.fourier_plm_basis_with_status(1, 2, &geometry);
    assert!(second.hit);
    assert!(!second.extended);

    let extended = workspace.fourier_plm_basis_with_status(1, 4, &geometry);
    assert!(!extended.hit);
    assert!(extended.extended);
    assert_eq!(extended.plm_basis.max_phase_index, 4);
}

#[test]
fn workspace_scratch_buffers_resize_to_requested_shapes() {
    let mut workspace = Workspace::new();
    let geometry = *workspace.geometry(4, 0.58, 0.64);
    let layers = vec![
        LayerInput {
            optical_depth: 0.2,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.3,
            ..LayerInput::default()
        },
    ];

    assert_eq!(workspace.layer_rt(3).len(), 3);
    assert_eq!(workspace.layer_phase_max_indices(2).len(), 2);
    assert_eq!(
        workspace.layer_effective_scattering_suffix(2).len(),
        2 * MAX_PHASE_COEF
    );
    assert_eq!(workspace.phase_kernel_cache(3).len(), 3);
    assert_eq!(workspace.phase_kernel_valid(3).len(), 3);
    assert_eq!(workspace.orders_workspace(3).ud.len(), 3);

    let attenuation =
        workspace.attenuation(&layers, &PseudoSphericalGrid::default(), &geometry, false);
    assert_eq!(attenuation.nlevel, 3);
    assert_eq!(workspace.attenuation_data.len(), geometry.nmutot * 3 * 3);
    assert_eq!(
        workspace.attenuation_layer_transmittance.len(),
        geometry.nmutot * layers.len()
    );
}

#[test]
fn layer_phase_signature_probe_tracks_reusable_templates() {
    let mut workspace = Workspace::new();
    let layers = vec![
        LayerInput {
            phase_coefficients: phase_coefficients(&[(1, 0.2), (2, 0.1)]),
            ..LayerInput::default()
        },
        LayerInput {
            phase_coefficients: phase_coefficients(&[(1, 0.4), (3, 0.05)]),
            ..LayerInput::default()
        },
    ];
    let layer_phase_max_indices = [2, 3];

    let first = workspace.probe_layer_phase_signatures(&layers, &layer_phase_max_indices, 2);
    assert_eq!(first.layer_count, 2);
    assert_eq!(first.max_index_matches, 0);
    assert_eq!(first.signature_matches, 0);
    assert_eq!(first.possible_fourier_layer_templates, 6);

    let second = workspace.probe_layer_phase_signatures(&layers, &layer_phase_max_indices, 2);
    assert_eq!(second.max_index_matches, 2);
    assert_eq!(second.signature_matches, 2);
    assert_eq!(second.reusable_fourier_layer_templates, 6);

    let source_indices =
        workspace.fill_source_phase_max_indices_from_layers(&layer_phase_max_indices);
    assert_eq!(source_indices, [2, 3, 3]);
}
