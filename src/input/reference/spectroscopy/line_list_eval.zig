// Evaluation helpers for spectroscopy line lists.

const std = @import("std");
const LineList = @import("line_list.zig");
const Ops = @import("line_list_ops.zig");
const Physics = @import("physics.zig");
const Support = @import("support.zig");
const Types = @import("types.zig");

const SpectroscopyLineList = LineList.SpectroscopyLineList;

// layout(64-bit):
//   size: 1048 B, align: 8 B
//   field storage: lines=16 B, start_index=8 B, anchors=1024 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   inline arrays: anchors:[128]usize=1024 B
//   out-of-line: lines carry references/descriptors; referenced storage is not included in size
//   cache span: 17 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 1048 B (1.023 KiB); total also includes referenced storage above
pub const StrongLineWavelengthWindow = struct {
    lines: []const Types.SpectroscopyLine,
    start_index: usize,
    anchors: [Types.max_strong_line_sidecars]usize,
};

// hot path:
//   when: support-row spectroscopy evaluates an active line absorber
//   work: computes base sigma and finite-temperature derivative sigma samples
//   data: line list, wavelength, pressure/temperature state, optional prepared line state
//   follow: totalSigma* variants and prepared strong-line windows
pub fn evaluateAt(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) Types.SpectroscopyEvaluation {
    const total = totalSigmaAt(self, wavelength_nm, temperature_k, pressure_hpa);
    const delta_t = 0.5;
    const upper = totalSigmaAt(self, wavelength_nm, temperature_k + delta_t, pressure_hpa);
    const lower = totalSigmaAt(self, wavelength_nm, @max(temperature_k - delta_t, 150.0), pressure_hpa);
    return .{
        .weak_line_sigma_cm2_per_molecule = total.weak_line_sigma_cm2_per_molecule,
        .strong_line_sigma_cm2_per_molecule = total.strong_line_sigma_cm2_per_molecule,
        .line_sigma_cm2_per_molecule = total.line_sigma_cm2_per_molecule,
        .line_mixing_sigma_cm2_per_molecule = total.line_mixing_sigma_cm2_per_molecule,
        .total_sigma_cm2_per_molecule = total.total_sigma_cm2_per_molecule,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / (2.0 * delta_t),
    };
}

pub fn totalSigmaAt(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) Types.SpectroscopyEvaluation {
    if (self.strong_lines != null and self.relaxation_matrix != null) {
        return totalSigmaWithStrongLineSidecars(self, wavelength_nm, temperature_k, pressure_hpa);
    }
    return totalSigmaFromLineListOnly(self, wavelength_nm, temperature_k, pressure_hpa);
}

