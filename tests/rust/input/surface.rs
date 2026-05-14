use zdisamar::{
    common::errors,
    input::surface::{Kind, Parameter, Surface},
};

#[test]
fn surface_accepts_named_parameters() {
    let value = Surface {
        kind: Kind::Lambertian,
        parameters: vec![
            Parameter {
                name: "roughness_hint".to_string(),
                value: 0.03,
            },
            Parameter {
                name: "slope_hint".to_string(),
                value: 0.02,
            },
        ],
        ..Surface::default()
    };

    assert_eq!(value.kind, Kind::Lambertian);
    assert_eq!(value.validate(), Ok(()));
    assert_eq!(Kind::parse("lambertian"), Ok(Kind::Lambertian));
    assert_eq!(Kind::parse("wavel_dependent"), Ok(Kind::WavelDependent));
    assert_eq!(
        Kind::parse("unknown_surface"),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn surface_rejects_invalid_albedo_pressure_and_parameters() {
    assert_eq!(
        Surface {
            albedo: 1.1,
            ..Surface::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Surface {
            pressure_hpa: -1.0,
            ..Surface::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Surface {
            parameters: vec![Parameter {
                name: String::new(),
                value: 0.0,
            }],
            ..Surface::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}
