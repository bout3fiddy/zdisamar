use crate::{
    common::errors,
    forward_model::{
        optical_properties::state_build::{
            PreparedOpticalState, PseudoSphericalBuffers, SharedOpticalCarrier,
            carrier_eval::WavelengthCarrierCache,
            fill_forward_layers_at_wavelength_with_carrier_cache,
            fill_pseudo_spherical_grid_at_wavelength_with_carrier_cache,
            fill_rtm_quadrature_at_wavelength_with_layers_and_carrier_cache,
            fill_source_interfaces_at_wavelength_with_layers_and_carrier_cache,
            forward_input_from_optical_depths,
        },
        radiative_transfer::common_types::{
            ForwardInput, LayerInput, PseudoSphericalGrid, PseudoSphericalSample, Route,
            RtmQuadratureGrid, RtmQuadratureLevel, SourceInterfaceInput,
        },
    },
    input::{atmosphere::IntervalSemantics, scene::Scene},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    OutOfMemory,
    InvalidRequest,
    MissingScene,
    MissingObservationInstrument,
    MissingExplicitRtmQuadrature,
}

impl From<errors::Error> for Error {
    fn from(value: errors::Error) -> Self {
        match value {
            errors::Error::OutOfMemory => Error::OutOfMemory,
            errors::Error::InvalidRequest => Error::InvalidRequest,
            errors::Error::MissingScene => Error::MissingScene,
            errors::Error::MissingObservationInstrument => Error::MissingObservationInstrument,
        }
    }
}

pub struct ForwardInputBuffers<'a> {
    pub layer_inputs: &'a mut [LayerInput],
    pub pseudo_spherical_layers: &'a mut [LayerInput],
    pub source_interfaces: &'a mut [SourceInterfaceInput],
    pub rtm_quadrature_levels: &'a mut [RtmQuadratureLevel],
    pub pseudo_spherical_samples: &'a mut [PseudoSphericalSample],
    pub pseudo_spherical_level_starts: &'a mut [usize],
    pub pseudo_spherical_level_altitudes: &'a mut [f64],
    pub support_carrier_valid: &'a mut [bool],
    pub support_carriers: &'a mut [SharedOpticalCarrier],
}

impl ForwardInputBuffers<'_> {
    pub fn reborrow(&mut self) -> ForwardInputBuffers<'_> {
        ForwardInputBuffers {
            layer_inputs: &mut *self.layer_inputs,
            pseudo_spherical_layers: &mut *self.pseudo_spherical_layers,
            source_interfaces: &mut *self.source_interfaces,
            rtm_quadrature_levels: &mut *self.rtm_quadrature_levels,
            pseudo_spherical_samples: &mut *self.pseudo_spherical_samples,
            pseudo_spherical_level_starts: &mut *self.pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes: &mut *self.pseudo_spherical_level_altitudes,
            support_carrier_valid: &mut *self.support_carrier_valid,
            support_carriers: &mut *self.support_carriers,
        }
    }
}

pub fn configured_forward_input(
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    buffers: ForwardInputBuffers<'_>,
) -> Result<ForwardInput, Error> {
    let transport_layer_count = prepared.transport_layer_count();
    if transport_layer_count == 0 || buffers.layer_inputs.len() != transport_layer_count {
        return Err(Error::InvalidRequest);
    }
    if buffers.source_interfaces.len() < transport_layer_count + 1
        || buffers.rtm_quadrature_levels.len() < transport_layer_count + 1
        || buffers.pseudo_spherical_level_starts.len() < transport_layer_count + 1
        || buffers.pseudo_spherical_level_altitudes.len() < transport_layer_count + 1
    {
        return Err(Error::InvalidRequest);
    }

    let mut wavelength_cache = WavelengthCarrierCache::new(
        prepared,
        wavelength_nm,
        buffers.support_carrier_valid,
        buffers.support_carriers,
        None,
    );
    let optical_depths = fill_forward_layers_at_wavelength_with_carrier_cache(
        prepared,
        scene,
        wavelength_nm,
        buffers.layer_inputs,
        &mut wavelength_cache,
    )?;
    let mut input = forward_input_from_optical_depths(
        prepared,
        scene,
        wavelength_nm,
        optical_depths,
        buffers.layer_inputs,
    );
    let source_interface_count = input.layers.len() + 1;
    let mut has_rtm_quadrature = false;

    if route.rtm_controls.integrate_source_function {
        let rtm_levels = &mut buffers.rtm_quadrature_levels[..source_interface_count];
        has_rtm_quadrature = fill_rtm_quadrature_at_wavelength_with_layers_and_carrier_cache(
            prepared,
            wavelength_nm,
            &input.layers,
            rtm_levels,
            &mut wavelength_cache,
        )?;
        if has_rtm_quadrature {
            input.rtm_quadrature = RtmQuadratureGrid {
                levels: rtm_levels.to_vec(),
            };
        } else if prepared.interval_semantics != IntervalSemantics::None {
            // Explicit interval runs need the RTM-native carrier grid; falling
            // back to midpoint source interfaces changes the physics.
            return Err(Error::MissingExplicitRtmQuadrature);
        }
    }

    if !has_rtm_quadrature {
        let source_interfaces = &mut buffers.source_interfaces[..source_interface_count];
        fill_source_interfaces_at_wavelength_with_layers_and_carrier_cache(
            prepared,
            wavelength_nm,
            &input.layers,
            source_interfaces,
            &mut wavelength_cache,
        )?;
        input.source_interfaces = source_interfaces.to_vec();
    }

    if route.rtm_controls.use_spherical_correction {
        let has_grid = fill_pseudo_spherical_grid_at_wavelength_with_carrier_cache(
            prepared,
            scene,
            wavelength_nm,
            input.layers.len(),
            PseudoSphericalBuffers {
                attenuation_layers: buffers.pseudo_spherical_layers,
                attenuation_samples: buffers.pseudo_spherical_samples,
                level_sample_starts: &mut buffers.pseudo_spherical_level_starts
                    [..source_interface_count],
                level_altitudes_km: &mut buffers.pseudo_spherical_level_altitudes
                    [..source_interface_count],
            },
            &mut wavelength_cache,
        )?;
        if has_grid {
            let sample_count = buffers.pseudo_spherical_level_starts[input.layers.len()];
            input.pseudo_spherical_grid = PseudoSphericalGrid {
                samples: buffers.pseudo_spherical_samples[..sample_count].to_vec(),
                level_sample_starts: buffers.pseudo_spherical_level_starts
                    [..source_interface_count]
                    .to_vec(),
                level_altitudes_km: buffers.pseudo_spherical_level_altitudes
                    [..source_interface_count]
                    .to_vec(),
            };
        }
    }

    input.rtm_controls = route.rtm_controls;
    Ok(input)
}
