use zdisamar::{
    forward_model::{
        jacobian::{self, State},
        optical_properties::{
            shared::phase_functions,
            state_build::{
                CrossSectionRepresentationKind, EvaluatedLayer, OpticalDepthBreakdown,
                PreparedCrossSectionAbsorber, PreparedCrossSectionRepresentation, PreparedSublayer,
                SharedRtmGeometry, SharedRtmLayerGeometry, SharedRtmLevelGeometry,
                accumulate_breakdown, interpolate_prepared_scalar_at_altitude,
                layer_input_from_evaluated, particle_optical_depth_at_wavelength,
                prepared_scalar_for_sublayer,
            },
        },
    },
    input::{
        atmosphere::{FractionControl, FractionKind, FractionTarget},
        atmospheric_types::AbsorberSpecies,
        reference_data::{CrossSectionPoint, CrossSectionTable},
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
