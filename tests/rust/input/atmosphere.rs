use zdisamar::{
    common::errors,
    input::{
        atmosphere::{
            Atmosphere, FractionControl, FractionKind, FractionTarget, IntervalGrid,
            IntervalSemantics, PartitionLabel, Subcolumn, SubcolumnLayout, VerticalInterval,
        },
        binding::{Binding, NamedRef},
    },
};

fn interval(
    index_1based: u32,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    top_altitude_km: f64,
    bottom_altitude_km: f64,
) -> VerticalInterval {
    VerticalInterval {
        index_1based,
        top_pressure_hpa,
        bottom_pressure_hpa,
        top_altitude_km,
        bottom_altitude_km,
        altitude_divisions: 2,
        ..VerticalInterval::default()
    }
}

#[test]
fn atmosphere_validates_profile_source_and_positive_surface_pressure() {
    assert_eq!(
        Atmosphere {
            layer_count: 48,
            profile_source: Binding::Asset(NamedRef {
                name: "us_standard_profile".to_string(),
            }),
            surface_pressure_hpa: 1013.0,
            ..Atmosphere::default()
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        Atmosphere {
            surface_pressure_hpa: -1.0,
            ..Atmosphere::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Atmosphere {
            has_aerosols: true,
            layer_count: 0,
            ..Atmosphere::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Atmosphere {
            layer_count: 48,
            sublayer_divisions: 12,
            ..Atmosphere::default()
        }
        .validate(),
        Ok(())
    );
}

#[test]
fn atmosphere_accepts_explicit_pressure_bounded_intervals_and_fit_interval_state() {
    let atmosphere = Atmosphere {
        layer_count: 2,
        interval_grid: IntervalGrid {
            semantics: IntervalSemantics::ExplicitPressureBounds,
            fit_interval_index_1based: 2,
            intervals: vec![
                VerticalInterval {
                    altitude_divisions: 2,
                    ..interval(1, 120.0, 450.0, 12.0, 6.5)
                },
                VerticalInterval {
                    altitude_divisions: 4,
                    ..interval(2, 450.0, 1013.0, 6.5, 0.0)
                },
            ],
        },
        ..Atmosphere::default()
    };

    assert_eq!(atmosphere.validate(), Ok(()));
    assert_eq!(
        atmosphere
            .interval_grid
            .fit_interval()
            .unwrap()
            .index_1based,
        2
    );
}

#[test]
fn atmosphere_rejects_malformed_interval_and_subcolumn_metadata() {
    assert_eq!(
        Atmosphere {
            interval_grid: IntervalGrid {
                semantics: IntervalSemantics::ExplicitPressureBounds,
                fit_interval_index_1based: 2,
                intervals: vec![VerticalInterval {
                    top_pressure_hpa: 700.0,
                    bottom_pressure_hpa: 500.0,
                    ..interval(1, 700.0, 500.0, f64::NAN, f64::NAN)
                }],
            },
            ..Atmosphere::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Atmosphere {
            layer_count: 2,
            interval_grid: IntervalGrid {
                semantics: IntervalSemantics::ExplicitPressureBounds,
                intervals: vec![
                    interval(1, 150.0, 500.0, 12.0, 8.0),
                    interval(2, 550.0, 1013.0, 8.0, 0.0),
                ],
                ..IntervalGrid::default()
            },
            ..Atmosphere::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Atmosphere {
            layer_count: 1,
            subcolumns: SubcolumnLayout {
                enabled: true,
                subcolumns: vec![Subcolumn {
                    index_1based: 1,
                    label: PartitionLabel::BoundaryLayer,
                    bottom_altitude_km: 2.0,
                    top_altitude_km: 1.0,
                    ..Subcolumn::default()
                }],
                ..SubcolumnLayout::default()
            },
            ..Atmosphere::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn fraction_control_interpolates_and_rejects_non_monotonic_wavelength_grids() {
    let control = FractionControl {
        enabled: true,
        target: FractionTarget::Aerosol,
        kind: FractionKind::WavelDependent,
        threshold_cloud_fraction: 0.25,
        threshold_variance: 0.1,
        wavelengths_nm: vec![760.0, 761.0],
        values: vec![0.20, 0.60],
        apriori_values: vec![0.25, 0.55],
        variance_values: vec![0.01, 0.04],
    };
    assert_eq!(control.validate(), Ok(()));
    assert!((control.value_at_wavelength(760.5) - 0.40).abs() <= 1.0e-12);

    assert_eq!(
        FractionControl {
            enabled: true,
            target: FractionTarget::Aerosol,
            kind: FractionKind::WavelDependent,
            wavelengths_nm: vec![761.0, 760.0],
            values: vec![0.25, 0.75],
            ..FractionControl::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn subcolumn_layout_labels_altitudes_by_configured_ranges() {
    let layout = SubcolumnLayout {
        enabled: true,
        subcolumns: vec![
            Subcolumn {
                index_1based: 1,
                label: PartitionLabel::BoundaryLayer,
                bottom_altitude_km: 0.0,
                top_altitude_km: 2.0,
                ..Subcolumn::default()
            },
            Subcolumn {
                index_1based: 2,
                label: PartitionLabel::FreeTroposphere,
                bottom_altitude_km: 2.0,
                top_altitude_km: 12.0,
                ..Subcolumn::default()
            },
        ],
        ..SubcolumnLayout::default()
    };

    assert_eq!(layout.validate(), Ok(()));
    assert_eq!(
        layout.label_for_altitude(1.0),
        PartitionLabel::BoundaryLayer
    );
    assert_eq!(
        layout.label_for_altitude(8.0),
        PartitionLabel::FreeTroposphere
    );
}
