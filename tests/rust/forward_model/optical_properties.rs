use zdisamar::{
    forward_model::optical_properties::{
        particle_support,
        shared::{
            band_means,
            particle_profiles::{self, PreparedVerticalGrid},
        },
    },
    input::{
        Aerosol, AerosolType, Cloud, IntervalGrid, IntervalPlacement, IntervalSemantics,
        MeasurementPipeline, ObservationModel, OperationalBandSupport, OperationalCrossSectionLut,
        OperationalReferenceGrid, ParticlePlacementSemantics, Scene, SpectralGrid,
        VerticalInterval,
    },
};

fn assert_close(actual: f64, expected: f64) {
    let tolerance = expected.abs().max(1.0) * 1.0e-12;
    assert!(
        (actual - expected).abs() <= tolerance,
        "{actual} != {expected}"
    );
}

fn vertical_grid<'a>(
    tops: &'a [f64],
    bottoms: &'a [f64],
    mids: &'a [f64],
    support_weights: &'a [f64],
    interval_indices: &'a [u32],
) -> PreparedVerticalGrid<'a> {
    PreparedVerticalGrid {
        layer_top_altitudes_km: &[],
        layer_bottom_altitudes_km: &[],
        layer_interval_indices_1based: &[],
        sublayer_top_altitudes_km: tops,
        sublayer_bottom_altitudes_km: bottoms,
        sublayer_mid_altitudes_km: mids,
        sublayer_support_weights_km: support_weights,
        sublayer_parent_interval_indices_1based: interval_indices,
    }
}

#[test]
fn particle_support_resolves_fallback_placements_and_albedos() {
    let aerosol = Aerosol {
        layer_center_km: 2.0,
        layer_width_km: 3.0,
        ..Aerosol::default()
    };
    let aerosol_placement = particle_support::aerosol_placement(&aerosol);
    assert_eq!(
        aerosol_placement.semantics,
        ParticlePlacementSemantics::AltitudeCenterWidthApproximation
    );
    assert_close(aerosol_placement.bottom_altitude_km, 0.5);
    assert_close(aerosol_placement.top_altitude_km, 3.5);

    let cloud = Cloud {
        top_altitude_km: 8.0,
        thickness_km: 2.0,
        ..Cloud::default()
    };
    let cloud_placement = particle_support::cloud_placement(&cloud);
    assert_close(cloud_placement.bottom_altitude_km, 6.0);
    assert_close(cloud_placement.top_altitude_km, 8.0);

    let albedos = particle_support::resolved_particle_single_scatter_albedos(-1.0, 1.2, 0.8);
    assert_close(albedos.aerosol, 0.8);
    assert_close(albedos.cloud, 1.0);
}

#[test]
fn particle_profiles_scale_and_distribute_finite_layers() {
    assert_close(
        particle_profiles::scale_optical_depth(0.2, 550.0, 1.0, 1100.0),
        0.1,
    );

    let grid = vertical_grid(
        &[1.0, 2.0, 3.0],
        &[0.0, 1.0, 2.0],
        &[0.5, 1.5, 2.5],
        &[1.0, 1.0, 1.0],
        &[1, 1, 2],
    );
    let finite = particle_profiles::build_finite_layer_sublayer_distribution(
        grid, true, 0.6, 0.5, 2.5, false,
    )
    .unwrap();
    assert_close(finite.iter().sum(), 0.6);
    assert_close(finite[0], 0.15);
    assert_close(finite[1], 0.3);
    assert_close(finite[2], 0.15);

    let interval =
        particle_profiles::build_interval_matched_distribution(grid, true, 0.4, 1).unwrap();
    assert_close(interval.iter().sum(), 0.4);
    assert_close(interval[0], 0.2);
    assert_close(interval[1], 0.2);
    assert_close(interval[2], 0.0);
}

