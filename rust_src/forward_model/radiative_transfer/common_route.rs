use crate::forward_model::{
    optical_properties::shared::phase_functions,
    radiative_transfer::common_types::{
        self, DispatchRequest, Error, ExecutionMode, LayerInput, Route, SourceInterfaceInput,
        TransportFamily,
    },
};

pub fn prepare_route(request: DispatchRequest) -> Result<Route, Error> {
    // This Rust slice only routes the real LABOS baseline path. Rejecting here
    // keeps unsupported parsed controls from being silently ignored.
    if request.rtm_controls.use_adding {
        return Err(Error::UnsupportedTransportSolver);
    }
    if request.regime != common_types::Regime::Nadir {
        return Err(Error::UnsupportedObservationRegime);
    }
    if request.execution_mode != ExecutionMode::Scalar {
        return Err(Error::UnsupportedExecutionMode);
    }
    if request.derivative_mode == crate::input::scene::DerivativeMode::Numerical {
        return Err(Error::UnsupportedDerivativeMode);
    }
    request.rtm_controls.validate(request.execution_mode)?;
    Ok(Route {
        family: TransportFamily::Labos,
        regime: request.regime,
        execution_mode: request.execution_mode,
        derivative_mode: request.derivative_mode,
        derivative_state_mask: crate::forward_model::jacobian::ALL_STATES_MASK,
        rtm_controls: request.rtm_controls,
    })
}

pub fn source_interface_from_layers(layers: &[LayerInput], ilevel: usize) -> SourceInterfaceInput {
    if layers.is_empty() {
        return SourceInterfaceInput::default();
    }
    let above_index = ilevel.min(layers.len() - 1);
    let below_index = if ilevel > 0 { ilevel - 1 } else { above_index };
    let source_weight = if ilevel < layers.len() {
        layers[ilevel].scattering_optical_depth.max(0.0)
    } else {
        // The bottom interface belongs to the last layer boundary, not a full
        // extra layer, so it carries half of the adjacent scattering estimate.
        0.5 * layers[above_index].scattering_optical_depth.max(0.0)
    };

    SourceInterfaceInput {
        source_weight,
        particle_ksca_above: layers[above_index].scattering_optical_depth.max(0.0),
        particle_ksca_below: if ilevel > 0 {
            layers[below_index].scattering_optical_depth.max(0.0)
        } else {
            0.0
        },
        ksca_above: layers[above_index].scattering_optical_depth.max(0.0),
        ksca_below: if ilevel > 0 {
            layers[below_index].scattering_optical_depth.max(0.0)
        } else {
            0.0
        },
        phase_coefficients_above: layers[above_index].phase_coefficients,
        phase_coefficients_below: if ilevel > 0 {
            layers[below_index].phase_coefficients
        } else {
            phase_functions::zero_phase_coefficients()
        },
        ..SourceInterfaceInput::default()
    }
}

pub fn fill_source_interfaces_from_layers(
    layers: &[LayerInput],
    source_interfaces: &mut [SourceInterfaceInput],
) {
    if layers.is_empty() || source_interfaces.len() != layers.len() + 1 {
        return;
    }
    for (ilevel, source_interface) in source_interfaces.iter_mut().enumerate() {
        *source_interface = source_interface_from_layers(layers, ilevel);
    }
}
