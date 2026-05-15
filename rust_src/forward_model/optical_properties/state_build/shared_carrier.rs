use super::{
    EvaluatedLayer, OpticalDepthBreakdown, PHASE_COEFFICIENT_COUNT, PreparedOpticalState,
    PreparedSublayer, ProfileNodeSpectroscopyCache, SharedOpticalCarrier, SharedRtmLayerGeometry,
    carrier_eval::{
        WavelengthCarrierCache, shared_optical_carrier_at_support_row_with_cache,
        shared_optical_carrier_at_support_row_with_carrier_cache,
    },
};
use crate::{
    common::errors,
    forward_model::optical_properties::shared::phase_functions::{self, PhaseCoefficients},
    forward_model::radiative_transfer::common_types::{LayerInput, PseudoSphericalSample},
    input::scene::Scene,
};

pub fn accumulate_shared_carrier(
    breakdown: &mut OpticalDepthBreakdown,
    phase_numerator: &mut PhaseCoefficients,
    carrier: SharedOpticalCarrier,
    weight_km: f64,
) {
    let weighted_gas_absorption = carrier.gas_absorption_optical_depth_per_km * weight_km;
    let weighted_gas_scattering = carrier.gas_scattering_optical_depth_per_km * weight_km;
    let weighted_cia = carrier.cia_optical_depth_per_km * weight_km;
    let weighted_aerosol = carrier.aerosol_optical_depth_per_km * weight_km;
    let weighted_aerosol_scattering = carrier.aerosol_scattering_optical_depth_per_km * weight_km;
    let weighted_cloud = carrier.cloud_optical_depth_per_km * weight_km;
    let weighted_cloud_scattering = carrier.cloud_scattering_optical_depth_per_km * weight_km;

    breakdown.gas_absorption_optical_depth += weighted_gas_absorption;
    breakdown.gas_scattering_optical_depth += weighted_gas_scattering;
    breakdown.cia_optical_depth += weighted_cia;
    breakdown.aerosol_optical_depth += weighted_aerosol;
    breakdown.aerosol_scattering_optical_depth += weighted_aerosol_scattering;
    breakdown.cloud_optical_depth += weighted_cloud;
    breakdown.cloud_scattering_optical_depth += weighted_cloud_scattering;

    let weighted_scattering =
        weighted_gas_scattering + weighted_aerosol_scattering + weighted_cloud_scattering;
    if weighted_scattering <= 0.0 {
        return;
    }
    for (index, value) in phase_numerator.iter_mut().enumerate() {
        *value += weighted_scattering * carrier.phase_coefficients[index];
    }
}

pub fn evaluated_layer_from_shared_carrier(
    scene: &Scene,
    wavelength_nm: f64,
    altitude_km: f64,
    breakdown: OpticalDepthBreakdown,
    phase_numerator: PhaseCoefficients,
) -> EvaluatedLayer {
    let total_scattering = breakdown.total_scattering_optical_depth();
    let mut phase_coefficients =
        phase_functions::gas_phase_coefficients_at_wavelength(wavelength_nm);
    if total_scattering > 0.0 {
        for index in 0..PHASE_COEFFICIENT_COUNT {
            phase_coefficients[index] = phase_numerator[index] / total_scattering;
        }
        phase_coefficients[0] = 1.0;
    }

    EvaluatedLayer {
        breakdown,
        phase_coefficients,
        solar_mu: scene.geometry.solar_cosine_at_altitude(altitude_km),
        view_mu: scene.geometry.viewing_cosine_at_altitude(altitude_km),
    }
}

pub fn evaluate_reduced_layer_from_support_rows(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    support_sublayers: &[PreparedSublayer],
    layer_geometry: SharedRtmLayerGeometry,
) -> Result<EvaluatedLayer, errors::Error> {
    evaluate_reduced_layer_from_support_rows_with_cache(
        prepared,
        scene,
        wavelength_nm,
        support_sublayers,
        layer_geometry,
        None,
    )
}

pub fn evaluate_reduced_layer_from_support_rows_with_cache(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    support_sublayers: &[PreparedSublayer],
    layer_geometry: SharedRtmLayerGeometry,
    profile_cache: Option<&ProfileNodeSpectroscopyCache>,
) -> Result<EvaluatedLayer, errors::Error> {
    let mut breakdown = OpticalDepthBreakdown::default();
    let mut phase_numerator = [0.0; PHASE_COEFFICIENT_COUNT];
    if support_sublayers.len() < 2 {
        return Ok(evaluated_layer_from_shared_carrier(
            scene,
            wavelength_nm,
            layer_geometry.midpoint_altitude_km,
            breakdown,
            phase_numerator,
        ));
    }

    for support_sublayer in &support_sublayers[1..support_sublayers.len() - 1] {
        let weight_km = (support_sublayer.path_length_cm / 1.0e5).max(0.0);
        if weight_km <= 0.0 {
            continue;
        }
        let carrier = shared_optical_carrier_at_support_row_with_cache(
            prepared,
            wavelength_nm,
            *support_sublayer,
            support_sublayer.global_sublayer_index as usize,
            profile_cache,
        )?;
        accumulate_shared_carrier(&mut breakdown, &mut phase_numerator, carrier, weight_km);
    }

    Ok(evaluated_layer_from_shared_carrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        phase_numerator,
    ))
}