#[test]
fn particle_profiles_route_scene_aerosol_and_cloud_controls() {
    let grid = vertical_grid(
        &[1.0, 2.0, 3.0],
        &[0.0, 1.0, 2.0],
        &[0.5, 1.5, 2.5],
        &[1.0, 1.0, 1.0],
        &[1, 1, 2],
    );
    let scene = Scene {
        atmosphere: zdisamar::input::Atmosphere {
            has_aerosols: true,
            has_clouds: true,
            interval_grid: IntervalGrid {
                semantics: IntervalSemantics::ExplicitPressureBounds,
                intervals: vec![
                    VerticalInterval {
                        index_1based: 1,
                        top_pressure_hpa: 100.0,
                        bottom_pressure_hpa: 400.0,
                        altitude_divisions: 2,
                        ..VerticalInterval::default()
                    },
                    VerticalInterval {
                        index_1based: 2,
                        top_pressure_hpa: 400.0,
                        bottom_pressure_hpa: 900.0,
                        altitude_divisions: 1,
                        ..VerticalInterval::default()
                    },
                ],
                ..IntervalGrid::default()
            },
            ..Default::default()
        },
        aerosol: Aerosol {
            enabled: true,
            aerosol_type: AerosolType::HgScattering,
            optical_depth: 0.3,
            placement: IntervalPlacement {
                semantics: ParticlePlacementSemantics::ExplicitIntervalBounds,
                interval_index_1based: 2,
                top_pressure_hpa: 400.0,
                bottom_pressure_hpa: 900.0,
                ..IntervalPlacement::default()
            },
            ..Aerosol::default()
        },
        cloud: Cloud {
            enabled: true,
            optical_thickness: 0.5,
            top_altitude_km: 2.5,
            thickness_km: 1.0,
            ..Cloud::default()
        },
        ..Scene::default()
    };

    let aerosol = particle_profiles::build_aerosol_sublayer_distribution(&scene, grid).unwrap();
    assert_close(aerosol.iter().sum(), 0.3);
    assert_close(aerosol[2], 0.3);

    let cloud = particle_profiles::build_cloud_sublayer_distribution(&scene, grid).unwrap();
    assert_close(cloud.iter().sum(), 0.5);
}

#[test]
fn band_means_average_operational_lut_on_native_or_weighted_grid() {
    let lut = OperationalCrossSectionLut {
        wavelengths_nm: vec![760.0, 762.0],
        coefficients: vec![1.0, 3.0],
        temperature_coefficient_count: 1,
        pressure_coefficient_count: 1,
        min_temperature_k: 200.0,
        max_temperature_k: 320.0,
        min_pressure_hpa: 100.0,
        max_pressure_hpa: 1000.0,
    };
    let scene = Scene {
        spectral_grid: SpectralGrid {
            start_nm: 760.0,
            end_nm: 762.0,
            sample_count: 3,
        },
        ..Scene::default()
    };
    assert_close(
        band_means::compute_operational_band_mean(&scene, &lut, 100.0, 0.1),
        2.0,
    );

    let weighted_scene = Scene {
        spectral_grid: SpectralGrid {
            start_nm: 760.0,
            end_nm: 762.0,
            sample_count: 3,
        },
        observation_model: ObservationModel {
            measurement_pipeline: MeasurementPipeline::default(),
            operational_band_support: vec![OperationalBandSupport {
                id: "primary".to_string(),
                operational_refspec_grid: OperationalReferenceGrid {
                    wavelengths_nm: vec![760.0, 762.0],
                    weights: vec![1.0, 3.0],
                },
                ..OperationalBandSupport::default()
            }],
            ..ObservationModel::default()
        },
        ..Scene::default()
    };
    assert_close(
        band_means::compute_operational_band_mean(&weighted_scene, &lut, 250.0, 500.0),
        2.5,
    );
    assert_close(
        band_means::compute_weighted_window_mean(&[1.0, 3.0], &[1.0, 3.0]),
        2.5,
    );
}
