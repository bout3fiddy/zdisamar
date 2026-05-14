use zdisamar::common::units::{
    AltitudeRangeKm, AngleDeg, AzimuthAngleDeg, Error, PressureRangeHpa, WavelengthRange,
    ZenithAngleDeg,
};

#[test]
fn wavelength_range_rejects_inverted_intervals() {
    assert_eq!(
        WavelengthRange {
            start_nm: 771.0,
            end_nm: 758.0,
        }
        .validate(),
        Err(Error::InvalidRange)
    );
}

#[test]
fn altitude_and_pressure_ranges_enforce_physical_ordering() {
    assert_eq!(
        AltitudeRangeKm {
            bottom_km: 0.0,
            top_km: 2.5,
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        PressureRangeHpa {
            top_hpa: 150.0,
            bottom_hpa: 900.0,
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        AltitudeRangeKm {
            bottom_km: 3.0,
            top_km: 2.0,
        }
        .validate(),
        Err(Error::InvalidRange)
    );
    assert_eq!(
        PressureRangeHpa {
            top_hpa: 900.0,
            bottom_hpa: 150.0,
        }
        .validate(),
        Err(Error::InvalidRange)
    );
}

#[test]
fn angle_validation_rejects_nan() {
    assert_eq!(
        AngleDeg { value: f64::NAN }.validate(),
        Err(Error::InvalidValue)
    );
}

#[test]
fn zenith_and_azimuth_helpers_enforce_physical_angle_ranges() {
    assert_eq!(ZenithAngleDeg { value: 95.0 }.validate(), Ok(()));
    assert_eq!(AzimuthAngleDeg { value: 270.0 }.validate(), Ok(()));
    assert_eq!(
        ZenithAngleDeg { value: -1.0 }.validate(),
        Err(Error::InvalidRange)
    );
    assert_eq!(
        AzimuthAngleDeg { value: 361.0 }.validate(),
        Err(Error::InvalidRange)
    );
}