pub fn evaluate_reduced_layer_from_support_rows_with_carrier_cache(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    support_sublayers: &[PreparedSublayer],
    layer_geometry: SharedRtmLayerGeometry,
    wavelength_cache: &mut WavelengthCarrierCache<'_>,
) -> Result<EvaluatedLayer, errors::Error> {
    let mut breakdown = OpticalDepthBreakdown::default();
    let mut phase_numerator = [0.0; PHASE_COEFFICIENT_COUNT];
    if support_sublayers.len() < 2 {
        return Ok(evaluated_layer_from_shared_carrier(
            scene,
            wavelength_nm,
            layer_geometry.midpoint_altitude_km,
            breakdown,
            phase_numerator,
        ));
    }

    for support_sublayer in &support_sublayers[1..support_sublayers.len() - 1] {
        let weight_km = (support_sublayer.path_length_cm / 1.0e5).max(0.0);
        if weight_km <= 0.0 {
            continue;
        }
        let carrier = shared_optical_carrier_at_support_row_with_carrier_cache(
            prepared,
            wavelength_nm,
            *support_sublayer,
            support_sublayer.global_sublayer_index as usize,
            wavelength_cache,
        )?;
        accumulate_shared_carrier(&mut breakdown, &mut phase_numerator, carrier, weight_km);
    }

    Ok(evaluated_layer_from_shared_carrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        phase_numerator,
    ))
}

pub fn fill_shared_pseudo_spherical_samples_from_support_rows(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    support_sublayers: &[PreparedSublayer],
    attenuation_layers: &mut [LayerInput],
    attenuation_samples: &mut [PseudoSphericalSample],
    sample_index_start: usize,
) -> Result<usize, errors::Error> {
    fill_shared_pseudo_spherical_samples_from_support_rows_with_cache(
        prepared,
        wavelength_nm,
        support_sublayers,
        attenuation_layers,
        attenuation_samples,
        sample_index_start,
        None,
    )
}

pub fn fill_shared_pseudo_spherical_samples_from_support_rows_with_cache(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    support_sublayers: &[PreparedSublayer],
    attenuation_layers: &mut [LayerInput],
    attenuation_samples: &mut [PseudoSphericalSample],
    sample_index_start: usize,
    profile_cache: Option<&ProfileNodeSpectroscopyCache>,
) -> Result<usize, errors::Error> {
    let mut sample_index = sample_index_start;
    if support_sublayers.len() < 2 {
        return Ok(sample_index);
    }

    for support_sublayer in &support_sublayers[1..support_sublayers.len() - 1] {
        if sample_index >= attenuation_samples.len() {
            return Err(errors::Error::InvalidRequest);
        }
        let weight_km = (support_sublayer.path_length_cm / 1.0e5).max(0.0);
        let optical_depth = if weight_km > 0.0 {
            weight_km
                * shared_optical_carrier_at_support_row_with_cache(
                    prepared,
                    wavelength_nm,
                    *support_sublayer,
                    support_sublayer.global_sublayer_index as usize,
                    profile_cache,
                )?
                .total_optical_depth_per_km()
        } else {
            0.0
        };
        attenuation_samples[sample_index] = PseudoSphericalSample {
            altitude_km: support_sublayer.altitude_km,
            thickness_km: weight_km,
            optical_depth,
        };
        if let Some(layer) = attenuation_layers.get_mut(sample_index) {
            *layer = LayerInput {
                optical_depth,
                ..LayerInput::default()
            };
        }
        sample_index += 1;
    }
    Ok(sample_index)
}

pub fn fill_shared_pseudo_spherical_samples_from_support_rows_with_carrier_cache(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    support_sublayers: &[PreparedSublayer],
    attenuation_layers: &mut [LayerInput],
    attenuation_samples: &mut [PseudoSphericalSample],
    sample_index_start: usize,
    wavelength_cache: &mut WavelengthCarrierCache<'_>,
) -> Result<usize, errors::Error> {
    let mut sample_index = sample_index_start;
    if support_sublayers.len() < 2 {
        return Ok(sample_index);
    }

    for support_sublayer in &support_sublayers[1..support_sublayers.len() - 1] {
        if sample_index >= attenuation_samples.len() {
            return Err(errors::Error::InvalidRequest);
        }
        let weight_km = (support_sublayer.path_length_cm / 1.0e5).max(0.0);
        let optical_depth = if weight_km > 0.0 {
            weight_km
                * shared_optical_carrier_at_support_row_with_carrier_cache(
                    prepared,
                    wavelength_nm,
                    *support_sublayer,
                    support_sublayer.global_sublayer_index as usize,
                    wavelength_cache,
                )?
                .total_optical_depth_per_km()
        } else {
            0.0
        };
        attenuation_samples[sample_index] = PseudoSphericalSample {
            altitude_km: support_sublayer.altitude_km,
            thickness_km: weight_km,
            optical_depth,
        };
        if let Some(layer) = attenuation_layers.get_mut(sample_index) {
            *layer = LayerInput {
                optical_depth,
                ..LayerInput::default()
            };
        }
        sample_index += 1;
    }
    Ok(sample_index)
}
