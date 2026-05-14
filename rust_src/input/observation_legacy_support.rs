use crate::input::{
    instrument::{
        IntegrationMode, NoiseControls, NoiseModelKind, OperationalBandSupport, SlitIndex,
        SpectralChannel, SpectralChannelControls, SpectralResponse,
    },
    observation_model::ObservationModel,
};

pub fn resolved_channel_controls(
    model: &ObservationModel,
    channel: SpectralChannel,
) -> SpectralChannelControls {
    match channel {
        SpectralChannel::Radiance if model.measurement_pipeline.radiance.explicit => {
            model.measurement_pipeline.radiance.clone()
        }
        SpectralChannel::Irradiance if model.measurement_pipeline.irradiance.explicit => {
            model.measurement_pipeline.irradiance.clone()
        }
        _ => legacy_channel_controls(model, channel),
    }
}

pub fn operational_band_count(model: &ObservationModel) -> usize {
    if !model.operational_band_support.is_empty() {
        return model.operational_band_support.len();
    }
    usize::from(legacy_operational_band_support(model).enabled())
}

pub fn primary_operational_band_support(model: &ObservationModel) -> OperationalBandSupport {
    resolved_operational_band_support(model, 0).unwrap_or_default()
}

pub fn resolved_operational_band_support(
    model: &ObservationModel,
    band_index: usize,
) -> Option<OperationalBandSupport> {
    if band_index < model.operational_band_support.len() {
        return Some(merged_operational_band_support(
            &model.operational_band_support[band_index],
            &legacy_operational_band_support(model),
        ));
    }
    if band_index == 0 {
        let legacy = legacy_operational_band_support(model);
        if legacy.enabled() {
            return Some(legacy);
        }
    }
    None
}

pub fn lut_sampling_half_span_nm(support: &OperationalBandSupport) -> f64 {
    if support.high_resolution_step_nm <= 0.0 {
        return 0.0;
    }

    let mut half_span_nm = support.high_resolution_half_span_nm;
    for offset_nm in support
        .instrument_line_shape
        .offsets_nm
        .iter()
        .take(usize::from(support.instrument_line_shape.sample_count))
    {
        half_span_nm = half_span_nm.max(offset_nm.abs());
    }
    for offset_nm in support
        .instrument_line_shape_table
        .offsets_nm
        .iter()
        .take(usize::from(
            support.instrument_line_shape_table.sample_count,
        ))
    {
        half_span_nm = half_span_nm.max(offset_nm.abs());
    }
    half_span_nm
}

fn legacy_channel_controls(
    model: &ObservationModel,
    channel: SpectralChannel,
) -> SpectralChannelControls {
    let mut controls = SpectralChannelControls {
        response: legacy_spectral_response(model),
        wavelength_shift_nm: model.wavelength_shift_nm,
        noise: NoiseControls {
            enabled: legacy_noise_enabled(model.noise_model, channel),
            model: legacy_noise_model(model.noise_model, channel),
            reference_signal: if channel == SpectralChannel::Radiance {
                model.reference_radiance.clone()
            } else {
                Vec::new()
            },
            reference_sigma: if channel == SpectralChannel::Radiance {
                model.ingested_noise_sigma.clone()
            } else {
                Vec::new()
            },
            ..NoiseControls::default()
        },
        ..SpectralChannelControls::default()
    };
    if channel == SpectralChannel::Radiance {
        controls.multiplicative_offset = model.multiplicative_offset;
        controls.stray_light = model.stray_light;
        controls.use_polarization_scrambler = true;
    }
    controls
}