// hot path:
//   when: a non-strong line list evaluates sigma for a wavelength/support row
//   work: scans the relevant weak-line window and sums weak-line contributions
//   data: line window, line thermodynamic state, wavelength state, sigma accumulator
//   follow: relevantLineWindowForWavelength and weakLineContributionWithWavelengthState
pub fn totalSigmaFromLineListOnly(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) Types.SpectroscopyEvaluation {
    if (self.lines.len == 0) return Support.zeroEvaluation();

    const safe_temperature = @max(temperature_k, 150.0);
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const relevant_window = Ops.relevantLineWindowForWavelength(self, wavelength_nm);
    var line_sigma: f64 = 0.0;
    for (relevant_window.lines) |line| {
        const contribution = Physics.weakLineContribution(
            wavelength_nm,
            line,
            safe_temperature,
            pressure_scale,
            Types.hitran_reference_temperature_k,
            self.runtime_controls,
        );
        line_sigma += contribution.line_sigma_cm2_per_molecule;
    }
    return .{
        .weak_line_sigma_cm2_per_molecule = line_sigma,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = line_sigma,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

// hot path:
//   when: line-mixing sidecars are enabled for a wavelength/support row
//   work: sums weak-line contributions plus strong-line sidecar contributions
//   data: relevant weak lines, strong-line sidecars, relaxation matrix, anchor matches
//   follow: selectStrongLineAnchors and strongLineContributionPrepared
pub fn totalSigmaWithStrongLineSidecars(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) Types.SpectroscopyEvaluation {
    if (self.lines.len == 0) return Support.zeroEvaluation();

    const strong_lines = self.strong_lines.?;
    const relaxation_matrix = self.relaxation_matrix.?;
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const safe_temperature = @max(temperature_k, 150.0);
    const convtp_state = Physics.prepareStrongLineConvTPState(
        strong_lines,
        relaxation_matrix,
        safe_temperature,
        pressure_scale,
    );
    const relevant_window = Ops.relevantLineWindowForWavelength(self, wavelength_nm);
    const relevant_lines = relevant_window.lines;
    const strong_line_anchors = Ops.selectStrongLineAnchors(self, relevant_lines, relevant_window.start_index);

    var weak_line_sigma: f64 = 0.0;
    var strong_line_sigma: f64 = 0.0;
    var line_mixing_sigma: f64 = 0.0;

    for (relevant_lines, 0..) |line, line_index| {
        if (Ops.shouldExcludeWeakLine(self, relevant_window.start_index, line, line_index, &strong_line_anchors)) continue;
        const contribution = Physics.weakLineContribution(
            wavelength_nm,
            line,
            safe_temperature,
            pressure_scale,
            Types.hitran_reference_temperature_k,
            self.runtime_controls,
        );
        weak_line_sigma += contribution.line_sigma_cm2_per_molecule;
    }

    for (strong_lines, 0..) |_, strong_index| {
        const contribution = Physics.strongLineContribution(
            wavelength_nm,
            strong_lines,
            strong_index,
            &convtp_state,
            safe_temperature,
            pressure_scale,
        );
        strong_line_sigma += contribution.strong_line_sigma_cm2_per_molecule;
        line_mixing_sigma += contribution.line_mixing_sigma_cm2_per_molecule * self.runtime_controls.line_mixing_factor;
    }

    const total_line_sigma = weak_line_sigma + strong_line_sigma;
    return .{
        .weak_line_sigma_cm2_per_molecule = weak_line_sigma,
        .strong_line_sigma_cm2_per_molecule = strong_line_sigma,
        .line_sigma_cm2_per_molecule = total_line_sigma,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = @max(total_line_sigma + line_mixing_sigma, 0.0),
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

pub fn totalSigmaWithPreparedStrongLineState(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_state: *const Types.StrongLinePreparedState,
) Types.SpectroscopyEvaluation {
    if (self.lines.len == 0) return Support.zeroEvaluation();

    const window = prepareStrongLineWavelengthWindow(self, wavelength_nm);
    return totalSigmaWithPreparedStrongLineStateAndWindow(
        self,
        wavelength_nm,
        temperature_k,
        pressure_hpa,
        prepared_state,
        null,
        &window,
    );
}

pub fn prepareStrongLineWavelengthWindow(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
) StrongLineWavelengthWindow {
    const relevant_window = Ops.relevantLineWindowForWavelength(self, wavelength_nm);
    return .{
        .lines = relevant_window.lines,
        .start_index = relevant_window.start_index,
        .anchors = Ops.selectStrongLineAnchors(self, relevant_window.lines, relevant_window.start_index),
    };
}

// hot path:
//   when: prepared spectroscopy state is available for a wavelength/support row
//   work: sums prepared weak-line and prepared strong-line sigma contributions
//   data: prepared weak-line state, prepared strong-line state, relevant window, wavelength state
//   follow: weakLineSigmaPreparedWithStimulatedEmissionScale and strongLineContributionPrepared
pub fn totalSigmaWithPreparedStrongLineStateAndWindow(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_state: *const Types.StrongLinePreparedState,
    prepared_weak_state: ?*const Types.WeakLinePreparedState,
    window: *const StrongLineWavelengthWindow,
) Types.SpectroscopyEvaluation {
    if (self.lines.len == 0) return Support.zeroEvaluation();

    const strong_lines = self.strong_lines.?;
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const safe_temperature = @max(temperature_k, 150.0);

    var weak_line_sigma: f64 = 0.0;
    var strong_line_sigma: f64 = 0.0;
    var line_mixing_sigma: f64 = 0.0;
    const weak_line_wavelength_state = Physics.prepareWeakLineWavelengthState(wavelength_nm, self.runtime_controls);

    const weak_line_state = if (prepared_weak_state) |state|
        if (state.line_count == self.lines.len) state else null
    else
        null;
    const weak_line_states = if (weak_line_state) |state| state.lines else null;
    const weak_line_stimulated_emission_scale = if (weak_line_state) |state|
        Physics.weakLinePreparedStimulatedEmissionScale(weak_line_wavelength_state, state.safe_temperature)
    else
        0.0;
    const weak_line_thermodynamic_scale = if (weak_line_state) |state|
        Physics.weakLinePreparedThermodynamicScale(state.safe_temperature, state.safe_pressure)
    else
        0.0;
    const vendor_weak_exclusions = if (Ops.usesVendorStrongLinePartition(self) and !self.preserve_anchor_weak_lines)
        self.strong_line_match_by_line
    else
        null;

    for (window.lines, 0..) |line, line_index| {
        if (vendor_weak_exclusions) |matches| {
            const global_index = window.start_index + line_index;
            if (global_index < matches.len and matches[global_index] != null) continue;
        } else if (Ops.shouldExcludeWeakLine(self, window.start_index, line, line_index, &window.anchors)) continue;
        if (weak_line_states) |states| {
            weak_line_sigma += Physics.weakLineSigmaPreparedWithStimulatedEmissionScale(
                weak_line_wavelength_state,
                states[window.start_index + line_index],
                self.runtime_controls,
                weak_line_stimulated_emission_scale,
                weak_line_thermodynamic_scale,
            );
        } else {
            const contribution = Physics.weakLineContributionWithWavelengthState(
                wavelength_nm,
                line,
                safe_temperature,
                pressure_scale,
                Types.hitran_reference_temperature_k,
                self.runtime_controls,
                weak_line_wavelength_state,
            );
            weak_line_sigma += contribution.line_sigma_cm2_per_molecule;
        }
    }

    for (strong_lines, 0..) |_, strong_index| {
        const contribution = Physics.strongLineContributionPrepared(
            wavelength_nm,
            strong_lines,
            strong_index,
            prepared_state,
            safe_temperature,
            pressure_scale,
        );
        strong_line_sigma += contribution.strong_line_sigma_cm2_per_molecule;
        line_mixing_sigma += contribution.line_mixing_sigma_cm2_per_molecule * self.runtime_controls.line_mixing_factor;
    }

    const total_line_sigma = weak_line_sigma + strong_line_sigma;
    return .{
        .weak_line_sigma_cm2_per_molecule = weak_line_sigma,
        .strong_line_sigma_cm2_per_molecule = strong_line_sigma,
        .line_sigma_cm2_per_molecule = total_line_sigma,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = @max(total_line_sigma + line_mixing_sigma, 0.0),
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}
