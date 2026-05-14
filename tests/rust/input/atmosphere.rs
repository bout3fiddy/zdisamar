use zdisamar::{
    common::errors::Error,
    input::{
        Atmosphere, Binding, FractionControl, FractionKind, FractionTarget, IntervalGrid,
        IntervalSemantics, NamedRef, PartitionLabel, Subcolumn, SubcolumnLayout, VerticalInterval,
    },
};

fn standard_interval(
    index_1based: u32,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
) -> VerticalInterval {
    VerticalInterval {
        index_1based,
        top_pressure_hpa,
        bottom_pressure_hpa,
        top_altitude_km: 12.0 - f64::from(index_1based - 1) * 6.0,
        bottom_altitude_km: 6.0 - f64::from(index_1based - 1) * 6.0,
        altitude_divisions: 2,
        ..VerticalInterval::default()
    }
}

#[test]
fn atmosphere_validates_profile_source_and_surface_pressure() {
    assert_eq!(
        Atmosphere {
            layer_count: 48,
            profile_source: Binding::Asset(NamedRef {
                name: "us_standard_profile".to_string()
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
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        Atmosphere {
            has_aerosols: true,
            ..Atmosphere::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
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
fn atmosphere_accepts_explicit_pressure_bounded_intervals() {
    let atmosphere = Atmosphere {
        layer_count: 2,
        interval_grid: IntervalGrid {
            semantics: IntervalSemantics::ExplicitPressureBounds,
            fit_interval_index_1based: 2,
            intervals: vec![
                VerticalInterval {
                    index_1based: 1,
                    top_pressure_hpa: 120.0,
                    bottom_pressure_hpa: 450.0,
                    top_altitude_km: 12.0,
                    bottom_altitude_km: 6.5,
                    altitude_divisions: 2,
                    ..VerticalInterval::default()
                },
                VerticalInterval {
                    index_1based: 2,
                    top_pressure_hpa: 450.0,
                    bottom_pressure_hpa: 1013.0,
                    top_altitude_km: 6.5,
                    bottom_altitude_km: 0.0,
                    altitude_divisions: 4,
                    ..VerticalInterval::default()
                },
            ],
        },
        ..Atmosphere::default()
    };

    assert_eq!(atmosphere.validate(), Ok(()));
    assert_eq!(atmosphere.prepared_layer_count(), 2);
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
                    index_1based: 1,
                    top_pressure_hpa: 700.0,
                    bottom_pressure_hpa: 500.0,
                    altitude_divisions: 2,
                    ..VerticalInterval::default()
                }],
            },
            ..Atmosphere::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        Atmosphere {
            layer_count: 2,
            interval_grid: IntervalGrid {
                semantics: IntervalSemantics::ExplicitPressureBounds,
                intervals: vec![
                    standard_interval(1, 150.0, 500.0),
                    VerticalInterval {
                        top_altitude_km: 9.0,
                        bottom_altitude_km: 0.0,
                        ..standard_interval(2, 500.0, 1013.0)
                    },
                ],
                ..IntervalGrid::default()
            },
            ..Atmosphere::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
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
        Err(Error::InvalidRequest)
    );
}

#[test]
fn fraction_control_validates_and_interpolates_wavelength_values() {
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
    assert!((control.value_at_wavelength(760.5) - 0.40).abs() < 1.0e-12);
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
        Err(Error::InvalidRequest)
    );
}

#[test]
fn subcolumn_layout_labels_nearest_altitude_range() {
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
                top_altitude_km: 8.0,
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
        layout.label_for_altitude(20.0),
        PartitionLabel::FreeTroposphere
    );
}
