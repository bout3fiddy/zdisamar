use crate::input::{Aerosol, Cloud, IntervalPlacement, ParticlePlacementSemantics};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ParticleSingleScatterAlbedos {
    pub aerosol: f64,
    pub cloud: f64,
}

pub fn aerosol_placement(aerosol: &Aerosol) -> IntervalPlacement {
    if aerosol.placement.enabled() {
        return aerosol.placement;
    }
    IntervalPlacement {
        semantics: ParticlePlacementSemantics::AltitudeCenterWidthApproximation,
        top_altitude_km: aerosol.layer_center_km + 0.5 * aerosol.layer_width_km,
        bottom_altitude_km: (aerosol.layer_center_km - 0.5 * aerosol.layer_width_km).max(0.0),
        ..IntervalPlacement::default()
    }
}

pub fn cloud_placement(cloud: &Cloud) -> IntervalPlacement {
    if cloud.placement.enabled() {
        return cloud.placement;
    }
    IntervalPlacement {
        semantics: ParticlePlacementSemantics::AltitudeCenterWidthApproximation,
        top_altitude_km: cloud.top_altitude_km,
        bottom_altitude_km: (cloud.top_altitude_km - cloud.thickness_km).max(0.0),
        ..IntervalPlacement::default()
    }
}

pub fn resolved_particle_single_scatter_albedos(
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    effective_single_scatter_albedo: f64,
) -> ParticleSingleScatterAlbedos {
    ParticleSingleScatterAlbedos {
        aerosol: if aerosol_single_scatter_albedo >= 0.0 {
            aerosol_single_scatter_albedo
        } else {
            effective_single_scatter_albedo
        }
        .clamp(0.0, 1.0),
        cloud: if cloud_single_scatter_albedo >= 0.0 {
            cloud_single_scatter_albedo
        } else {
            effective_single_scatter_albedo
        }
        .clamp(0.0, 1.0),
    }
}
