use zdisamar::{
    common::errors::Error,
    input::{
        Aerosol, Cloud, FractionControl, FractionKind, FractionTarget, IntervalPlacement,
        ParticlePlacementSemantics,
    },
};

#[test]
fn particle_placement_falls_back_only_when_explicit_placement_is_absent() {
    let aerosol = Aerosol {
        layer_center_km: 2.5,
        layer_width_km: 3.0,
        ..Aerosol::default()
    };
    let aerosol_placement = aerosol.resolved_placement();

    assert_eq!(
        aerosol_placement.semantics,
        ParticlePlacementSemantics::AltitudeCenterWidthApproximation
    );
    assert_eq!(aerosol_placement.top_altitude_km, 4.0);
    assert_eq!(aerosol_placement.bottom_altitude_km, 1.0);

    let cloud = Cloud {
        top_altitude_km: 6.0,
        thickness_km: 1.5,
        placement: IntervalPlacement {
            semantics: ParticlePlacementSemantics::ExplicitIntervalBounds,
            interval_index_1based: 2,
            top_pressure_hpa: 300.0,
            bottom_pressure_hpa: 450.0,
            top_altitude_km: 6.0,
            bottom_altitude_km: 4.5,
        },
        ..Cloud::default()
    };
    let cloud_placement = cloud.resolved_placement();

    assert_eq!(cloud_placement.interval_index_1based, 2);
    assert_eq!(cloud_placement.top_pressure_hpa, 300.0);
    assert_eq!(cloud_placement.bottom_altitude_km, 4.5);
}

#[test]
fn aerosol_and_cloud_validate_particle_ranges_and_fraction_targets() {
    assert_eq!(
        Aerosol {
            optical_depth: 0.25,
            fraction: FractionControl {
                enabled: true,
                target: FractionTarget::Aerosol,
                kind: FractionKind::WavelIndependent,
                values: vec![0.4],
                ..FractionControl::default()
            },
            ..Aerosol::default()
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        Aerosol {
            asymmetry_factor: 1.5,
            ..Aerosol::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        Cloud {
            fraction: FractionControl {
                enabled: true,
                target: FractionTarget::Aerosol,
                kind: FractionKind::WavelIndependent,
                values: vec![0.4],
                ..FractionControl::default()
            },
            ..Cloud::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}
