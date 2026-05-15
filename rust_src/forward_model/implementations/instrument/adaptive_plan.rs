use super::response::{adaptive_kernel_half_span_nm, spectral_response_weight};
use crate::{
    common::math::quadrature::gauss_legendre,
    forward_model::{
        instrument_grid::grid_calculation::spectral_eval::{
            IntegrationKernel, MAX_INTEGRATION_SAMPLE_COUNT,
        },
        optical_properties::PreparedOpticalState,
    },
    input::{
        instrument::{AdaptiveReferenceGrid, IntegrationMode, SpectralResponse},
        reference_data::SpectroscopyLineList,
        scene::Scene,
    },
};

#[derive(Debug, Clone, Copy, PartialEq)]
struct AdaptiveKernelSupportWindow {
    global_start_nm: f64,
    global_end_nm: f64,
    window_start_nm: f64,
    window_end_nm: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct AdaptiveIntervalDescriptor {
    interval_start_nm: f64,
    interval_end_nm: f64,
    division_count: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct AdaptiveSupportRange {
    start_index: usize,
    end_index: usize,
}

pub fn build_adaptive_integration_kernel(
    scene: &Scene,
    prepared: &PreparedOpticalState,
    response: &SpectralResponse,
    nominal_wavelength_nm: f64,
    apply_disamar_midpoint_bias: bool,
) -> Option<IntegrationKernel> {
    let adaptive = scene.observation_model.adaptive_reference_grid;
    if !adaptive.enabled() || response.fwhm_nm <= 0.0 {
        return None;
    }
    let has_single_line_list = prepared
        .spectroscopy_lines
        .as_ref()
        .is_some_and(|line_list| !line_list.lines.is_empty());
    if !has_single_line_list && prepared.line_absorbers.is_empty() {
        return None;
    }

    let support_window = adaptive_kernel_support_window(scene, response, nominal_wavelength_nm);
    if support_window.window_end_nm <= support_window.window_start_nm {
        return None;
    }
    let plan = build_adaptive_interval_plan(scene, prepared, response)?;
    let (wavelengths, raw_weights) = append_adaptive_samples_from_plan(
        &plan,
        response,
        nominal_wavelength_nm,
        support_window.global_start_nm,
        support_window.global_end_nm,
        apply_disamar_midpoint_bias,
    )?;
    finalize_adaptive_kernel(nominal_wavelength_nm, wavelengths, raw_weights)
}

pub fn build_adaptive_support_wavelengths(
    scene: &Scene,
    prepared: &PreparedOpticalState,
    response: &SpectralResponse,
) -> Option<Vec<f64>> {
    let adaptive = scene.observation_model.adaptive_reference_grid;
    if !adaptive.enabled() || response.fwhm_nm <= 0.0 {
        return None;
    }
    let has_single_line_list = prepared
        .spectroscopy_lines
        .as_ref()
        .is_some_and(|line_list| !line_list.lines.is_empty());
    if !has_single_line_list && prepared.line_absorbers.is_empty() {
        return None;
    }

    let plan = build_adaptive_interval_plan(scene, prepared, response)?;
    let mut support = Vec::new();
    for interval in &plan {
        let order = interval.division_count;
        if order == 0 {
            continue;
        }
        let (nodes_01, _) = fill_adaptive_unit_gauss(response, order)?;
        let interval_width_nm = interval.interval_end_nm - interval.interval_start_nm;
        for node_01 in nodes_01 {
            // DISAMAR stores the cutoff grid on the same realized adaptive
            // support used for convolution, before nominal-window trimming.
            let wavelength_nm = interval.interval_start_nm + interval_width_nm * node_01;
            if wavelength_nm.is_finite() {
                support.push(wavelength_nm);
            }
        }
    }
    if support.is_empty() {
        return None;
    }

    support.sort_by(f64::total_cmp);
    support.dedup_by(|left, right| (*left - *right).abs() <= 1.0e-9);
    Some(support)
}

pub fn build_disamar_realized_kernel(
    scene: &Scene,
    response: &SpectralResponse,
    nominal_wavelength_nm: f64,
    apply_disamar_midpoint_bias: bool,
) -> Option<IntegrationKernel> {
    if response.fwhm_nm <= 0.0 {
        return None;
    }
    let support_window = adaptive_kernel_support_window(scene, response, nominal_wavelength_nm);
    if support_window.window_end_nm <= support_window.window_start_nm {
        return None;
    }
    let division_count =
        disamar_interval_division_count(scene.observation_model.adaptive_reference_grid, response);
    if division_count == 0 {
        return None;
    }
    let plan = build_disamar_interval_plan(
        support_window.global_start_nm,
        support_window.global_end_nm,
        response.fwhm_nm.max(1.0e-4),
        division_count,
    )?;
    let (wavelengths, raw_weights) = append_adaptive_samples_from_plan(
        &plan,
        response,
        nominal_wavelength_nm,
        support_window.global_start_nm,
        support_window.global_end_nm,
        apply_disamar_midpoint_bias,
    )?;
    finalize_adaptive_kernel(nominal_wavelength_nm, wavelengths, raw_weights)
}

fn adaptive_kernel_support_window(
    scene: &Scene,
    response: &SpectralResponse,
    nominal_wavelength_nm: f64,
) -> AdaptiveKernelSupportWindow {
    let fwhm_nm = response.fwhm_nm.max(1.0e-4);
    let half_span_nm = adaptive_kernel_half_span_nm(response);
    let global_start_nm = scene.spectral_grid.start_nm - 2.0 * fwhm_nm;
    let global_end_nm = scene.spectral_grid.end_nm + 2.0 * fwhm_nm;
    AdaptiveKernelSupportWindow {
        global_start_nm,
        global_end_nm,
        window_start_nm: global_start_nm.max(nominal_wavelength_nm - half_span_nm),
        window_end_nm: global_end_nm.min(nominal_wavelength_nm + half_span_nm),
    }
}

fn build_adaptive_interval_plan(
    scene: &Scene,
    prepared: &PreparedOpticalState,
    response: &SpectralResponse,
) -> Option<Vec<AdaptiveIntervalDescriptor>> {
    let adaptive = scene.observation_model.adaptive_reference_grid;
    let support_window =
        adaptive_kernel_support_window(scene, response, scene.spectral_grid.start_nm);
    let fwhm_nm = response.fwhm_nm.max(1.0e-4);
    let strong_centers_nm = collect_adaptive_strong_line_centers(
        prepared,
        support_window.global_start_nm,
        support_window.global_end_nm,
    )?;

    let mut plan = Vec::new();
    let mut current_nm = support_window.global_start_nm;
    let mut strong_index = 0;
    while strong_index < strong_centers_nm.len()
        && strong_centers_nm[strong_index] <= current_nm + 1.0e-12
    {
        strong_index += 1;
    }

    while plan.len() < MAX_INTEGRATION_SAMPLE_COUNT {
        let mut next_nm = current_nm + fwhm_nm;
        if strong_index < strong_centers_nm.len()
            && strong_centers_nm[strong_index] < next_nm - 1.0e-12
        {
            next_nm = strong_centers_nm[strong_index];
            strong_index += 1;
        }
        if next_nm <= current_nm + 1.0e-12 {
            next_nm = current_nm + fwhm_nm;
        }
        plan.push(AdaptiveIntervalDescriptor {
            interval_start_nm: current_nm,
            interval_end_nm: next_nm,
            division_count: 1,
        });
        current_nm = next_nm;
        while strong_index < strong_centers_nm.len()
            && strong_centers_nm[strong_index] <= current_nm + 1.0e-12
        {
            strong_index += 1;
        }
        if current_nm > support_window.global_end_nm {
            break;
        }
    }
    if plan.is_empty() || current_nm <= support_window.global_end_nm {
        return None;
    }

    let max_interval_nm = max_adaptive_interval_width(&plan);
    let has_strong_lines = !strong_centers_nm.is_empty();
    for interval in &mut plan {
        interval.division_count = adaptive_interval_division_count(
            adaptive,
            interval.interval_end_nm - interval.interval_start_nm,
            max_interval_nm,
            has_strong_lines,
        );
    }
    Some(plan)
}

fn append_adaptive_samples_from_plan(
    plan: &[AdaptiveIntervalDescriptor],
    response: &SpectralResponse,
    nominal_wavelength_nm: f64,
    global_start_nm: f64,
    global_end_nm: f64,
    apply_disamar_midpoint_bias: bool,
) -> Option<(Vec<f64>, Vec<f64>)> {
    let support_half_span_nm = adaptive_kernel_half_span_nm(response);
    let generation_start_nm = global_start_nm
        .max(nominal_wavelength_nm - support_half_span_nm - response.fwhm_nm.max(1.0e-4));
    let generation_end_nm = global_end_nm
        .min(nominal_wavelength_nm + support_half_span_nm + response.fwhm_nm.max(1.0e-4));

    let mut candidates = Vec::<(f64, f64)>::new();
    for interval in plan {
        if interval.interval_end_nm < generation_start_nm - 1.0e-12 {
            continue;
        }
        if interval.interval_start_nm > generation_end_nm + 1.0e-12 {
            continue;
        }
        let order = interval.division_count;
        if order == 0 {
            continue;
        }
        let (nodes_01, weights_01) = fill_adaptive_unit_gauss(response, order)?;
        let interval_width_nm = interval.interval_end_nm - interval.interval_start_nm;
        for gauss_index in 0..order {
            let wavelength_nm = realized_interval_wavelength_nm(
                response,
                interval.interval_start_nm,
                interval_width_nm,
                nodes_01[gauss_index],
                order,
                gauss_index,
                apply_disamar_midpoint_bias,
            );
            let raw_weight =
                spectral_response_weight(response, wavelength_nm - nominal_wavelength_nm)
                    * (interval_width_nm * weights_01[gauss_index]);
            append_finite_sample(&mut candidates, wavelength_nm, raw_weight)?;
        }
    }
    if candidates.is_empty() {
        return None;
    }
    candidates.sort_by(|left, right| left.0.total_cmp(&right.0));

    let wavelengths = candidates
        .iter()
        .map(|(wavelength, _)| *wavelength)
        .collect::<Vec<_>>();
    let support_range =
        select_vendor_support_range(&wavelengths, nominal_wavelength_nm, support_half_span_nm);
    let mut selected = Vec::<(f64, f64)>::new();
    for candidate in candidates
        .iter()
        .take(support_range.end_index + 1)
        .skip(support_range.start_index)
    {
        append_finite_sample(&mut selected, candidate.0, candidate.1)?;
    }
    if selected.is_empty() {
        return None;
    }
    let (sample_wavelengths_nm, sample_raw_weights): (Vec<_>, Vec<_>) =
        selected.into_iter().unzip();
    Some((sample_wavelengths_nm, sample_raw_weights))
}

fn finalize_adaptive_kernel(
    nominal_wavelength_nm: f64,
    mut sample_wavelengths_nm: Vec<f64>,
    mut sample_raw_weights: Vec<f64>,
) -> Option<IntegrationKernel> {
    if sample_wavelengths_nm.is_empty() || sample_wavelengths_nm.len() != sample_raw_weights.len() {
        return None;
    }
    let mut samples = sample_wavelengths_nm
        .drain(..)
        .zip(sample_raw_weights.drain(..))
        .collect::<Vec<_>>();
    samples.sort_by(|left, right| left.0.total_cmp(&right.0));

    let mut merged = Vec::<(f64, f64)>::new();
    for (wavelength_nm, raw_weight) in samples {
        if let Some(last) = merged.last_mut()
            && (last.0 - wavelength_nm).abs() <= 1.0e-9
        {
            last.1 += raw_weight;
            continue;
        }
        merged.push((wavelength_nm, raw_weight));
    }
    if merged.is_empty() || merged.len() > MAX_INTEGRATION_SAMPLE_COUNT {
        return None;
    }
    let total_weight = merged.iter().map(|(_, raw_weight)| raw_weight).sum::<f64>();
    if !total_weight.is_finite() || total_weight <= 0.0 {
        return None;
    }

    let offsets_nm = merged
        .iter()
        .map(|(wavelength_nm, _)| wavelength_nm - nominal_wavelength_nm)
        .collect::<Vec<_>>();
    let weights = merged
        .iter()
        .map(|(_, raw_weight)| raw_weight / total_weight)
        .collect::<Vec<_>>();
    Some(IntegrationKernel::from_samples(offsets_nm, weights))
}

fn collect_adaptive_strong_line_centers(
    prepared: &PreparedOpticalState,
    global_start_nm: f64,
    global_end_nm: f64,
) -> Option<Vec<f64>> {
    let mut centers_nm = Vec::new();
    if let Some(line_list) = &prepared.spectroscopy_lines {
        collect_adaptive_strong_line_centers_from_list(
            line_list,
            global_start_nm,
            global_end_nm,
            &mut centers_nm,
        )?;
    }
    for line_absorber in &prepared.line_absorbers {
        collect_adaptive_strong_line_centers_from_list(
            &line_absorber.line_list,
            global_start_nm,
            global_end_nm,
            &mut centers_nm,
        )?;
    }
    if centers_nm.is_empty() {
        return Some(centers_nm);
    }
    centers_nm.sort_by(f64::total_cmp);
    centers_nm.dedup_by(|left, right| (*left - *right).abs() <= 1.0e-9);
    Some(centers_nm)
}

fn collect_adaptive_strong_line_centers_from_list(
    line_list: &SpectroscopyLineList,
    global_start_nm: f64,
    global_end_nm: f64,
    centers_nm: &mut Vec<f64>,
) -> Option<()> {
    let Some(threshold_strength) = line_list
        .runtime_controls
        .threshold_strength(&line_list.lines)
    else {
        return Some(());
    };
    for line in &line_list.lines {
        if line.line_strength_cm2_per_molecule < threshold_strength {
            continue;
        }
        if line.center_wavelength_nm < global_start_nm || line.center_wavelength_nm > global_end_nm
        {
            continue;
        }
        if centers_nm.len() >= MAX_INTEGRATION_SAMPLE_COUNT {
            return None;
        }
        centers_nm.push(line.center_wavelength_nm);
    }
    Some(())
}

fn max_adaptive_interval_width(intervals: &[AdaptiveIntervalDescriptor]) -> f64 {
    if intervals.is_empty() {
        return 1.0;
    }
    let mut max_width_nm: f64 = 0.0;
    if intervals.len() > 2 {
        for interval in &intervals[1..intervals.len() - 1] {
            max_width_nm = max_width_nm.max(interval.interval_end_nm - interval.interval_start_nm);
        }
    }
    if max_width_nm <= 0.0 {
        for interval in intervals {
            max_width_nm = max_width_nm.max(interval.interval_end_nm - interval.interval_start_nm);
        }
    }
    max_width_nm.max(1.0e-9)
}

fn adaptive_interval_division_count(
    adaptive: AdaptiveReferenceGrid,
    interval_width_nm: f64,
    max_interval_nm: f64,
    has_strong_lines: bool,
) -> usize {
    if !has_strong_lines {
        return usize::from(adaptive.points_per_fwhm).max(1);
    }
    let min_divisions = usize::from(adaptive.strong_line_min_divisions).max(1);
    let max_divisions = usize::from(adaptive.strong_line_max_divisions).max(min_divisions);
    let scaled = (max_divisions as f64
        * (interval_width_nm.max(1.0e-9) / max_interval_nm.max(1.0e-9)))
    .round() as usize;
    scaled
        .max(min_divisions)
        .clamp(min_divisions, max_divisions)
}

fn fill_adaptive_unit_gauss(
    response: &SpectralResponse,
    order: usize,
) -> Option<(Vec<f64>, Vec<f64>)> {
    if order == 0 || order > MAX_INTEGRATION_SAMPLE_COUNT {
        return None;
    }
    let mut nodes_01 = vec![0.0; order];
    let mut weights_01 = vec![0.0; order];
    if response.integration_mode == IntegrationMode::DisamarHrGrid {
        gauss_legendre::fill_disamar_div_points_01(order as u32, &mut nodes_01, &mut weights_01)
            .ok()?;
    } else {
        gauss_legendre::fill_nodes_and_weights(order as u32, &mut nodes_01, &mut weights_01)
            .ok()?;
        for index in 0..order {
            nodes_01[index] = (nodes_01[index] + 1.0) * 0.5;
            weights_01[index] *= 0.5;
        }
    }
    Some((nodes_01, weights_01))
}

fn realized_interval_wavelength_nm(
    response: &SpectralResponse,
    interval_start_nm: f64,
    interval_width_nm: f64,
    node_01: f64,
    order: usize,
    gauss_index: usize,
    apply_disamar_midpoint_bias: bool,
) -> f64 {
    let wavelength_nm = interval_start_nm + interval_width_nm * node_01;
    if !apply_disamar_midpoint_bias
        || response.integration_mode != IntegrationMode::DisamarHrGrid
        || order.is_multiple_of(2)
        || gauss_index != order / 2
        || node_01 != 0.5
    {
        return wavelength_nm;
    }
    next_down(wavelength_nm)
}

fn disamar_interval_division_count(
    adaptive: AdaptiveReferenceGrid,
    response: &SpectralResponse,
) -> usize {
    if adaptive.points_per_fwhm > 0 {
        return usize::from(adaptive.points_per_fwhm);
    }
    if response.high_resolution_step_nm > 0.0 && response.fwhm_nm > 0.0 {
        return ((response.fwhm_nm / response.high_resolution_step_nm).round() as usize).max(1);
    }
    1
}

fn build_disamar_interval_plan(
    global_start_nm: f64,
    global_end_nm: f64,
    interval_width_nm: f64,
    division_count: usize,
) -> Option<Vec<AdaptiveIntervalDescriptor>> {
    if global_end_nm <= global_start_nm || interval_width_nm <= 0.0 || division_count == 0 {
        return None;
    }
    let mut plan = Vec::new();
    let mut current_nm = global_start_nm;
    while current_nm < global_end_nm - 1.0e-12 && plan.len() < MAX_INTEGRATION_SAMPLE_COUNT {
        let next_nm = (current_nm + interval_width_nm).min(global_end_nm);
        plan.push(AdaptiveIntervalDescriptor {
            interval_start_nm: current_nm,
            interval_end_nm: next_nm,
            division_count,
        });
        current_nm = next_nm;
    }
    (current_nm >= global_end_nm - 1.0e-12 && !plan.is_empty()).then_some(plan)
}

fn append_finite_sample(
    samples: &mut Vec<(f64, f64)>,
    wavelength_nm: f64,
    raw_weight: f64,
) -> Option<()> {
    if !wavelength_nm.is_finite() || !raw_weight.is_finite() || raw_weight < 0.0 {
        return Some(());
    }
    if samples.len() >= MAX_INTEGRATION_SAMPLE_COUNT {
        return None;
    }
    samples.push((wavelength_nm, raw_weight));
    Some(())
}

fn select_vendor_support_range(
    sample_wavelengths_nm: &[f64],
    nominal_wavelength_nm: f64,
    support_half_span_nm: f64,
) -> AdaptiveSupportRange {
    debug_assert!(!sample_wavelengths_nm.is_empty());
    let mut closest_index = 0;
    let mut closest_distance_nm = (sample_wavelengths_nm[0] - nominal_wavelength_nm).abs();
    for (index, &wavelength_nm) in sample_wavelengths_nm.iter().enumerate().skip(1) {
        let distance_nm = (wavelength_nm - nominal_wavelength_nm).abs();
        if distance_nm < closest_distance_nm {
            closest_distance_nm = distance_nm;
            closest_index = index;
        }
    }

    let mut start_index = 0;
    let mut left_index = closest_index;
    while left_index > 0 {
        left_index -= 1;
        if (nominal_wavelength_nm - sample_wavelengths_nm[left_index]).abs() > support_half_span_nm
        {
            // DISAMAR keeps one guard sample outside the nominal support span.
            start_index = left_index;
            break;
        }
    }

    let mut end_index = sample_wavelengths_nm.len() - 1;
    let mut right_index = closest_index;
    while right_index + 1 < sample_wavelengths_nm.len() {
        right_index += 1;
        if (sample_wavelengths_nm[right_index] - nominal_wavelength_nm).abs() > support_half_span_nm
        {
            // Keep the symmetric guard sample for edge interpolation parity.
            end_index = right_index;
            break;
        }
    }

    AdaptiveSupportRange {
        start_index,
        end_index,
    }
}

fn next_down(value: f64) -> f64 {
    if value.is_nan() || value == f64::NEG_INFINITY {
        return value;
    }
    if value == 0.0 {
        return f64::from_bits(0x8000_0000_0000_0001);
    }
    let bits = value.to_bits();
    if value > 0.0 {
        f64::from_bits(bits - 1)
    } else {
        f64::from_bits(bits + 1)
    }
}
