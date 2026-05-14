use crate::input::instrument::MAX_LINE_SHAPE_SAMPLES;

pub const DEFAULT_INTEGRATION_SAMPLE_COUNT: usize = 5;
pub const MAX_INTEGRATION_SAMPLE_COUNT: usize = MAX_LINE_SHAPE_SAMPLES;

#[derive(Debug, Clone, PartialEq)]
pub struct IntegrationKernel {
    pub enabled: bool,
    pub sample_count: usize,
    pub offsets_nm: [f64; MAX_INTEGRATION_SAMPLE_COUNT],
    pub weights: [f64; MAX_INTEGRATION_SAMPLE_COUNT],
}

impl Default for IntegrationKernel {
    fn default() -> Self {
        Self {
            enabled: false,
            sample_count: 0,
            offsets_nm: [0.0; MAX_INTEGRATION_SAMPLE_COUNT],
            weights: [0.0; MAX_INTEGRATION_SAMPLE_COUNT],
        }
    }
}
