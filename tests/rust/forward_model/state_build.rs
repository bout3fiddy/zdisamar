use zdisamar::{
    forward_model::{
        jacobian::{self, State},
        optical_properties::{
            shared::phase_functions,
            state_build::{
                CrossSectionRepresentationKind, EvaluatedLayer, OpticalDepthBreakdown,
                PreparedCrossSectionAbsorber, PreparedCrossSectionRepresentation, PreparedSublayer,
                SharedRtmGeometry, SharedRtmLayerGeometry, SharedRtmLevelGeometry,
                accumulate_breakdown, collect_active_cross_section_absorbers,
                collect_active_line_absorbers, interpolate_prepared_scalar_at_altitude,
                layer_input_from_evaluated, particle_optical_depth_at_wavelength,
                prepare_cross_section_absorbers, prepared_scalar_for_sublayer,
                resolve_active_line_species, resolve_continuum_owner_species, sort_line_list,
                species_mixing_ratio_at_pressure,
            },
        },
    },
    input::{
        absorber::{Absorber, AbsorberSet, LineGasControls, Spectroscopy, SpectroscopyMode},
        atmosphere::{FractionControl, FractionKind, FractionTarget},
        atmospheric_types::AbsorberSpecies,
        bands::{SpectralBand, SpectralBandSet},
        instrument::OperationalCrossSectionLut,
        reference_data::{
            CrossSectionPoint, CrossSectionTable, SpectroscopyLine, SpectroscopyLineList,
        },
        scene::Scene,
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

#[test]
fn optical_depth_breakdown_computes_totals_and_single_scatter_albedo() {
    let mut totals = OpticalDepthBreakdown {
        gas_absorption_optical_depth: 0.2,
        gas_scattering_optical_depth: 0.03,
        ..OpticalDepthBreakdown::default()
    };
    accumulate_breakdown(
        &mut totals,
        OpticalDepthBreakdown {
            cia_optical_depth: 0.01,
            aerosol_optical_depth: 0.12,
            aerosol_scattering_optical_depth: 0.08,
            cloud_optical_depth: 0.2,
            cloud_scattering_optical_depth: 0.05,
            ..OpticalDepthBreakdown::default()
        },
    );

    assert_close(totals.total_optical_depth(), 0.56, 1.0e-14);
    assert_close(totals.total_scattering_optical_depth(), 0.16, 1.0e-14);
    assert_close(totals.single_scatter_albedo(), 0.16 / 0.56, 1.0e-14);
    assert_close(
        OpticalDepthBreakdown::default().single_scatter_albedo(),
        0.0,
        0.0,
    );
}

#[test]
fn evaluated_layer_maps_to_radiative_transfer_input() {
    let mut phase = phase_functions::gas_phase_coefficients();
    phase[2] = 0.25;
    let evaluated = EvaluatedLayer {
        breakdown: OpticalDepthBreakdown {
            gas_absorption_optical_depth: 0.2,
            gas_scattering_optical_depth: 0.03,
            cia_optical_depth: 0.01,
            aerosol_optical_depth: 0.12,
            aerosol_scattering_optical_depth: 0.08,
            cloud_optical_depth: 0.2,
            cloud_scattering_optical_depth: 0.05,
        },
        phase_coefficients: phase,
        solar_mu: 0.61,
        view_mu: 0.72,
    };

    let layer = layer_input_from_evaluated(evaluated);

    assert_close(layer.optical_depth, 0.56, 1.0e-14);
    assert_close(layer.scattering_optical_depth, 0.16, 1.0e-14);
    assert_close(layer.single_scatter_albedo, 0.16 / 0.56, 1.0e-14);
    assert_eq!(layer.phase_coefficients, phase);
    assert_close(layer.solar_mu, 0.61, 0.0);
    assert_close(layer.view_mu, 0.72, 0.0);
    assert_close(
        jacobian::get(layer.optical_depth_jacobian, State::AerosolOpticalDepth),
        0.0,
        0.0,
    );
}

#[test]
fn prepared_sublayer_and_shared_geometry_match_zig_defaults() {
    let sublayer = PreparedSublayer {
        oxygen_number_density_cm3: 2.0,
        ..PreparedSublayer::default()
    };
    assert_close(sublayer.cia_pair_density_cm6_value(), 4.0, 0.0);
    let explicit_pair_density = PreparedSublayer {
        oxygen_number_density_cm3: 2.0,
        cia_pair_density_cm6: 7.0,
        ..PreparedSublayer::default()
    };
    assert_close(explicit_pair_density.cia_pair_density_cm6_value(), 7.0, 0.0);

    let geometry = SharedRtmGeometry {
        layers: vec![
            SharedRtmLayerGeometry::default(),
            SharedRtmLayerGeometry::default(),
        ],
        levels: vec![
            SharedRtmLevelGeometry::default(),
            SharedRtmLevelGeometry::default(),
            SharedRtmLevelGeometry::default(),
        ],
    };
    assert!(geometry.is_valid_for(2));
    assert!(!geometry.is_valid_for(1));
    assert_eq!(
        SharedRtmLevelGeometry::default().particle_above_support_row_index,
        u32::MAX
    );
}

#[test]
fn prepared_scalar_helpers_interpolate_by_altitude() {
    let sublayers = vec![
        PreparedSublayer {
            global_sublayer_index: 0,
            altitude_km: 1.0,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            global_sublayer_index: 1,
            altitude_km: 3.0,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            global_sublayer_index: 2,
            altitude_km: 5.0,
            ..PreparedSublayer::default()
        },
    ];
    let values = [10.0, 20.0, 50.0];

    assert_close(
        prepared_scalar_for_sublayer(&values, sublayers[1]),
        20.0,
        0.0,
    );
    assert_close(
        interpolate_prepared_scalar_at_altitude(&sublayers, &values, 4.0),
        35.0,
        1.0e-14,
    );
    assert_close(
        interpolate_prepared_scalar_at_altitude(&sublayers, &values, 0.0),
        10.0,
        1.0e-14,
    );
    assert_close(
        interpolate_prepared_scalar_at_altitude(&[], &values, 4.0),
        0.0,
        0.0,
    );
}

#[test]
fn particle_optical_depth_uses_base_or_effective_fraction_semantics() {
    let disabled_control = FractionControl::default();
    assert_close(
        particle_optical_depth_at_wavelength(0.2, 0.0, 760.0, 0.0, &disabled_control, 770.0),
        0.2,
        0.0,
    );

    let control = FractionControl {
        enabled: true,
        target: FractionTarget::Aerosol,
        kind: FractionKind::WavelDependent,
        wavelengths_nm: vec![760.0, 770.0],
        values: vec![0.5, 1.0],
        ..FractionControl::default()
    };
    assert_close(
        particle_optical_depth_at_wavelength(0.2, 0.0, 760.0, 0.0, &control, 770.0),
        0.4,
        1.0e-14,
    );
    assert_close(
        particle_optical_depth_at_wavelength(0.2, 0.1, 760.0, 0.0, &control, 770.0),
        0.1,
        1.0e-14,
    );
}

#[test]
fn prepared_cross_section_absorber_uses_typed_representation() {
    let table = CrossSectionTable {
        points: vec![
            CrossSectionPoint {
                wavelength_nm: 760.0,
                sigma_cm2_per_molecule: 1.0,
            },
            CrossSectionPoint {
                wavelength_nm: 762.0,
                sigma_cm2_per_molecule: 3.0,
            },
        ],
    };
    let absorber = PreparedCrossSectionAbsorber {
        species: AbsorberSpecies::O2O2,
        representation_kind: CrossSectionRepresentationKind::Table,
        polynomial_order: 0,
        representation: PreparedCrossSectionRepresentation::Table(table),
        number_densities_cm3: vec![1.0e18, 2.0e18],
        column_density_factor: 1.5,
    };

    assert_close(absorber.sigma_at(761.0, 220.0, 500.0), 2.0, 1.0e-14);
    assert_close(
        absorber.d_sigma_d_temperature_at(761.0, 220.0, 500.0),
        0.0,
        0.0,
    );
    assert_close(
        absorber.mean_sigma_in_range(760.0, 762.0, 220.0, 500.0),
        2.0,
        1.0e-14,
    );
}

#[test]
fn spectroscopy_helpers_collect_active_absorbers_from_scene() {
    let explicit_table = CrossSectionTable {
        points: vec![
            CrossSectionPoint {
                wavelength_nm: 760.0,
                sigma_cm2_per_molecule: 1.0,
            },
            CrossSectionPoint {
                wavelength_nm: 762.0,
                sigma_cm2_per_molecule: 3.0,
            },
        ],
    };
    let fallback_table = CrossSectionTable {
        points: vec![
            CrossSectionPoint {
                wavelength_nm: 760.0,
                sigma_cm2_per_molecule: 10.0,
            },
            CrossSectionPoint {
                wavelength_nm: 762.0,
                sigma_cm2_per_molecule: 14.0,
            },
        ],
    };
    let mut scene = Scene {
        bands: SpectralBandSet {
            items: vec![SpectralBand {
                id: "o2-a".to_string(),
                start_nm: 759.0,
                end_nm: 770.0,
                step_nm: 0.1,
                exclude: Vec::new(),
            }],
        },
        absorbers: AbsorberSet {
            items: vec![
                Absorber {
                    id: "o2".to_string(),
                    species: "o2".to_string(),
                    spectroscopy: Spectroscopy {
                        mode: SpectroscopyMode::LineByLine,
                        line_gas_controls: LineGasControls {
                            threshold_line_sim: Some(0.05),
                            ..LineGasControls::default()
                        },
                        ..Spectroscopy::default()
                    },
                    volume_mixing_ratio_profile_ppmv: vec![[1000.0, 209_460.0]],
                    ..Absorber::default()
                },
                Absorber {
                    id: "o2o2-table".to_string(),
                    species: "o2o2".to_string(),
                    spectroscopy: Spectroscopy {
                        mode: SpectroscopyMode::CrossSections,
                        resolved_cross_section_table: Some(explicit_table),
                        ..Spectroscopy::default()
                    },
                    volume_mixing_ratio_profile_ppmv: vec![[1000.0, 1.0]],
                    ..Absorber::default()
                },
                Absorber {
                    id: "o2o2-fallback".to_string(),
                    species: "O2-O2".to_string(),
                    spectroscopy: Spectroscopy {
                        mode: SpectroscopyMode::CrossSections,
                        ..Spectroscopy::default()
                    },
                    ..Absorber::default()
                },
            ],
        },
        ..Scene::default()
    };
    scene
        .observation_model
        .cross_section_fit
        .xsec_strong_absorption_bands = vec![true];
    scene
        .observation_model
        .cross_section_fit
        .polynomial_degree_bands = vec![3];

    let line_absorbers = collect_active_line_absorbers(&scene);
    assert_eq!(line_absorbers.len(), 1);
    assert_eq!(line_absorbers[0].species, AbsorberSpecies::O2);
    assert_eq!(line_absorbers[0].controls.threshold_line_sim, Some(0.05));

    let active_cross_sections = collect_active_cross_section_absorbers(&scene, &fallback_table);
    assert_eq!(active_cross_sections.len(), 2);
    assert!(active_cross_sections[0].use_effective_cross_section);
    assert_eq!(active_cross_sections[0].polynomial_order, 3);

    let prepared = prepare_cross_section_absorbers(&active_cross_sections, 4).unwrap();
    assert_eq!(prepared.len(), 2);
    assert_eq!(
        prepared[0].representation_kind,
        CrossSectionRepresentationKind::EffectiveTable
    );
    assert_eq!(prepared[0].number_densities_cm3, vec![0.0; 4]);
    assert_close(prepared[0].sigma_at(761.0, 220.0, 500.0), 2.0, 1.0e-14);
    assert_close(prepared[1].sigma_at(761.0, 220.0, 500.0), 12.0, 1.0e-14);
}

#[test]
fn spectroscopy_helpers_resolve_species_and_profiles() {
    let mut line_list = SpectroscopyLineList {
        lines: vec![
            SpectroscopyLine {
                gas_index: 7,
                center_wavelength_nm: 762.0,
                ..SpectroscopyLine::default()
            },
            SpectroscopyLine {
                gas_index: 7,
                center_wavelength_nm: 760.0,
                ..SpectroscopyLine::default()
            },
        ],
    };
    sort_line_list(&mut line_list);
    assert_close(line_list.lines[0].center_wavelength_nm, 760.0, 0.0);

    assert_eq!(
        resolve_active_line_species(
            None,
            Some(&line_list),
            &OperationalCrossSectionLut::default()
        )
        .unwrap(),
        Some(AbsorberSpecies::O2)
    );
    assert_eq!(
        resolve_continuum_owner_species(None, &[], &OperationalCrossSectionLut::default()),
        None
    );

    let scene = Scene {
        absorbers: AbsorberSet {
            items: vec![Absorber {
                id: "o2".to_string(),
                species: "o2".to_string(),
                volume_mixing_ratio_profile_ppmv: vec![[1000.0, 100_000.0], [500.0, 200_000.0]],
                ..Absorber::default()
            }],
        },
        ..Scene::default()
    };
    assert_close(
        species_mixing_ratio_at_pressure(&scene, AbsorberSpecies::O2, &[], 750.0, None).unwrap(),
        0.15,
        1.0e-14,
    );
    assert_close(
        species_mixing_ratio_at_pressure(
            &scene,
            AbsorberSpecies::O2,
            &[[100.0, -5.0]],
            100.0,
            None,
        )
        .unwrap(),
        0.0,
        0.0,
    );
}
