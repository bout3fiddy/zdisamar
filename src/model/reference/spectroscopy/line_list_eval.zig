//! Evaluation and trace helpers for spectroscopy line lists.

const std = @import("std");
const LineList = @import("line_list.zig");
const Ops = @import("line_list_ops.zig");
const Physics = @import("physics.zig");
const Support = @import("support.zig");
const Types = @import("types.zig");

const SpectroscopyLineList = LineList.SpectroscopyLineList;

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

pub fn traceAt(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_state: ?*const Types.StrongLinePreparedState,
) !Types.SpectroscopyTrace {
    var rows = std.ArrayList(Types.SpectroscopyTraceRow).empty;
    errdefer rows.deinit(allocator);

    const safe_temperature = @max(temperature_k, 150.0);
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);

    if (!self.hasStrongLineSidecars()) {
        const relevant_window = Ops.relevantLineWindowForWavelength(self, wavelength_nm);
        for (relevant_window.lines, 0..) |line, line_index| {
            const contribution = Physics.weakLineContribution(
                wavelength_nm,
                line,
                safe_temperature,
                pressure_scale,
                Types.hitran_reference_temperature_k,
                self.runtime_controls.cutoff_cm1,
            );
            try rows.append(allocator, Support.traceRowForWeakLine(
                wavelength_nm,
                relevant_window.start_index + line_index,
                line,
                null,
                .weak_included,
                contribution,
                pressure_scale,
            ));
        }
    } else {
        const strong_lines = self.strong_lines.?;
        const relaxation_matrix = self.relaxation_matrix.?;
        const convtp_state = if (prepared_state == null)
            Physics.prepareStrongLineConvTPState(strong_lines, relaxation_matrix, safe_temperature, pressure_scale)
        else
            null;
        const relevant_window = Ops.relevantLineWindowForWavelength(self, wavelength_nm);
        const relevant_lines = relevant_window.lines;
        const strong_line_anchors = Ops.selectStrongLineAnchors(self, relevant_lines, relevant_window.start_index);

        for (relevant_lines, 0..) |line, line_index| {
            const matched_strong_index = Ops.matchedStrongIndexForRelevantLine(
                self,
                relevant_window.start_index,
                line,
                line_index,
            );
            if (Ops.shouldExcludeWeakLine(self, relevant_window.start_index, line, line_index, &strong_line_anchors)) {
                const exclusion_kind: Types.SpectroscopyTraceContributionKind = if (Ops.usesVendorStrongLinePartition(self))
                    .weak_excluded_vendor_partition
                else
                    .weak_excluded_anchor;
                try rows.append(allocator, Support.traceRowForWeakLine(
                    wavelength_nm,
                    relevant_window.start_index + line_index,
                    line,
                    matched_strong_index,
                    exclusion_kind,
                    Support.zeroEvaluation(),
                    pressure_scale,
                ));
                continue;
            }
            const contribution = Physics.weakLineContribution(
                wavelength_nm,
                line,
                safe_temperature,
                pressure_scale,
                Types.hitran_reference_temperature_k,
                self.runtime_controls.cutoff_cm1,
            );
            try rows.append(allocator, Support.traceRowForWeakLine(
                wavelength_nm,
                relevant_window.start_index + line_index,
                line,
                matched_strong_index,
                .weak_included,
                contribution,
                pressure_scale,
            ));
        }

        for (strong_line_anchors[0..strong_lines.len], 0..) |anchor_line_index, strong_index| {
            const line_index = anchor_line_index orelse continue;
            const anchor_line = relevant_lines[line_index];
            const contribution = if (prepared_state) |state|
                Physics.strongLineContributionPrepared(
                    wavelength_nm,
                    anchor_line,
                    strong_lines,
                    strong_index,
                    state,
                    safe_temperature,
                    pressure_scale,
                    self.runtime_controls.cutoff_cm1,
                )
            else
                Physics.strongLineContribution(
                    wavelength_nm,
                    anchor_line,
                    strong_lines,
                    strong_index,
                    convtp_state.?,
                    safe_temperature,
                    pressure_scale,
                    self.runtime_controls.cutoff_cm1,
                );
            try rows.append(allocator, Support.traceRowForStrongLine(
                wavelength_nm,
                relevant_window.start_index + line_index,
                strong_index,
                anchor_line,
                strong_lines[strong_index],
                contribution,
                pressure_scale,
            ));
        }
    }

    return .{
        .wavelength_nm = wavelength_nm,
        .temperature_k = safe_temperature,
        .pressure_hpa = pressure_hpa,
        .evaluation = if (prepared_state) |state|
            self.evaluateAtPrepared(wavelength_nm, safe_temperature, pressure_hpa, state)
        else
            self.evaluateAt(wavelength_nm, safe_temperature, pressure_hpa),
        .rows = try rows.toOwnedSlice(allocator),
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
            self.runtime_controls.cutoff_cm1,
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
            self.runtime_controls.cutoff_cm1,
        );
        weak_line_sigma += contribution.line_sigma_cm2_per_molecule;
    }

    for (strong_line_anchors[0..strong_lines.len], 0..) |anchor_line_index, strong_index| {
        const line_index = anchor_line_index orelse continue;
        const contribution = Physics.strongLineContribution(
            wavelength_nm,
            relevant_lines[line_index],
            strong_lines,
            strong_index,
            convtp_state,
            safe_temperature,
            pressure_scale,
            self.runtime_controls.cutoff_cm1,
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

    const strong_lines = self.strong_lines.?;
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const safe_temperature = @max(temperature_k, 150.0);
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
            self.runtime_controls.cutoff_cm1,
        );
        weak_line_sigma += contribution.line_sigma_cm2_per_molecule;
    }

    for (strong_line_anchors[0..strong_lines.len], 0..) |anchor_line_index, strong_index| {
        const line_index = anchor_line_index orelse continue;
        const contribution = Physics.strongLineContributionPrepared(
            wavelength_nm,
            relevant_lines[line_index],
            strong_lines,
            strong_index,
            prepared_state,
            safe_temperature,
            pressure_scale,
            self.runtime_controls.cutoff_cm1,
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
