use zdisamar::{
    common::errors,
    forward_model::{
        jacobian::{self, State},
        optical_properties::{
            shared::phase_functions,
            state_build::{
                CrossSectionRepresentationKind, EvaluatedLayer, INVALID_SUPPORT_ROW_INDEX,
                OpticalDepthBreakdown, PreparedCrossSectionAbsorber,
                PreparedCrossSectionRepresentation, PreparedLayer, PreparedLineAbsorber,
                PreparedOpticalState, PreparedSublayer, SharedRtmGeometry, SharedRtmLayerGeometry,
                SharedRtmLevelGeometry, accumulate_breakdown,
                build_shared_rtm_geometry_from_layers, collect_active_cross_section_absorbers,
                collect_active_line_absorbers, collision_induced_sigma_at_wavelength,
                continuum_carrier_density_at_sublayer,
                effective_spectroscopy_evaluation_at_wavelength, evaluate_layer_at_wavelength,
                fill_forward_layers_at_wavelength, fill_source_interfaces_from_prepared_layers,
                first_active_support_row_index, forward_input_from_optical_depths,
                interpolate_prepared_scalar_at_altitude, interval_altitude_at_node,
                interval_weight_km, last_active_support_row_index, layer_input_from_evaluated,
                level_altitude_from_sublayers, line_spectroscopy_carrier_density_at_sublayer,
                operational_o2_evaluation_at_wavelength, optical_depth_breakdown_at_wavelength,
                particle_optical_depth_at_wavelength, prepare_cross_section_absorbers,
                prepared_scalar_for_sublayer, resolve_active_line_species,
                resolve_continuum_owner_species, resolve_gauss_rule, sort_line_list,
                species_mixing_ratio_at_pressure, to_forward_input_at_wavelength_with_layers,
                total_cross_section_at_wavelength, total_optical_depth_at_wavelength,
                weighted_cross_section_sigma_at_wavelength, zero_spectroscopy_evaluation,
            },
        },
        radiative_transfer::common_types::{LayerInput, SourceInterfaceInput},
    },
    input::{
        absorber::{Absorber, AbsorberSet, LineGasControls, Spectroscopy, SpectroscopyMode},
        atmosphere::{FractionControl, FractionKind, FractionTarget, IntervalSemantics},
        atmospheric_types::AbsorberSpecies,
        bands::{SpectralBand, SpectralBandSet},
        instrument::OperationalCrossSectionLut,
        reference::rayleigh,
        reference_data::{
            CollisionInducedAbsorptionPoint, CollisionInducedAbsorptionTable, CrossSectionPoint,
            CrossSectionTable, SpectroscopyLine, SpectroscopyLineList,
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

fn scalar_lut(
    left_nm: f64,
    left_sigma: f64,
    right_nm: f64,
    right_sigma: f64,
) -> OperationalCrossSectionLut {
    OperationalCrossSectionLut {
        wavelengths_nm: vec![left_nm, right_nm],
        coefficients: vec![left_sigma, right_sigma],
        temperature_coefficient_count: 1,
        pressure_coefficient_count: 1,
        min_temperature_k: 180.0,
        max_temperature_k: 320.0,
        min_pressure_hpa: 200.0,
        max_pressure_hpa: 1000.0,
    }
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
fn prepared_scalar_helpers_resolve_carrier_densities_by_species() {
    let sublayer = PreparedSublayer {
        global_sublayer_index: 1,
        absorber_number_density_cm3: 10.0,
        oxygen_number_density_cm3: 4.0,
        ..PreparedSublayer::default()
    };
    let prepared = PreparedOpticalState {
        continuum_owner_species: Some(AbsorberSpecies::O2),
        operational_o2_lut: scalar_lut(760.0, 1.0, 761.0, 1.0),
        line_absorbers: vec![PreparedLineAbsorber {
            species: AbsorberSpecies::O2,
            line_list: SpectroscopyLineList::default(),
            number_densities_cm3: vec![2.0, 3.0],
            column_density_factor: 1.0,
        }],
        cross_section_absorbers: vec![PreparedCrossSectionAbsorber {
            species: AbsorberSpecies::O2O2,
            representation_kind: CrossSectionRepresentationKind::Table,
            polynomial_order: 0,
            representation: PreparedCrossSectionRepresentation::Table(CrossSectionTable::default()),
            number_densities_cm3: vec![1.0, 6.0],
            column_density_factor: 1.0,
        }],
        ..PreparedOpticalState::default()
    };

    assert_close(
        continuum_carrier_density_at_sublayer(&prepared, sublayer, 1),
        4.0,
        0.0,
    );
    assert_close(
        line_spectroscopy_carrier_density_at_sublayer(&prepared, sublayer, 1),
        4.0,
        0.0,
    );

    let no_operational_o2 = PreparedOpticalState {
        cross_section_absorbers: prepared.cross_section_absorbers.clone(),
        ..PreparedOpticalState::default()
    };
    assert_close(
        line_spectroscopy_carrier_density_at_sublayer(&no_operational_o2, sublayer, 1),
        4.0,
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

#[test]
fn operational_o2_evaluation_wraps_lut_sigma_as_line_absorption() {
    let lut = OperationalCrossSectionLut {
        wavelengths_nm: vec![760.0, 761.0],
        coefficients: vec![2.0, 4.0],
        temperature_coefficient_count: 1,
        pressure_coefficient_count: 1,
        min_temperature_k: 180.0,
        max_temperature_k: 320.0,
        min_pressure_hpa: 200.0,
        max_pressure_hpa: 1000.0,
    };

    let evaluation = operational_o2_evaluation_at_wavelength(&lut, 760.5, 250.0, 500.0);

    assert_close(evaluation.weak_line_sigma_cm2_per_molecule, 3.0, 0.0);
    assert_close(evaluation.strong_line_sigma_cm2_per_molecule, 0.0, 0.0);
    assert_close(evaluation.line_sigma_cm2_per_molecule, 3.0, 0.0);
    assert_close(evaluation.line_mixing_sigma_cm2_per_molecule, 0.0, 0.0);
    assert_close(evaluation.total_sigma_cm2_per_molecule, 3.0, 0.0);
    assert_close(
        evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k,
        0.0,
        0.0,
    );
}

#[test]
fn state_spectroscopy_weights_cross_section_absorbers_by_column_density() {
    let first = PreparedCrossSectionAbsorber {
        species: AbsorberSpecies::O2O2,
        representation_kind: CrossSectionRepresentationKind::Table,
        polynomial_order: 0,
        representation: PreparedCrossSectionRepresentation::Table(CrossSectionTable {
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
        }),
        number_densities_cm3: Vec::new(),
        column_density_factor: 3.0,
    };
    let fallback_weight = PreparedCrossSectionAbsorber {
        species: AbsorberSpecies::O2O2,
        representation_kind: CrossSectionRepresentationKind::Table,
        polynomial_order: 0,
        representation: PreparedCrossSectionRepresentation::Table(CrossSectionTable {
            points: vec![
                CrossSectionPoint {
                    wavelength_nm: 760.0,
                    sigma_cm2_per_molecule: 10.0,
                },
                CrossSectionPoint {
                    wavelength_nm: 762.0,
                    sigma_cm2_per_molecule: 12.0,
                },
            ],
        }),
        number_densities_cm3: Vec::new(),
        column_density_factor: 0.0,
    };
    let prepared = PreparedOpticalState {
        cross_section_absorbers: vec![first, fallback_weight],
        ..PreparedOpticalState::default()
    };

    assert_close(
        weighted_cross_section_sigma_at_wavelength(&prepared, 761.0, 240.0, 700.0),
        4.25,
        1.0e-14,
    );
}

#[test]
fn state_spectroscopy_prefers_operational_cia_lut_over_cia_table() {
    let prepared = PreparedOpticalState {
        operational_o2o2_lut: scalar_lut(760.0, 20.0, 761.0, 40.0),
        collision_induced_absorption: Some(CollisionInducedAbsorptionTable {
            scale_factor_cm5_per_molecule2: 1.0,
            points: vec![CollisionInducedAbsorptionPoint {
                wavelength_nm: 760.5,
                a0: 100.0,
                a1: 0.0,
                a2: 0.0,
            }],
        }),
        effective_temperature_k: 250.0,
        effective_pressure_hpa: 500.0,
        ..PreparedOpticalState::default()
    };

    assert_close(
        collision_induced_sigma_at_wavelength(&prepared, 760.5),
        30.0,
        1.0e-14,
    );
}

#[test]
fn state_spectroscopy_uses_operational_o2_without_fake_line_list_physics() {
    let prepared = PreparedOpticalState {
        operational_o2_lut: scalar_lut(760.0, 2.0, 761.0, 4.0),
        oxygen_column_density_factor: 5.0,
        effective_temperature_k: 250.0,
        effective_pressure_hpa: 500.0,
        line_absorbers: vec![PreparedLineAbsorber {
            species: AbsorberSpecies::O2,
            line_list: SpectroscopyLineList::default(),
            number_densities_cm3: Vec::new(),
            column_density_factor: 2.0,
        }],
        ..PreparedOpticalState::default()
    };

    let evaluation = effective_spectroscopy_evaluation_at_wavelength(&prepared, 760.5).unwrap();

    assert_close(evaluation.weak_line_sigma_cm2_per_molecule, 3.0, 1.0e-14);
    assert_close(evaluation.total_sigma_cm2_per_molecule, 3.0, 1.0e-14);
}

#[test]
fn state_spectroscopy_errors_when_only_unported_line_physics_is_available() {
    let prepared = PreparedOpticalState {
        line_absorbers: vec![PreparedLineAbsorber {
            species: AbsorberSpecies::O2,
            line_list: SpectroscopyLineList {
                lines: vec![SpectroscopyLine {
                    gas_index: 7,
                    isotope_number: 1,
                    center_wavelength_nm: 760.5,
                    line_strength_cm2_per_molecule: 1.0e-24,
                }],
            },
            number_densities_cm3: Vec::new(),
            column_density_factor: 1.0,
        }],
        ..PreparedOpticalState::default()
    };

    assert_eq!(
        effective_spectroscopy_evaluation_at_wavelength(&prepared, 760.5).unwrap_err(),
        errors::Error::InvalidRequest,
    );
}

#[test]
fn state_spectroscopy_adds_continuum_and_supported_line_sigma() {
    let prepared = PreparedOpticalState {
        continuum_points: vec![
            CrossSectionPoint {
                wavelength_nm: 760.0,
                sigma_cm2_per_molecule: 1.0,
            },
            CrossSectionPoint {
                wavelength_nm: 761.0,
                sigma_cm2_per_molecule: 2.0,
            },
        ],
        operational_o2_lut: scalar_lut(760.0, 10.0, 761.0, 20.0),
        effective_temperature_k: 250.0,
        effective_pressure_hpa: 500.0,
        ..PreparedOpticalState::default()
    };

    assert_close(
        total_cross_section_at_wavelength(&prepared, 760.5).unwrap(),
        16.5,
        1.0e-14,
    );
    assert_eq!(zero_spectroscopy_evaluation(), Default::default(),);
}

#[test]
fn state_optical_depth_builds_single_layer_breakdown() {
    let prepared = PreparedOpticalState {
        continuum_points: vec![
            CrossSectionPoint {
                wavelength_nm: 760.0,
                sigma_cm2_per_molecule: 1.0,
            },
            CrossSectionPoint {
                wavelength_nm: 761.0,
                sigma_cm2_per_molecule: 2.0,
            },
        ],
        operational_o2_lut: scalar_lut(760.0, 10.0, 761.0, 20.0),
        operational_o2o2_lut: scalar_lut(760.0, 0.2, 761.0, 0.4),
        effective_temperature_k: 250.0,
        effective_pressure_hpa: 500.0,
        column_density_factor: 2.0,
        air_column_density_factor: 3.0,
        cia_pair_path_factor_cm5: 4.0,
        aerosol_optical_depth: 0.5,
        aerosol_reference_wavelength_nm: 760.5,
        aerosol_angstrom_exponent: 0.0,
        aerosol_single_scatter_albedo: 0.8,
        cloud_optical_depth: 0.25,
        cloud_reference_wavelength_nm: 760.5,
        cloud_angstrom_exponent: 0.0,
        cloud_single_scatter_albedo: 0.4,
        ..PreparedOpticalState::default()
    };

    let breakdown = optical_depth_breakdown_at_wavelength(&prepared, 760.5).unwrap();

    assert_close(breakdown.gas_absorption_optical_depth, 33.0, 1.0e-14);
    assert_close(
        breakdown.gas_scattering_optical_depth,
        rayleigh::cross_section_cm2(760.5) * 3.0,
        1.0e-30,
    );
    assert_close(breakdown.cia_optical_depth, 1.2, 1.0e-14);
    assert_close(breakdown.aerosol_optical_depth, 0.5, 1.0e-14);
    assert_close(breakdown.aerosol_scattering_optical_depth, 0.4, 1.0e-14);
    assert_close(breakdown.cloud_optical_depth, 0.25, 1.0e-14);
    assert_close(breakdown.cloud_scattering_optical_depth, 0.1, 1.0e-14);
    assert_close(
        total_optical_depth_at_wavelength(&prepared, 760.5).unwrap(),
        breakdown.total_optical_depth(),
        1.0e-14,
    );
}

#[test]
fn state_optical_depth_evaluates_and_aggregates_sublayers() {
    let mut aerosol_phase = phase_functions::gas_phase_coefficients();
    aerosol_phase[1] = 2.0;
    let mut cloud_phase = phase_functions::gas_phase_coefficients();
    cloud_phase[1] = 4.0;
    let sublayers = vec![PreparedSublayer {
        global_sublayer_index: 0,
        altitude_km: 2.0,
        temperature_k: 250.0,
        pressure_hpa: 500.0,
        number_density_cm3: 4.0,
        absorber_number_density_cm3: 3.0,
        oxygen_number_density_cm3: 2.0,
        cia_pair_density_cm6: 6.0,
        path_length_cm: 5.0,
        aerosol_optical_depth: 0.2,
        aerosol_single_scatter_albedo: 0.5,
        aerosol_phase_coefficients: aerosol_phase,
        cloud_optical_depth: 0.4,
        cloud_single_scatter_albedo: 0.25,
        cloud_phase_coefficients: cloud_phase,
        ..PreparedSublayer::default()
    }];
    let prepared = PreparedOpticalState {
        layers: vec![PreparedLayer {
            altitude_km: 2.0,
            sublayer_start_index: 0,
            sublayer_count: 1,
            ..PreparedLayer::default()
        }],
        sublayers: Some(sublayers.clone()),
        continuum_points: vec![CrossSectionPoint {
            wavelength_nm: 760.0,
            sigma_cm2_per_molecule: 2.0,
        }],
        operational_o2o2_lut: scalar_lut(760.0, 0.1, 761.0, 0.1),
        aerosol_reference_wavelength_nm: 760.0,
        cloud_reference_wavelength_nm: 760.0,
        ..PreparedOpticalState::default()
    };

    let evaluated =
        evaluate_layer_at_wavelength(&prepared, None, 2.0, 760.0, 0, &sublayers).unwrap();

    assert_close(
        evaluated.breakdown.gas_absorption_optical_depth,
        30.0,
        1.0e-14,
    );
    assert_close(
        evaluated.breakdown.gas_scattering_optical_depth,
        rayleigh::cross_section_cm2(760.0) * 20.0,
        1.0e-30,
    );
    assert_close(evaluated.breakdown.cia_optical_depth, 3.0, 1.0e-14);
    assert_close(
        evaluated.breakdown.aerosol_scattering_optical_depth,
        0.1,
        1.0e-14,
    );
    assert_close(
        evaluated.breakdown.cloud_scattering_optical_depth,
        0.1,
        1.0e-14,
    );
    assert_close(evaluated.phase_coefficients[0], 1.0, 0.0);
    assert_close(evaluated.phase_coefficients[1], 3.0, 1.0e-14);

    let breakdown = optical_depth_breakdown_at_wavelength(&prepared, 760.0).unwrap();
    assert_eq!(breakdown, evaluated.breakdown);
}

#[test]
fn state_optical_depth_rejects_unported_line_absorbers_in_sublayers() {
    let prepared = PreparedOpticalState {
        line_absorbers: vec![PreparedLineAbsorber {
            species: AbsorberSpecies::O2,
            line_list: SpectroscopyLineList::default(),
            number_densities_cm3: vec![1.0],
            column_density_factor: 1.0,
        }],
        ..PreparedOpticalState::default()
    };
    let sublayers = vec![PreparedSublayer {
        path_length_cm: 1.0,
        ..PreparedSublayer::default()
    }];

    assert_eq!(
        evaluate_layer_at_wavelength(&prepared, None, 0.0, 760.0, 0, &sublayers).unwrap_err(),
        errors::Error::InvalidRequest,
    );
}

#[test]
fn forward_layers_map_total_depths_into_forward_input() {
    let prepared = PreparedOpticalState {
        effective_air_mass_factor: 2.5,
        effective_single_scatter_albedo: 0.42,
        ..PreparedOpticalState::default()
    };
    let mut scene = Scene::default();
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 762.0;
    scene.spectral_grid.sample_count = 5;
    scene.geometry.solar_zenith_deg = 60.0;
    scene.geometry.viewing_zenith_deg = 30.0;
    scene.geometry.relative_azimuth_deg = 20.0;
    scene.surface.albedo = 1.2;

    let input = forward_input_from_optical_depths(
        &prepared,
        &scene,
        761.0,
        OpticalDepthBreakdown::default(),
        &[],
    );

    assert_close(input.spectral_weight, 0.5, 1.0e-14);
    assert_close(input.air_mass_factor, 2.5, 0.0);
    assert_close(input.mu0, 0.5, 1.0e-14);
    assert_close(input.muv, 30.0_f64.to_radians().cos(), 1.0e-14);
    assert_close(input.relative_azimuth_rad, 160.0_f64.to_radians(), 1.0e-14);
    assert_close(input.surface_albedo, 1.0, 0.0);
    assert_close(input.single_scatter_albedo, 0.42, 0.0);
    assert!(input.layers.is_empty());
}

#[test]
fn forward_layers_fill_prepared_layer_inputs_and_aerosol_tangent() {
    let prepared = PreparedOpticalState {
        layers: vec![PreparedLayer {
            altitude_km: 2.0,
            gas_optical_depth: 0.5,
            gas_scattering_optical_depth: 0.1,
            cia_optical_depth: 0.03,
            aerosol_optical_depth: 0.2,
            cloud_optical_depth: 0.4,
            ..PreparedLayer::default()
        }],
        aerosol_reference_wavelength_nm: 760.0,
        aerosol_single_scatter_albedo: 0.5,
        cloud_reference_wavelength_nm: 760.0,
        cloud_single_scatter_albedo: 0.25,
        ..PreparedOpticalState::default()
    };
    let mut scene = Scene::default();
    scene.aerosol.optical_depth = 0.2;
    scene.aerosol.asymmetry_factor = 0.3;
    let mut layer_inputs = vec![LayerInput::default()];

    let totals =
        fill_forward_layers_at_wavelength(&prepared, &scene, 760.0, &mut layer_inputs).unwrap();

    assert_close(
        totals.total_optical_depth(),
        layer_inputs[0].optical_depth,
        1.0e-14,
    );
    assert_close(
        totals.total_scattering_optical_depth(),
        layer_inputs[0].scattering_optical_depth,
        1.0e-14,
    );
    assert_close(layer_inputs[0].gas_absorption_optical_depth, 0.4, 1.0e-14);
    assert_close(
        layer_inputs[0].aerosol_scattering_optical_depth,
        0.1,
        1.0e-14,
    );
    assert_close(layer_inputs[0].cloud_scattering_optical_depth, 0.1, 1.0e-14);
    assert_eq!(
        layer_inputs[0].phase_coefficients,
        phase_functions::hg_phase_coefficients(0.3),
    );
    assert_close(
        jacobian::get(
            layer_inputs[0].optical_depth_jacobian,
            State::AerosolOpticalDepth,
        ),
        1.0,
        1.0e-14,
    );
    assert_close(
        jacobian::get(
            layer_inputs[0].scattering_optical_depth_jacobian,
            State::AerosolOpticalDepth,
        ),
        0.5,
        1.0e-14,
    );
}

#[test]
fn forward_layers_fill_sublayer_grid_and_return_forward_input_layers() {
    let sublayers = vec![PreparedSublayer {
        global_sublayer_index: 0,
        altitude_km: 1.0,
        temperature_k: 250.0,
        pressure_hpa: 500.0,
        number_density_cm3: 1.0,
        absorber_number_density_cm3: 2.0,
        path_length_cm: 3.0,
        aerosol_optical_depth: 0.1,
        aerosol_single_scatter_albedo: 0.5,
        ..PreparedSublayer::default()
    }];
    let prepared = PreparedOpticalState {
        sublayers: Some(sublayers),
        continuum_points: vec![CrossSectionPoint {
            wavelength_nm: 760.0,
            sigma_cm2_per_molecule: 4.0,
        }],
        aerosol_reference_wavelength_nm: 760.0,
        ..PreparedOpticalState::default()
    };
    let mut scene = Scene::default();
    scene.spectral_grid.start_nm = 759.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 3;
    let mut layer_inputs = vec![LayerInput::default()];

    let input =
        to_forward_input_at_wavelength_with_layers(&prepared, &scene, 760.0, &mut layer_inputs)
            .unwrap();

    assert_close(layer_inputs[0].gas_absorption_optical_depth, 24.0, 1.0e-14);
    assert_eq!(input.layers, layer_inputs);
    assert_close(input.optical_depth, layer_inputs[0].optical_depth, 1.0e-14);
}

#[test]
fn forward_layers_reject_shared_rtm_grid_until_carrier_path_is_ported() {
    let prepared = PreparedOpticalState {
        layers: vec![PreparedLayer {
            sublayer_start_index: 0,
            sublayer_count: 2,
            ..PreparedLayer::default()
        }],
        sublayers: Some(vec![PreparedSublayer::default()]),
        interval_semantics: IntervalSemantics::ExplicitPressureBounds,
        ..PreparedOpticalState::default()
    };
    let mut layer_inputs = vec![LayerInput::default()];

    assert_eq!(
        fill_forward_layers_at_wavelength(&prepared, &Scene::default(), 760.0, &mut layer_inputs)
            .unwrap_err(),
        errors::Error::InvalidRequest,
    );
}

#[test]
fn shared_geometry_builds_reduced_rtm_levels_and_interval_weights() {
    let sublayers = (0..=5)
        .map(|index| PreparedSublayer {
            altitude_km: f64::from(index),
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        })
        .collect::<Vec<_>>();
    let layers = vec![
        PreparedLayer {
            sublayer_start_index: 0,
            sublayer_count: 3,
            bottom_altitude_km: 0.0,
            top_altitude_km: 2.0,
            interval_index_1based: 1,
            ..PreparedLayer::default()
        },
        PreparedLayer {
            sublayer_start_index: 2,
            sublayer_count: 3,
            bottom_altitude_km: 2.0,
            top_altitude_km: 4.0,
            interval_index_1based: 1,
            ..PreparedLayer::default()
        },
        PreparedLayer {
            sublayer_start_index: 4,
            sublayer_count: 2,
            bottom_altitude_km: 4.0,
            top_altitude_km: 5.0,
            interval_index_1based: 2,
            ..PreparedLayer::default()
        },
    ];

    let geometry = build_shared_rtm_geometry_from_layers(&layers, &sublayers).unwrap();

    assert!(geometry.is_valid_for(3));
    assert_close(geometry.layers[0].midpoint_altitude_km, 1.0, 0.0);
    assert_close(geometry.layers[1].thickness_km, 2.0, 0.0);
    assert_close(geometry.levels[0].altitude_km, 0.0, 0.0);
    assert_eq!(geometry.levels[0].particle_above_support_row_index, 1);
    assert_eq!(
        geometry.levels[0].particle_below_support_row_index,
        INVALID_SUPPORT_ROW_INDEX
    );
    assert_close(geometry.levels[1].altitude_km, 2.0, 0.0);
    assert_close(geometry.levels[1].weight_km, 4.0, 1.0e-14);
    assert_eq!(geometry.levels[1].particle_above_support_row_index, 3);
    assert_eq!(geometry.levels[1].particle_below_support_row_index, 1);
    assert_eq!(
        geometry.levels[2].particle_above_support_row_index,
        INVALID_SUPPORT_ROW_INDEX
    );
    assert_eq!(geometry.levels[2].particle_below_support_row_index, 3);
    assert_close(geometry.levels[3].altitude_km, 5.0, 0.0);
}

#[test]
fn shared_geometry_helpers_match_zig_boundary_semantics() {
    let rule = resolve_gauss_rule(1).unwrap();
    assert_close(rule.nodes[0], 0.0, 1.0e-14);
    assert_close(rule.weights[0], 2.0, 1.0e-14);
    assert!(resolve_gauss_rule(0).is_err());

    assert_close(interval_altitude_at_node(2.0, 6.0, 0.0), 4.0, 0.0);
    assert_close(interval_weight_km(2.0, 6.0, 2.0), 4.0, 0.0);
    assert_close(interval_altitude_at_node(6.0, 2.0, 0.0), 6.0, 0.0);
    assert_close(interval_weight_km(6.0, 2.0, 2.0), 0.0, 0.0);

    let active_layer = PreparedLayer {
        sublayer_start_index: 4,
        sublayer_count: 4,
        ..PreparedLayer::default()
    };
    assert_eq!(first_active_support_row_index(active_layer), 5);
    assert_eq!(last_active_support_row_index(active_layer), 6);
    assert_eq!(
        first_active_support_row_index(PreparedLayer {
            sublayer_count: 2,
            ..PreparedLayer::default()
        }),
        INVALID_SUPPORT_ROW_INDEX
    );

    let sublayers = vec![
        PreparedSublayer {
            altitude_km: 1.0,
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            altitude_km: 3.0,
            path_length_cm: 200_000.0,
            ..PreparedSublayer::default()
        },
    ];
    assert_close(level_altitude_from_sublayers(&sublayers, 0), 0.5, 0.0);
    assert_close(level_altitude_from_sublayers(&sublayers, 1), 2.0, 0.0);
    assert_close(level_altitude_from_sublayers(&sublayers, 2), 4.0, 0.0);
    assert_close(level_altitude_from_sublayers(&[], 0), 0.0, 0.0);
}

#[test]
fn source_interfaces_use_sublayer_rtm_weight_when_inputs_are_sublayers() {
    let mut phase = phase_functions::gas_phase_coefficients();
    phase[2] = 0.25;
    let layer_inputs = vec![
        LayerInput {
            scattering_optical_depth: 2.0,
            phase_coefficients: phase_functions::gas_phase_coefficients(),
            ..LayerInput::default()
        },
        LayerInput {
            scattering_optical_depth: 6.0,
            phase_coefficients: phase,
            ..LayerInput::default()
        },
    ];
    let sublayers = vec![
        PreparedSublayer {
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            path_length_cm: 300_000.0,
            ..PreparedSublayer::default()
        },
    ];
    let mut interfaces = vec![SourceInterfaceInput::default(); 3];

    fill_source_interfaces_from_prepared_layers(
        &layer_inputs,
        Some(&sublayers),
        &[],
        &mut interfaces,
    );

    assert_close(interfaces[1].source_weight, 0.0, 0.0);
    assert_close(interfaces[1].rtm_weight, 3.0, 0.0);
    assert_close(interfaces[1].ksca_above, 2.0, 1.0e-14);
    assert_eq!(interfaces[1].phase_coefficients_above, phase);
    assert_close(interfaces[2].source_weight, 3.0, 0.0);
}

#[test]
fn source_interfaces_sum_support_sublayers_for_layer_inputs() {
    let mut phase = phase_functions::gas_phase_coefficients();
    phase[3] = 0.125;
    let layer_inputs = vec![
        LayerInput {
            scattering_optical_depth: 1.0,
            ..LayerInput::default()
        },
        LayerInput {
            scattering_optical_depth: 8.0,
            phase_coefficients: phase,
            ..LayerInput::default()
        },
        LayerInput {
            scattering_optical_depth: 4.0,
            phase_coefficients: phase,
            ..LayerInput::default()
        },
    ];
    let sublayers = vec![
        PreparedSublayer {
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            path_length_cm: 300_000.0,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        },
    ];
    let layers = vec![
        PreparedLayer {
            sublayer_start_index: 0,
            sublayer_count: 1,
            ..PreparedLayer::default()
        },
        PreparedLayer {
            sublayer_start_index: 1,
            sublayer_count: 2,
            ..PreparedLayer::default()
        },
        PreparedLayer {
            sublayer_start_index: 0,
            sublayer_count: 0,
            ..PreparedLayer::default()
        },
    ];
    let mut interfaces = vec![SourceInterfaceInput::default(); 4];

    fill_source_interfaces_from_prepared_layers(
        &layer_inputs,
        Some(&sublayers),
        &layers,
        &mut interfaces,
    );

    assert_close(interfaces[1].rtm_weight, 4.0, 0.0);
    assert_close(interfaces[1].ksca_above, 2.0, 1.0e-14);
    assert_eq!(interfaces[1].phase_coefficients_above, phase);
    assert_close(interfaces[2].source_weight, 0.0, 0.0);
    assert_close(interfaces[2].rtm_weight, 0.0, 0.0);
    assert_eq!(interfaces[2].phase_coefficients_above, phase);
}

#[test]
fn prepared_optical_state_resolves_transport_grid_and_shared_geometry_cache() {
    let layers = vec![
        PreparedLayer {
            sublayer_start_index: 0,
            sublayer_count: 3,
            bottom_altitude_km: 0.0,
            top_altitude_km: 2.0,
            interval_index_1based: 1,
            ..PreparedLayer::default()
        },
        PreparedLayer {
            sublayer_start_index: 2,
            sublayer_count: 3,
            bottom_altitude_km: 2.0,
            top_altitude_km: 4.0,
            interval_index_1based: 1,
            ..PreparedLayer::default()
        },
    ];
    let sublayers = (0..=4)
        .map(|index| PreparedSublayer {
            altitude_km: f64::from(index),
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        })
        .collect::<Vec<_>>();
    let mut prepared = PreparedOpticalState {
        layers,
        sublayers: Some(sublayers),
        interval_semantics: IntervalSemantics::ExplicitPressureBounds,
        effective_single_scatter_albedo: 0.4,
        ..PreparedOpticalState::default()
    };

    assert!(prepared.interval_semantics_use_reduced_shared_rtm_layers());
    assert_eq!(prepared.transport_layer_count(), 2);
    prepared.ensure_shared_rtm_geometry_cache().unwrap();
    assert!(prepared.shared_rtm_geometry.is_valid_for(2));
    assert_close(
        prepared.shared_rtm_geometry.levels[1].weight_km,
        4.0,
        1.0e-14,
    );

    let albedos = prepared.resolved_particle_single_scatter_albedos();
    assert_close(albedos.aerosol, 0.4, 0.0);
    assert_close(albedos.cloud, 0.4, 0.0);
}

#[test]
fn prepared_optical_state_uses_sublayer_transport_grid_without_shared_reuse() {
    let mut prepared = PreparedOpticalState {
        layers: vec![PreparedLayer {
            sublayer_count: 1,
            ..PreparedLayer::default()
        }],
        sublayers: Some(vec![
            PreparedSublayer::default(),
            PreparedSublayer::default(),
        ]),
        interval_semantics: IntervalSemantics::ExplicitPressureBounds,
        aerosol_single_scatter_albedo: 1.2,
        cloud_single_scatter_albedo: -0.5,
        effective_single_scatter_albedo: 0.25,
        ..PreparedOpticalState::default()
    };

    assert!(!prepared.interval_semantics_use_reduced_shared_rtm_layers());
    assert_eq!(prepared.transport_layer_count(), 2);
    prepared.ensure_shared_rtm_geometry_cache().unwrap();
    assert!(!prepared.shared_rtm_geometry.is_valid_for(2));

    let albedos = prepared.resolved_particle_single_scatter_albedos();
    assert_close(albedos.aerosol, 1.0, 0.0);
    assert_close(albedos.cloud, 0.25, 0.0);
}
