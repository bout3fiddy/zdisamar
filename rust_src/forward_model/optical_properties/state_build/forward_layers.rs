use super::{
    OpticalDepthBreakdown, PreparedOpticalState, PreparedSublayer, accumulate_breakdown,
    evaluate_layer_at_wavelength, layer_input_from_evaluated,
    optical_depth_breakdown_at_wavelength, particle_optical_depth_at_wavelength,
};
use crate::{
    common::errors,
    forward_model::{
        jacobian,
        optical_properties::shared::phase_functions,
        radiative_transfer::common_types::{ForwardInput, LayerInput},
    },
    input::scene::Scene,
};

fn transport_azimuth_difference_rad(relative_azimuth_deg: f64) -> f64 {
    (180.0 - relative_azimuth_deg)
        .rem_euclid(360.0)
        .to_radians()
}

pub fn to_forward_input(
    prepared: &PreparedOpticalState,
    scene: &Scene,
) -> Result<ForwardInput, errors::Error> {
    to_forward_input_at_wavelength(
        prepared,
        scene,
        (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
    )
}

pub fn to_forward_input_at_wavelength(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
) -> Result<ForwardInput, errors::Error> {
    let optical_depths = optical_depth_breakdown_at_wavelength(prepared, wavelength_nm)?;
    Ok(forward_input_from_optical_depths(
        prepared,
        scene,
        wavelength_nm,
        optical_depths,
        &[],
    ))
}

pub fn to_forward_input_at_wavelength_with_layers(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    layer_inputs: &mut [LayerInput],
) -> Result<ForwardInput, errors::Error> {
    let optical_depths =
        fill_forward_layers_at_wavelength(prepared, scene, wavelength_nm, layer_inputs)?;
    Ok(forward_input_from_optical_depths(
        prepared,
        scene,
        wavelength_nm,
        optical_depths,
        layer_inputs,
    ))
}

pub fn forward_input_from_optical_depths(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    optical_depths: OpticalDepthBreakdown,
    layers: &[LayerInput],
) -> ForwardInput {
    let span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    let spectral_weight = if scene.spectral_grid.sample_count <= 1 {
        span_nm.max(1.0e-6)
    } else {
        span_nm / f64::from(scene.spectral_grid.sample_count - 1)
    };
    let total_optical_depth = optical_depths.total_optical_depth();
    ForwardInput {
        wavelength_nm,
        spectral_weight: spectral_weight.max(1.0e-6),
        air_mass_factor: prepared.effective_air_mass_factor,
        mu0: scene.geometry.solar_cosine_at_altitude(0.0),
        muv: scene.geometry.viewing_cosine_at_altitude(0.0),
        relative_azimuth_rad: transport_azimuth_difference_rad(scene.geometry.relative_azimuth_deg),
        surface_albedo: scene.surface.albedo.clamp(0.0, 1.0),
        gas_absorption_optical_depth: optical_depths.gas_absorption_optical_depth,
        gas_scattering_optical_depth: optical_depths.gas_scattering_optical_depth,
        cia_optical_depth: optical_depths.cia_optical_depth,
        aerosol_optical_depth: optical_depths.aerosol_optical_depth,
        aerosol_scattering_optical_depth: optical_depths.aerosol_scattering_optical_depth,
        cloud_optical_depth: optical_depths.cloud_optical_depth,
        cloud_scattering_optical_depth: optical_depths.cloud_scattering_optical_depth,
        optical_depth: total_optical_depth,
        single_scatter_albedo: if total_optical_depth > 0.0 {
            optical_depths.single_scatter_albedo()
        } else {
            prepared.effective_single_scatter_albedo
        },
        layers: layers.to_vec(),
        ..ForwardInput::default()
    }
}

pub fn fill_forward_layers_at_wavelength(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    layer_inputs: &mut [LayerInput],
) -> Result<OpticalDepthBreakdown, errors::Error> {
    if layer_inputs.is_empty() {
        return optical_depth_breakdown_at_wavelength(prepared, wavelength_nm);
    }

    if let Some(sublayers) = &prepared.sublayers {
        return fill_sublayer_forward_layers_at_wavelength(
            prepared,
            scene,
            wavelength_nm,
            sublayers,
            layer_inputs,
        );
    }

    fill_prepared_layer_forward_inputs(prepared, scene, wavelength_nm, layer_inputs)
}

fn fill_sublayer_forward_layers_at_wavelength(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    layer_inputs: &mut [LayerInput],
) -> Result<OpticalDepthBreakdown, errors::Error> {
    if prepared.interval_semantics_use_reduced_shared_rtm_layers()
        && layer_inputs.len() == prepared.layers.len()
    {
        // Reduced shared-RTM layers must be evaluated from support-row carriers.
        // That path is separate from the ordinary sublayer integration and is
        // not ported yet.
        return Err(errors::Error::InvalidRequest);
    }

    let mut totals = OpticalDepthBreakdown::default();
    if layer_inputs.len() == sublayers.len() {
        for (sublayer_index, layer_input) in layer_inputs.iter_mut().enumerate() {
            let sublayer = sublayers[sublayer_index];
            let evaluated = evaluate_layer_at_wavelength(
                prepared,
                Some(scene),
                sublayer.altitude_km,
                wavelength_nm,
                sublayer_index,
                &sublayers[sublayer_index..sublayer_index + 1],
            )?;
            *layer_input = layer_input_from_evaluated(evaluated);
            attach_aerosol_optical_depth_jacobian(scene, layer_input);
            accumulate_breakdown(&mut totals, evaluated.breakdown);
        }
        return Ok(totals);
    }

    if layer_inputs.len() != prepared.layers.len() {
        return Err(errors::Error::InvalidRequest);
    }

    for (layer, layer_input) in prepared.layers.iter().zip(layer_inputs.iter_mut()) {
        let start_index = layer.sublayer_start_index as usize;
        let end_index = start_index + layer.sublayer_count as usize;
        if start_index >= sublayers.len() || end_index > sublayers.len() {
            return Err(errors::Error::InvalidRequest);
        }
        let evaluated = evaluate_layer_at_wavelength(
            prepared,
            Some(scene),
            layer.altitude_km,
            wavelength_nm,
            start_index,
            &sublayers[start_index..end_index],
        )?;
        *layer_input = layer_input_from_evaluated(evaluated);
        attach_aerosol_optical_depth_jacobian(scene, layer_input);
        accumulate_breakdown(&mut totals, evaluated.breakdown);
    }
    Ok(totals)
}

fn fill_prepared_layer_forward_inputs(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    layer_inputs: &mut [LayerInput],
) -> Result<OpticalDepthBreakdown, errors::Error> {
    if layer_inputs.len() != prepared.layers.len() {
        return Err(errors::Error::InvalidRequest);
    }

    let particle_albedos = prepared.resolved_particle_single_scatter_albedos();
    let mut totals = OpticalDepthBreakdown::default();
    for (layer, layer_input) in prepared.layers.iter().zip(layer_inputs.iter_mut()) {
        let aerosol_optical_depth = particle_optical_depth_at_wavelength(
            layer.aerosol_optical_depth,
            layer.aerosol_base_optical_depth,
            prepared.aerosol_reference_wavelength_nm,
            prepared.aerosol_angstrom_exponent,
            &prepared.aerosol_fraction_control,
            wavelength_nm,
        );
        let cloud_optical_depth = particle_optical_depth_at_wavelength(
            layer.cloud_optical_depth,
            layer.cloud_base_optical_depth,
            prepared.cloud_reference_wavelength_nm,
            prepared.cloud_angstrom_exponent,
            &prepared.cloud_fraction_control,
            wavelength_nm,
        );
        let gas_scattering_optical_depth = layer.gas_scattering_optical_depth;
        let gas_absorption_optical_depth =
            (layer.gas_optical_depth - gas_scattering_optical_depth).max(0.0);
        let aerosol_scattering_optical_depth = aerosol_optical_depth * particle_albedos.aerosol;
        let cloud_scattering_optical_depth = cloud_optical_depth * particle_albedos.cloud;

        let breakdown = OpticalDepthBreakdown {
            gas_absorption_optical_depth,
            gas_scattering_optical_depth,
            cia_optical_depth: layer.cia_optical_depth,
            aerosol_optical_depth,
            aerosol_scattering_optical_depth,
            cloud_optical_depth,
            cloud_scattering_optical_depth,
        };
        let optical_depth = breakdown.total_optical_depth();
        let scattering_optical_depth = breakdown.total_scattering_optical_depth();
        *layer_input = LayerInput {
            gas_absorption_optical_depth,
            gas_scattering_optical_depth,
            cia_optical_depth: layer.cia_optical_depth,
            aerosol_optical_depth,
            aerosol_scattering_optical_depth,
            cloud_optical_depth,
            cloud_scattering_optical_depth,
            optical_depth,
            scattering_optical_depth,
            single_scatter_albedo: if optical_depth > 0.0 {
                (scattering_optical_depth / optical_depth).clamp(0.0, 1.0)
            } else {
                0.0
            },
            solar_mu: scene.geometry.solar_cosine_at_altitude(layer.altitude_km),
            view_mu: scene.geometry.viewing_cosine_at_altitude(layer.altitude_km),
            phase_coefficients: phase_functions::hg_phase_coefficients(
                scene.aerosol.asymmetry_factor,
            ),
            ..LayerInput::default()
        };
        attach_aerosol_optical_depth_jacobian(scene, layer_input);
        accumulate_breakdown(&mut totals, breakdown);
    }
    Ok(totals)
}

fn attach_aerosol_optical_depth_jacobian(scene: &Scene, layer_input: &mut LayerInput) {
    let aerosol_tau = scene.aerosol.optical_depth;
    if aerosol_tau <= 0.0 {
        return;
    }
    let optical_derivative = layer_input.aerosol_optical_depth / aerosol_tau;
    let scattering_derivative = layer_input.aerosol_scattering_optical_depth / aerosol_tau;
    jacobian::set(
        &mut layer_input.optical_depth_jacobian,
        jacobian::State::AerosolOpticalDepth,
        optical_derivative,
    );
    jacobian::set(
        &mut layer_input.scattering_optical_depth_jacobian,
        jacobian::State::AerosolOpticalDepth,
        scattering_derivative,
    );
    if layer_input.optical_depth > 0.0 {
        let derivative = (scattering_derivative * layer_input.optical_depth
            - layer_input.scattering_optical_depth * optical_derivative)
            / (layer_input.optical_depth * layer_input.optical_depth);
        jacobian::set(
            &mut layer_input.single_scatter_albedo_jacobian,
            jacobian::State::AerosolOpticalDepth,
            derivative,
        );
    }
}