fn legacy_spectral_response(model: &ObservationModel) -> SpectralResponse {
    let support = primary_operational_band_support(model);
    let resolved_high_resolution_step_nm = if support.high_resolution_step_nm > 0.0 {
        support.high_resolution_step_nm
    } else {
        model.high_resolution_step_nm
    };
    let resolved_high_resolution_half_span_nm = if support.high_resolution_half_span_nm > 0.0 {
        support.high_resolution_half_span_nm
    } else {
        model.high_resolution_half_span_nm
    };

    SpectralResponse {
        slit_index: match model.builtin_line_shape {
            crate::input::instrument::BuiltinLineShapeKind::Gaussian => {
                if support.instrument_line_shape_table.nominal_count > 0
                    || model.instrument_line_shape_table.nominal_count > 0
                {
                    SlitIndex::Table
                } else {
                    SlitIndex::GaussianModulated
                }
            }
            crate::input::instrument::BuiltinLineShapeKind::FlatTopN4 => SlitIndex::FlatTopN4,
            crate::input::instrument::BuiltinLineShapeKind::TripleFlatTopN4 => {
                SlitIndex::TripleFlatTopN4
            }
        },
        fwhm_nm: model.instrument_line_fwhm_nm,
        builtin_line_shape: model.builtin_line_shape,
        integration_mode: if model.adaptive_reference_grid.enabled() {
            IntegrationMode::Adaptive
        } else if resolved_high_resolution_step_nm > 0.0
            && resolved_high_resolution_half_span_nm > 0.0
        {
            IntegrationMode::ExplicitHrGrid
        } else {
            IntegrationMode::Auto
        },
        high_resolution_step_nm: resolved_high_resolution_step_nm,
        high_resolution_half_span_nm: resolved_high_resolution_half_span_nm,
        instrument_line_shape: if support.instrument_line_shape.sample_count > 0 {
            support.instrument_line_shape
        } else {
            model.instrument_line_shape.clone()
        },
        instrument_line_shape_table: if support.instrument_line_shape_table.nominal_count > 0 {
            support.instrument_line_shape_table
        } else {
            model.instrument_line_shape_table.clone()
        },
        ..SpectralResponse::default()
    }
}

fn legacy_operational_band_support(model: &ObservationModel) -> OperationalBandSupport {
    OperationalBandSupport {
        id: if model.instrument != crate::input::instrument::Id::Unset {
            "primary".to_string()
        } else {
            String::new()
        },
        high_resolution_step_nm: model.high_resolution_step_nm,
        high_resolution_half_span_nm: model.high_resolution_half_span_nm,
        instrument_line_shape: model.instrument_line_shape.clone(),
        instrument_line_shape_table: model.instrument_line_shape_table.clone(),
        operational_refspec_grid: model.operational_refspec_grid.clone(),
        operational_solar_spectrum: model.operational_solar_spectrum.clone(),
        o2_operational_lut: model.o2_operational_lut.clone(),
        o2o2_operational_lut: model.o2o2_operational_lut.clone(),
    }
}

fn merged_operational_band_support(
    explicit: &OperationalBandSupport,
    legacy: &OperationalBandSupport,
) -> OperationalBandSupport {
    let mut merged = legacy.clone();
    if !explicit.id.is_empty() {
        merged.id.clone_from(&explicit.id);
    }
    if explicit.high_resolution_step_nm > 0.0 {
        merged.high_resolution_step_nm = explicit.high_resolution_step_nm;
        merged.high_resolution_half_span_nm = explicit.high_resolution_half_span_nm;
    }
    if explicit.instrument_line_shape.sample_count > 0 {
        merged.instrument_line_shape = explicit.instrument_line_shape.clone();
    }
    if explicit.instrument_line_shape_table.nominal_count > 0 {
        merged.instrument_line_shape_table = explicit.instrument_line_shape_table.clone();
    }
    if explicit.operational_refspec_grid.enabled() {
        merged.operational_refspec_grid = explicit.operational_refspec_grid.clone();
    }
    if explicit.operational_solar_spectrum.enabled() {
        merged.operational_solar_spectrum = explicit.operational_solar_spectrum.clone();
    }
    if explicit.o2_operational_lut.enabled() {
        merged.o2_operational_lut = explicit.o2_operational_lut.clone();
    }
    if explicit.o2o2_operational_lut.enabled() {
        merged.o2o2_operational_lut = explicit.o2o2_operational_lut.clone();
    }
    merged
}

fn legacy_noise_enabled(model: NoiseModelKind, channel: SpectralChannel) -> bool {
    match channel {
        SpectralChannel::Radiance => model != NoiseModelKind::None,
        SpectralChannel::Irradiance => {
            matches!(
                model,
                NoiseModelKind::ShotNoise | NoiseModelKind::LabOperational
            )
        }
    }
}

fn legacy_noise_model(model: NoiseModelKind, channel: SpectralChannel) -> NoiseModelKind {
    if channel == SpectralChannel::Radiance {
        return model;
    }
    match model {
        NoiseModelKind::ShotNoise | NoiseModelKind::LabOperational => model,
        NoiseModelKind::None | NoiseModelKind::S5pOperational | NoiseModelKind::SnrFromInput => {
            NoiseModelKind::None
        }
    }
}
