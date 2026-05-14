use zdisamar::{
    common::errors,
    forward_model::optical_properties::particle_support::{
        ParticleSingleScatterAlbedos, resolved_particle_single_scatter_albedos,
    },
    input::{
        aerosol::Aerosol,
        atmosphere::{
            FractionControl, FractionKind, FractionTarget, IntervalPlacement,
            ParticlePlacementSemantics,
        },
        cloud::Cloud,
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
        aerosol_placement,
        IntervalPlacement {
            semantics: ParticlePlacementSemantics::AltitudeCenterWidthApproximation,
            top_altitude_km: 4.0,
            bottom_altitude_km: 1.0,
            ..IntervalPlacement::default()
        }
    );

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
fn particle_controls_validate_bounds_and_fraction_targets() {
    assert_eq!(
        Aerosol {
            optical_depth: -0.1,
            ..Aerosol::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Cloud {
            single_scatter_albedo: 1.2,
            ..Cloud::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Aerosol {
            fraction: FractionControl {
                enabled: true,
                target: FractionTarget::Cloud,
                kind: FractionKind::WavelIndependent,
                values: vec![0.5],
                ..FractionControl::default()
            },
            ..Aerosol::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn particle_single_scatter_albedos_use_effective_fallback_and_clamping() {
    assert_eq!(
        resolved_particle_single_scatter_albedos(-1.0, 1.5, 0.4),
        ParticleSingleScatterAlbedos {
            aerosol: 0.4,
            cloud: 1.0,
        }
    );
}
