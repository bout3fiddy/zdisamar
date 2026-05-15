use crate::{
    forward_model::instrument_grid::InstrumentGridProduct, input::o2a_reference::ReferenceSample,
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RangeExtremum {
    pub wavelength_nm: f64,
    pub value: f64,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct ComparisonMetrics {
    pub sample_count: usize,
    pub nonzero_sample_count: usize,
    pub exact_match_within_zero_tolerance: bool,
    pub mean_signed_difference: f64,
    pub mean_abs_difference: f64,
    pub root_mean_square_difference: f64,
    pub max_abs_difference: f64,
    pub max_abs_difference_wavelength_nm: f64,
    pub correlation: f64,
    pub blue_wing_mean_difference: f64,
    pub trough_wavelength_difference_nm: f64,
    pub trough_value_difference: f64,
    pub rebound_peak_difference: f64,
    pub mid_band_mean_difference: f64,
    pub red_wing_mean_difference: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TrendTolerances {
    pub mean_abs_difference_abs: f64,
    pub root_mean_square_difference_abs: f64,
    pub max_abs_difference_abs: f64,
    pub correlation_abs: f64,
    pub blue_wing_mean_difference_abs: f64,
    pub trough_wavelength_difference_nm_abs: f64,
    pub trough_value_difference_abs: f64,
    pub rebound_peak_difference_abs: f64,
    pub mid_band_mean_difference_abs: f64,
    pub red_wing_mean_difference_abs: f64,
}

impl TrendTolerances {
    pub fn with_core_tolerances(
        mean_abs_difference_abs: f64,
        root_mean_square_difference_abs: f64,
        max_abs_difference_abs: f64,
        correlation_abs: f64,
    ) -> Self {
        Self {
            mean_abs_difference_abs,
            root_mean_square_difference_abs,
            max_abs_difference_abs,
            correlation_abs,
            blue_wing_mean_difference_abs: 1.0e-6,
            trough_wavelength_difference_nm_abs: 1.0e-6,
            trough_value_difference_abs: 1.0e-6,
            rebound_peak_difference_abs: 1.0e-6,
            mid_band_mean_difference_abs: 1.0e-6,
            red_wing_mean_difference_abs: 1.0e-6,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrendState {
    Improved,
    Flat,
    Regressed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AssessmentVerdict {
    ExactZeroPass,
    BaselinePass,
    RegressionFail,
    NonzeroFail,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AssessmentTrend {
    pub mean_abs_difference: TrendState,
    pub root_mean_square_difference: TrendState,
    pub max_abs_difference: TrendState,
    pub correlation: TrendState,
    pub blue_wing_mean_difference: TrendState,
    pub trough_wavelength_difference_nm: TrendState,
    pub trough_value_difference: TrendState,
    pub rebound_peak_difference: TrendState,
    pub mid_band_mean_difference: TrendState,
    pub red_wing_mean_difference: TrendState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AssessmentOutcome {
    pub verdict: AssessmentVerdict,
    pub trend: AssessmentTrend,
}

pub fn mean_vector_in_range(
    wavelengths_nm: &[f64],
    values: &[f64],
    start_nm: f64,
    end_nm: f64,
) -> f64 {
    let mut sum = 0.0;
    let mut count = 0;
    for (&wavelength_nm, &value) in wavelengths_nm.iter().zip(values) {
        if wavelength_nm < start_nm || wavelength_nm > end_nm {
            continue;
        }
        sum += value;
        count += 1;
    }
    if count == 0 { 0.0 } else { sum / count as f64 }
}

pub fn min_vector_in_range(
    wavelengths_nm: &[f64],
    values: &[f64],
    start_nm: f64,
    end_nm: f64,
) -> RangeExtremum {
    let mut best = f64::INFINITY;
    let mut best_wavelength = start_nm;
    for (&wavelength_nm, &value) in wavelengths_nm.iter().zip(values) {
        if wavelength_nm < start_nm || wavelength_nm > end_nm {
            continue;
        }
        if value < best {
            best = value;
            best_wavelength = wavelength_nm;
        }
    }
    RangeExtremum {
        wavelength_nm: best_wavelength,
        value: best,
    }
}

pub fn max_vector_in_range(
    wavelengths_nm: &[f64],
    values: &[f64],
    start_nm: f64,
    end_nm: f64,
) -> f64 {
    let mut best = -f64::INFINITY;
    for (&wavelength_nm, &value) in wavelengths_nm.iter().zip(values) {
        if wavelength_nm < start_nm || wavelength_nm > end_nm {
            continue;
        }
        best = best.max(value);
    }
    best
}

pub fn mean_reference_in_range(reference: &[ReferenceSample], start_nm: f64, end_nm: f64) -> f64 {
    let mut sum = 0.0;
    let mut count = 0;
    for sample in reference {
        if sample.wavelength_nm < start_nm || sample.wavelength_nm > end_nm {
            continue;
        }
        sum += sample.reflectance;
        count += 1;
    }
    if count == 0 { 0.0 } else { sum / count as f64 }
}

pub fn min_reference_in_range(
    reference: &[ReferenceSample],
    start_nm: f64,
    end_nm: f64,
) -> RangeExtremum {
    let mut best = f64::INFINITY;
    let mut best_wavelength = start_nm;
    for sample in reference {
        if sample.wavelength_nm < start_nm || sample.wavelength_nm > end_nm {
            continue;
        }
        if sample.reflectance < best {
            best = sample.reflectance;
            best_wavelength = sample.wavelength_nm;
        }
    }
    RangeExtremum {
        wavelength_nm: best_wavelength,
        value: best,
    }
}

pub fn max_reference_in_range(reference: &[ReferenceSample], start_nm: f64, end_nm: f64) -> f64 {
    let mut best = -f64::INFINITY;
    for sample in reference {
        if sample.wavelength_nm < start_nm || sample.wavelength_nm > end_nm {
            continue;
        }
        best = best.max(sample.reflectance);
    }
    best
}

pub fn interpolate_vector(
    wavelengths_nm: &[f64],
    values: &[f64],
    target_wavelength_nm: f64,
) -> f64 {
    let sample_count = wavelengths_nm.len().min(values.len());
    if sample_count == 0 {
        return 0.0;
    }
    let last_index = sample_count - 1;
    if target_wavelength_nm <= wavelengths_nm[0] {
        return values[0];
    }
    if target_wavelength_nm >= wavelengths_nm[last_index] {
        return values[last_index];
    }

    let mut lower_index = 0;
    while lower_index + 1 < sample_count && wavelengths_nm[lower_index + 1] < target_wavelength_nm {
        lower_index += 1;
    }
    let upper_index = lower_index + 1;
    let lower_wavelength = wavelengths_nm[lower_index];
    let upper_wavelength = wavelengths_nm[upper_index];
    let denominator = upper_wavelength - lower_wavelength;
    if denominator == 0.0 {
        return values[upper_index];
    }
    let blend = (target_wavelength_nm - lower_wavelength) / denominator;
    values[lower_index] + (values[upper_index] - values[lower_index]) * blend
}

pub fn compare_lower_is_better(current: f64, baseline: f64, tolerance: f64) -> TrendState {
    if current < baseline - tolerance {
        return TrendState::Improved;
    }
    if current > baseline + tolerance {
        return TrendState::Regressed;
    }
    TrendState::Flat
}

pub fn compare_higher_is_better(current: f64, baseline: f64, tolerance: f64) -> TrendState {
    if current > baseline + tolerance {
        return TrendState::Improved;
    }
    if current < baseline - tolerance {
        return TrendState::Regressed;
    }
    TrendState::Flat
}

pub fn compare_absolute_ceiling(current: f64, ceiling: f64) -> TrendState {
    if current > ceiling {
        return TrendState::Regressed;
    }
    TrendState::Flat
}

pub fn assess_against_baseline(
    current: ComparisonMetrics,
    baseline: ComparisonMetrics,
    tolerances: TrendTolerances,
    allowed_to_fail: bool,
) -> AssessmentOutcome {
    let trend = AssessmentTrend {
        mean_abs_difference: compare_lower_is_better(
            current.mean_abs_difference,
            baseline.mean_abs_difference,
            tolerances.mean_abs_difference_abs,
        ),
        root_mean_square_difference: compare_lower_is_better(
            current.root_mean_square_difference,
            baseline.root_mean_square_difference,
            tolerances.root_mean_square_difference_abs,
        ),
        max_abs_difference: compare_lower_is_better(
            current.max_abs_difference,
            baseline.max_abs_difference,
            tolerances.max_abs_difference_abs,
        ),
        correlation: compare_higher_is_better(
            current.correlation,
            baseline.correlation,
            tolerances.correlation_abs,
        ),
        blue_wing_mean_difference: compare_lower_is_better(
            current.blue_wing_mean_difference.abs(),
            baseline.blue_wing_mean_difference.abs(),
            0.0,
        ),
        trough_wavelength_difference_nm: compare_lower_is_better(
            current.trough_wavelength_difference_nm.abs(),
            baseline.trough_wavelength_difference_nm.abs(),
            0.0,
        ),
        trough_value_difference: compare_lower_is_better(
            current.trough_value_difference.abs(),
            baseline.trough_value_difference.abs(),
            0.0,
        ),
        rebound_peak_difference: compare_lower_is_better(
            current.rebound_peak_difference.abs(),
            baseline.rebound_peak_difference.abs(),
            0.0,
        ),
        mid_band_mean_difference: compare_lower_is_better(
            current.mid_band_mean_difference.abs(),
            baseline.mid_band_mean_difference.abs(),
            0.0,
        ),
        red_wing_mean_difference: compare_lower_is_better(
            current.red_wing_mean_difference.abs(),
            baseline.red_wing_mean_difference.abs(),
            0.0,
        ),
    };

    let morphology_ceiling_regressed = compare_absolute_ceiling(
        current.blue_wing_mean_difference.abs(),
        tolerances.blue_wing_mean_difference_abs,
    ) == TrendState::Regressed
        || compare_absolute_ceiling(
            current.trough_wavelength_difference_nm.abs(),
            tolerances.trough_wavelength_difference_nm_abs,
        ) == TrendState::Regressed
        || compare_absolute_ceiling(
            current.trough_value_difference.abs(),
            tolerances.trough_value_difference_abs,
        ) == TrendState::Regressed
        || compare_absolute_ceiling(
            current.rebound_peak_difference.abs(),
            tolerances.rebound_peak_difference_abs,
        ) == TrendState::Regressed
        || compare_absolute_ceiling(
            current.mid_band_mean_difference.abs(),
            tolerances.mid_band_mean_difference_abs,
        ) == TrendState::Regressed
        || compare_absolute_ceiling(
            current.red_wing_mean_difference.abs(),
            tolerances.red_wing_mean_difference_abs,
        ) == TrendState::Regressed;

    if current.exact_match_within_zero_tolerance {
        return AssessmentOutcome {
            verdict: AssessmentVerdict::ExactZeroPass,
            trend,
        };
    }
    if !allowed_to_fail {
        return AssessmentOutcome {
            verdict: AssessmentVerdict::NonzeroFail,
            trend,
        };
    }
    if trend.mean_abs_difference == TrendState::Regressed
        || trend.root_mean_square_difference == TrendState::Regressed
        || trend.max_abs_difference == TrendState::Regressed
        || trend.correlation == TrendState::Regressed
        || morphology_ceiling_regressed
    {
        return AssessmentOutcome {
            verdict: AssessmentVerdict::RegressionFail,
            trend,
        };
    }
    AssessmentOutcome {
        verdict: AssessmentVerdict::BaselinePass,
        trend,
    }
}

pub fn compute_comparison_metrics(
    product: &InstrumentGridProduct,
    reference: &[ReferenceSample],
    zero_tolerance_abs: f64,
) -> ComparisonMetrics {
    let blue_wing_mean =
        mean_vector_in_range(&product.wavelengths, &product.reflectance, 755.0, 758.5);
    let trough = min_vector_in_range(&product.wavelengths, &product.reflectance, 760.2, 761.1);
    let rebound_peak =
        max_vector_in_range(&product.wavelengths, &product.reflectance, 761.8, 762.4);
    let mid_band_mean =
        mean_vector_in_range(&product.wavelengths, &product.reflectance, 763.8, 765.5);
    let red_wing_mean =
        mean_vector_in_range(&product.wavelengths, &product.reflectance, 769.5, 771.0);

    let reference_blue_wing_mean = mean_reference_in_range(reference, 755.0, 758.5);
    let reference_trough = min_reference_in_range(reference, 760.2, 761.1);
    let reference_rebound_peak = max_reference_in_range(reference, 761.8, 762.4);
    let reference_mid_band_mean = mean_reference_in_range(reference, 763.8, 765.5);
    let reference_red_wing_mean = mean_reference_in_range(reference, 769.5, 771.0);

    let mut sum_signed = 0.0;
    let mut sum_abs = 0.0;
    let mut sum_sq = 0.0;
    let mut generated_mean = 0.0;
    let mut reference_mean = 0.0;
    let mut max_abs_difference = 0.0;
    let mut max_abs_difference_wavelength_nm =
        reference.first().map_or(0.0, |sample| sample.wavelength_nm);
    let mut nonzero_sample_count = 0;

    for sample in reference {
        let generated = interpolate_vector(
            &product.wavelengths,
            &product.reflectance,
            sample.wavelength_nm,
        );
        let delta = generated - sample.reflectance;
        let abs_delta = delta.abs();
        sum_signed += delta;
        sum_abs += abs_delta;
        sum_sq += delta * delta;
        generated_mean += generated;
        reference_mean += sample.reflectance;
        if abs_delta > zero_tolerance_abs {
            nonzero_sample_count += 1;
        }
        if abs_delta > max_abs_difference {
            max_abs_difference = abs_delta;
            max_abs_difference_wavelength_nm = sample.wavelength_nm;
        }
    }

    let sample_count = reference.len() as f64;
    if !reference.is_empty() {
        generated_mean /= sample_count;
        reference_mean /= sample_count;
    }

    let mut covariance = 0.0;
    let mut generated_variance = 0.0;
    let mut reference_variance = 0.0;
    for sample in reference {
        let generated = interpolate_vector(
            &product.wavelengths,
            &product.reflectance,
            sample.wavelength_nm,
        );
        covariance += (generated - generated_mean) * (sample.reflectance - reference_mean);
        generated_variance += (generated - generated_mean).powi(2);
        reference_variance += (sample.reflectance - reference_mean).powi(2);
    }

    let correlation = if generated_variance == 0.0 || reference_variance == 0.0 {
        0.0
    } else {
        covariance / (generated_variance * reference_variance).sqrt()
    };

    ComparisonMetrics {
        sample_count: reference.len(),
        nonzero_sample_count,
        exact_match_within_zero_tolerance: nonzero_sample_count == 0,
        mean_signed_difference: if reference.is_empty() {
            0.0
        } else {
            sum_signed / sample_count
        },
        mean_abs_difference: if reference.is_empty() {
            0.0
        } else {
            sum_abs / sample_count
        },
        root_mean_square_difference: if reference.is_empty() {
            0.0
        } else {
            (sum_sq / sample_count).sqrt()
        },
        max_abs_difference,
        max_abs_difference_wavelength_nm,
        correlation,
        blue_wing_mean_difference: blue_wing_mean - reference_blue_wing_mean,
        trough_wavelength_difference_nm: trough.wavelength_nm - reference_trough.wavelength_nm,
        trough_value_difference: trough.value - reference_trough.value,
        rebound_peak_difference: rebound_peak - reference_rebound_peak,
        mid_band_mean_difference: mid_band_mean - reference_mid_band_mean,
        red_wing_mean_difference: red_wing_mean - reference_red_wing_mean,
    }
}
