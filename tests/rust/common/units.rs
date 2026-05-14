use zdisamar::common::units::{
    AltitudeRangeKm, AngleDeg, AzimuthAngleDeg, Error, PressureRangeHpa, WavelengthRange,
    ZenithAngleDeg,
};

#[test]
fn wavelength_range_rejects_inverted_and_nonfinite_bounds() {
    assert_eq!(WavelengthRange::default().validate(), Ok(()));
    assert_eq!(
        WavelengthRange {
            start_nm: 800.0,
            end_nm: 700.0
        }
        .validate(),
        Err(Error::InvalidRange)
    );
    assert_eq!(
        WavelengthRange {
            start_nm: f64::NAN,
            end_nm: 700.0
        }
        .validate(),
        Err(Error::InvalidValue)
    );
}

#[test]
fn altitude_and_pressure_ranges_enforce_physical_ordering() {
    assert_eq!(
        AltitudeRangeKm {
            bottom_km: 0.0,
            top_km: 20.0
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        AltitudeRangeKm {
            bottom_km: 10.0,
            top_km: 5.0
        }
        .validate(),
        Err(Error::InvalidRange)
    );
    assert_eq!(
        PressureRangeHpa {
            top_hpa: 100.0,
            bottom_hpa: 900.0
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        PressureRangeHpa {
            top_hpa: 1000.0,
            bottom_hpa: 900.0
        }
        .validate(),
        Err(Error::InvalidRange)
    );
}

#[test]
fn angle_helpers_keep_generic_and_domain_ranges_separate() {
    assert_eq!(AngleDeg { value: -20.0 }.validate(), Ok(()));
    assert_eq!(
        AngleDeg {
            value: f64::INFINITY
        }
        .validate(),
        Err(Error::InvalidValue)
    );
    assert_eq!(ZenithAngleDeg { value: 180.0 }.validate(), Ok(()));
    assert_eq!(
        ZenithAngleDeg { value: 181.0 }.validate(),
        Err(Error::InvalidRange)
    );
    assert_eq!(AzimuthAngleDeg { value: 360.0 }.validate(), Ok(()));
    assert_eq!(
        AzimuthAngleDeg { value: -0.1 }.validate(),
        Err(Error::InvalidRange)
    );
}
