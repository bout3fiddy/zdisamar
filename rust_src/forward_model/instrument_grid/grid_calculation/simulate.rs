use crate::{
    forward_model::{
        instrument_grid::{
            grid_calculation::{
                storage::{self, Buffers},
                types::{Implementations, InstrumentGridSummary},
            },
            spectral_math::{calibration, grid},
        },
        jacobian::{self, Vector},
    },
    input::{Scene, SpectralChannel},
};

pub const MAX_SUMMARY_SAMPLES: u32 = 128;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SimulationSetup<'a> {
    pub sample_count: usize,
    pub resolved_axis: grid::ResolvedAxis<'a>,
    pub radiance_calibration: calibration::Calibration,
    pub irradiance_calibration: calibration::Calibration,
    pub radiance_slit_kernel: [f64; 5],
    pub irradiance_slit_kernel: [f64; 5],
    pub uses_integrated_radiance_sampling: bool,
    pub uses_integrated_irradiance_sampling: bool,
    pub safe_span: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RunningSummary {
    pub radiance_sum: f64,
    pub irradiance_sum: f64,
    pub reflectance_sum: f64,
    pub noise_sum: f64,
    pub jacobian_sum: Vector,
}

impl Default for RunningSummary {
    fn default() -> Self {
        Self {
            radiance_sum: 0.0,
            irradiance_sum: 0.0,
            reflectance_sum: 0.0,
            noise_sum: 0.0,
            jacobian_sum: jacobian::zero(),
        }
    }
}

impl RunningSummary {
    pub fn add_reflectance_sample(&mut self, radiance: f64, irradiance: f64, reflectance: f64) {
        self.radiance_sum += radiance;
        self.irradiance_sum += irradiance;
        self.reflectance_sum += reflectance;
    }

    pub fn add_noise_sigma(&mut self, values: &[f64]) {
        self.noise_sum += values.iter().sum::<f64>();
    }

    pub fn add_jacobian_row(&mut self, values: Vector) {
        jacobian::add_scaled(&mut self.jacobian_sum, values, 1.0);
    }

    pub fn to_instrument_grid_summary(
        self,
        sample_count: usize,
        wavelengths: &[f64],
        has_noise_sigma: bool,
        mean_jacobian: Option<Vector>,
    ) -> InstrumentGridSummary {
        let denominator = sample_count as f64;
        InstrumentGridSummary {
            sample_count: sample_count as u32,
            wavelength_start_nm: wavelengths[0],
            wavelength_end_nm: wavelengths[sample_count - 1],
            mean_radiance: self.radiance_sum / denominator,
            mean_irradiance: self.irradiance_sum / denominator,
            mean_reflectance: self.reflectance_sum / denominator,
            mean_noise_sigma: if has_noise_sigma {
                self.noise_sum / denominator
            } else {
                0.0
            },
            mean_jacobian,
        }
    }
}

pub fn build_simulation_setup<'a>(
    scene: &'a Scene,
    implementations: Implementations,
    buffers: &Buffers<'_>,
) -> storage::Result<SimulationSetup<'a>> {
    scene
        .validate()
        .map_err(|_| storage::Error::ShapeMismatch)?;
    let sample_count = scene.spectral_grid.sample_count as usize;
    storage::validate_buffers(sample_count, buffers)?;

    let spectral_grid = grid::SpectralGrid {
        start_nm: scene.spectral_grid.start_nm,
        end_nm: scene.spectral_grid.end_nm,
        sample_count: scene.spectral_grid.sample_count,
    };
    let resolved_axis = grid::ResolvedAxis {
        base: spectral_grid,
        explicit_wavelengths_nm: &scene.observation_model.measured_wavelengths_nm,
    };
    resolved_axis
        .validate()
        .map_err(|_| storage::Error::ShapeMismatch)?;

    let span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    Ok(SimulationSetup {
        sample_count,
        resolved_axis,
        radiance_calibration: (implementations.instrument.calibration_for_scene)(
            scene,
            SpectralChannel::Radiance,
        ),
        irradiance_calibration: (implementations.instrument.calibration_for_scene)(
            scene,
            SpectralChannel::Irradiance,
        ),
        radiance_slit_kernel: (implementations.instrument.slit_kernel_for_scene)(
            scene,
            SpectralChannel::Radiance,
        ),
        irradiance_slit_kernel: (implementations.instrument.slit_kernel_for_scene)(
            scene,
            SpectralChannel::Irradiance,
        ),
        uses_integrated_radiance_sampling: (implementations.instrument.uses_integrated_sampling)(
            scene,
            SpectralChannel::Radiance,
        ),
        uses_integrated_irradiance_sampling: (implementations.instrument.uses_integrated_sampling)(
            scene,
            SpectralChannel::Irradiance,
        ),
        safe_span: if span_nm <= 0.0 { 1.0 } else { span_nm },
    })
}

pub fn assemble_reflectance(
    scene: &Scene,
    sample_count: usize,
    buffers: &mut Buffers<'_>,
    summary: &mut RunningSummary,
) {
    let solar_cosine = scene.geometry.solar_cosine_at_altitude(0.0);
    for index in 0..sample_count {
        buffers.reflectance[index] = (buffers.radiance[index] * std::f64::consts::PI)
            / (buffers.irradiance[index] * solar_cosine).max(1.0e-9);
        summary.add_reflectance_sample(
            buffers.radiance[index],
            buffers.irradiance[index],
            buffers.reflectance[index],
        );
    }
}

pub fn jacobian_offset(sample_index: usize, state_index: usize) -> usize {
    sample_index * jacobian::STATE_COUNT + state_index
}

pub fn write_jacobian_row(buffer: &mut [f64], sample_index: usize, values: Vector) {
    for (state_index, value) in values.into_iter().enumerate() {
        buffer[jacobian_offset(sample_index, state_index)] = value;
    }
}

pub fn read_jacobian_row(buffer: &[f64], sample_index: usize) -> Vector {
    let mut values = jacobian::zero();
    for (state_index, value) in values.iter_mut().enumerate() {
        *value = buffer[jacobian_offset(sample_index, state_index)];
    }
    values
}

pub fn copy_jacobian_column_to_scratch(buffer: &[f64], state_index: usize, scratch: &mut [f64]) {
    for (sample_index, value) in scratch.iter_mut().enumerate() {
        *value = buffer[jacobian_offset(sample_index, state_index)];
    }
}

pub fn copy_scratch_to_jacobian_column(scratch: &[f64], buffer: &mut [f64], state_index: usize) {
    for (sample_index, value) in scratch.iter().copied().enumerate() {
        buffer[jacobian_offset(sample_index, state_index)] = value;
    }
}
