//! Purpose:
//!   Define the typed reference-data carriers and spectroscopy evaluation helpers used by the
//!   engine, runtime loaders, and optics preparation.
//!
//! Physics:
//!   Covers climatology, cross sections, CIA, Rayleigh helpers, airmass/Mie tables, and the
//!   line-by-line spectroscopy structures and evaluation paths used for weak and strong lines.
//!
//! Vendor:
//!   `HITRAN weak-line and LISA strong-line reference-data support`
//!
//! Design:
//!   Keep table carriers small and typed while colocating the non-trivial spectroscopy physics so
//!   adapters and runtime loaders can normalize vendor assets into one reusable evaluation model.
//!
//! Invariants:
//!   Reference-data carriers remain typed and ownership-aware. Spectroscopy line lists may attach
//!   O2 strong-line sidecars only when their matching line/relaxation data are present.
//!
//! Validation:
//!   The unit tests in this file plus bundled-reference, O2A forward-shape, and retrieval
//!   validation tests that exercise typed reference-data loading and evaluation.

const std = @import("std");
const hitran_partition_tables = @import("hitran_partition_tables.zig");
const climatology = @import("reference/climatology.zig");
const cross_section_types = @import("reference/cross_sections.zig");
const cia = @import("reference/cia.zig");
const airmass_phase = @import("reference/airmass_phase.zig");
const rayleigh = @import("reference/rayleigh.zig");
const demo_builders = @import("reference/demo_builders.zig");

const Allocator = std.mem.Allocator;
const max_strong_line_sidecars: usize = 128;
// UNITS:
//   HITRAN constants below are kept in the units used by the vendor tabulations: Kelvin, Joules,
//   `cm^3 * hPa / K`, `cm * K`, `J / (mol * K)`, and `m / s`.
const hitran_reference_temperature_k = 296.0;
const hitran_boltzmann_constant_j_per_k = 1.3806488e-23;
const hitran_boltzmann_constant_cm3_hpa_per_k = 1.380658e-19;
const hitran_hc_over_kb_cm_k = 1.4387770;
const hitran_gas_constant_j_per_mol_k = 8.3144621;
const hitran_speed_of_light_m_per_s = 2.99792458e8;
const min_spectroscopy_pressure_atm = 1.0e-12;

pub const ClimatologyPoint = climatology.ClimatologyPoint;
pub const ClimatologyProfile = climatology.ClimatologyProfile;
pub const CrossSectionPoint = cross_section_types.CrossSectionPoint;
pub const CrossSectionTable = cross_section_types.CrossSectionTable;
pub const CollisionInducedAbsorptionPoint = cia.CollisionInducedAbsorptionPoint;
pub const CollisionInducedAbsorptionTable = cia.CollisionInducedAbsorptionTable;
pub const Rayleigh = rayleigh;

/// Purpose:
///   Represent one weak/nominal spectroscopy line after normalization into wavelength-space
///   fields and typed HITRAN metadata.
pub const SpectroscopyLine = struct {
    gas_index: u16 = 0,
    isotope_number: u8 = 1,
    abundance_fraction: f64 = 1.0,
    center_wavelength_nm: f64,
    line_strength_cm2_per_molecule: f64,
    air_half_width_nm: f64,
    temperature_exponent: f64,
    lower_state_energy_cm1: f64,
    pressure_shift_nm: f64,
    line_mixing_coefficient: f64,
    branch_ic1: ?u8 = null,
    branch_ic2: ?u8 = null,
    rotational_nf: ?u8 = null,
};

/// Purpose:
///   Represent one LISA strong-line sidecar entry retained alongside a nominal line list.
pub const SpectroscopyStrongLine = struct {
    center_wavenumber_cm1: f64,
    center_wavelength_nm: f64,
    population_t0: f64,
    dipole_ratio: f64,
    dipole_t0: f64,
    lower_state_energy_cm1: f64,
    air_half_width_cm1: f64,
    air_half_width_nm: f64,
    temperature_exponent: f64,
    pressure_shift_cm1: f64,
    pressure_shift_nm: f64,
    rotational_index_m1: i32,
};

/// Purpose:
///   Own a set of strong-line sidecars associated with a spectroscopy line list.
pub const SpectroscopyStrongLineSet = struct {
    lines: []SpectroscopyStrongLine,

    /// Purpose:
    ///   Release the owned strong-line array.
    pub fn deinit(self: *SpectroscopyStrongLineSet, allocator: Allocator) void {
        allocator.free(self.lines);
        self.* = undefined;
    }
};

/// Purpose:
///   Store the square relaxation matrix used by the strong-line line-mixing path.
pub const RelaxationMatrix = struct {
    line_count: usize,
    wt0: []f64,
    bw: []f64,

    /// Purpose:
    ///   Release the owned relaxation-matrix storage.
    pub fn deinit(self: *RelaxationMatrix, allocator: Allocator) void {
        allocator.free(self.wt0);
        allocator.free(self.bw);
        self.* = undefined;
    }

    /// Purpose:
    ///   Return one relaxation weight from the flattened square matrix.
    pub fn weightAt(self: RelaxationMatrix, row: usize, col: usize) f64 {
        return self.wt0[row * self.line_count + col];
    }

    /// Purpose:
    ///   Return the temperature-exponent companion entry for one relaxation-matrix element.
    pub fn temperatureExponentAt(self: RelaxationMatrix, row: usize, col: usize) f64 {
        return self.bw[row * self.line_count + col];
    }

    /// Purpose:
    ///   Deep-clone the relaxation matrix into owned storage.
    pub fn clone(self: RelaxationMatrix, allocator: Allocator) !RelaxationMatrix {
        const owned_wt0 = try allocator.dupe(f64, self.wt0);
        errdefer allocator.free(owned_wt0);
        return .{
            .line_count = self.line_count,
            .wt0 = owned_wt0,
            .bw = try allocator.dupe(f64, self.bw),
        };
    }
};

/// Purpose:
///   Report the weak-line, strong-line, and line-mixing contributions for one spectroscopy
///   evaluation.
pub const SpectroscopyEvaluation = struct {
    weak_line_sigma_cm2_per_molecule: f64 = 0.0,
    strong_line_sigma_cm2_per_molecule: f64 = 0.0,
    line_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
    d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
};

pub const SpectroscopyTraceContributionKind = enum {
    weak_included,
    weak_excluded_anchor,
    weak_excluded_vendor_partition,
    strong_sidecar,
};

pub const SpectroscopyTraceRow = struct {
    contribution_kind: SpectroscopyTraceContributionKind,
    wavelength_nm: f64,
    global_line_index: ?usize = null,
    strong_index: ?usize = null,
    matched_strong_index: ?usize = null,
    gas_index: u16 = 0,
    isotope_number: u8 = 0,
    center_wavelength_nm: f64,
    center_wavenumber_cm1: f64,
    shifted_center_wavenumber_cm1: f64,
    line_strength_cm2_per_molecule: f64 = 0.0,
    air_half_width_nm: f64 = 0.0,
    lower_state_energy_cm1: f64 = 0.0,
    pressure_shift_nm: f64 = 0.0,
    line_mixing_coefficient: f64 = 0.0,
    branch_ic1: ?u8 = null,
    branch_ic2: ?u8 = null,
    rotational_nf: ?u8 = null,
    weak_line_sigma_cm2_per_molecule: f64 = 0.0,
    strong_line_sigma_cm2_per_molecule: f64 = 0.0,
    line_mixing_sigma_cm2_per_molecule: f64 = 0.0,
    total_sigma_cm2_per_molecule: f64 = 0.0,
};

pub const SpectroscopyTrace = struct {
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    evaluation: SpectroscopyEvaluation,
    rows: []SpectroscopyTraceRow,

    pub fn deinit(self: *SpectroscopyTrace, allocator: Allocator) void {
        allocator.free(self.rows);
        self.* = undefined;
    }
};

/// Purpose:
///   Describe runtime filtering and line-mixing controls applied to a spectroscopy line list.
pub const SpectroscopyRuntimeControls = struct {
    gas_index: ?u16 = null,
    active_isotopes: []const u8 = &.{},
    threshold_line_scale: ?f64 = null,
    cutoff_cm1: ?f64 = null,
    line_mixing_factor: f64 = 1.0,

    /// Purpose:
    ///   Deep-clone the runtime control payload, including isotope selections.
    pub fn clone(self: SpectroscopyRuntimeControls, allocator: Allocator) !SpectroscopyRuntimeControls {
        return .{
            .gas_index = self.gas_index,
            .active_isotopes = if (self.active_isotopes.len != 0) try allocator.dupe(u8, self.active_isotopes) else &.{},
            .threshold_line_scale = self.threshold_line_scale,
            .cutoff_cm1 = self.cutoff_cm1,
            .line_mixing_factor = self.line_mixing_factor,
        };
    }

    /// Purpose:
    ///   Release any owned isotope-selection storage.
    pub fn deinitOwned(self: *SpectroscopyRuntimeControls, allocator: Allocator) void {
        if (self.active_isotopes.len != 0) allocator.free(self.active_isotopes);
        self.* = .{};
    }

    /// Purpose:
    ///   Convert a threshold scale into an absolute weak-line strength cutoff.
    pub fn thresholdStrength(self: SpectroscopyRuntimeControls, lines: []const SpectroscopyLine) ?f64 {
        const scale = self.threshold_line_scale orelse return null;
        if (lines.len == 0) return null;

        var max_strength: f64 = 0.0;
        for (lines) |line| {
            max_strength = @max(max_strength, line.line_strength_cm2_per_molecule);
        }
        return max_strength * scale;
    }
};

/// Purpose:
///   Store a prepared strong-line state that can be reused across repeated wavelength
///   evaluations at one thermodynamic state.
pub const StrongLinePreparedState = struct {
    line_count: usize,
    sig_moy_cm1: f64,
    population_t: []f64,
    dipole_t: []f64,
    mod_sig_cm1: []f64,
    half_width_cm1_at_t: []f64,
    line_mixing_coefficients: []f64,
    relaxation_weights: []f64,

    /// Purpose:
    ///   Release the owned prepared strong-line arrays.
    pub fn deinit(self: *StrongLinePreparedState, allocator: Allocator) void {
        allocator.free(self.population_t);
        allocator.free(self.dipole_t);
        allocator.free(self.mod_sig_cm1);
        allocator.free(self.half_width_cm1_at_t);
        allocator.free(self.line_mixing_coefficients);
        allocator.free(self.relaxation_weights);
        self.* = undefined;
    }

    fn weightAt(self: StrongLinePreparedState, row: usize, col: usize) f64 {
        return self.relaxation_weights[row * self.line_count + col];
    }
};

/// Purpose:
///   Own a spectroscopy line list plus optional strong-line sidecars and runtime controls.
pub const SpectroscopyLineList = struct {
    lines: []SpectroscopyLine,
    strong_lines: ?[]SpectroscopyStrongLine = null,
    relaxation_matrix: ?RelaxationMatrix = null,
    strong_line_tolerance_nm: f64 = 0.01,
    lines_sorted_ascending: bool = false,
    preserve_anchor_weak_lines: bool = false,
    strong_line_match_by_line: ?[]?u16 = null,
    runtime_controls: SpectroscopyRuntimeControls = .{},

    /// Purpose:
    ///   Release the owned line list, optional sidecars, and runtime controls.
    pub fn deinit(self: *SpectroscopyLineList, allocator: Allocator) void {
        allocator.free(self.lines);
        if (self.strong_lines) |strong_lines| allocator.free(strong_lines);
        if (self.relaxation_matrix) |*relaxation_matrix| relaxation_matrix.deinit(allocator);
        if (self.strong_line_match_by_line) |matches| allocator.free(matches);
        self.runtime_controls.deinitOwned(allocator);
        self.* = undefined;
    }

    /// Purpose:
    ///   Deep-clone the line list, optional strong-line sidecars, and runtime controls.
    pub fn clone(self: SpectroscopyLineList, allocator: Allocator) !SpectroscopyLineList {
        const owned_lines = try allocator.dupe(SpectroscopyLine, self.lines);
        errdefer allocator.free(owned_lines);

        const owned_strong_lines = if (self.strong_lines) |strong_lines|
            try allocator.dupe(SpectroscopyStrongLine, strong_lines)
        else
            null;
        errdefer if (owned_strong_lines) |strong_lines| allocator.free(strong_lines);

        const owned_relaxation_matrix = if (self.relaxation_matrix) |relaxation_matrix|
            try relaxation_matrix.clone(allocator)
        else
            null;
        errdefer if (owned_relaxation_matrix) |relaxation_matrix| {
            var owned = relaxation_matrix;
            owned.deinit(allocator);
        };

        return .{
            .lines = owned_lines,
            .strong_lines = owned_strong_lines,
            .relaxation_matrix = owned_relaxation_matrix,
            .strong_line_tolerance_nm = self.strong_line_tolerance_nm,
            .lines_sorted_ascending = self.lines_sorted_ascending,
            .preserve_anchor_weak_lines = self.preserve_anchor_weak_lines,
            .strong_line_match_by_line = if (self.strong_line_match_by_line) |matches|
                try allocator.dupe(?u16, matches)
            else
                null,
            .runtime_controls = try self.runtime_controls.clone(allocator),
        };
    }

    /// Purpose:
    ///   Attach strong-line and relaxation sidecars to the nominal line list.
    ///
    /// Vendor:
    ///   `LISA strong-line sidecar attachment`
    pub fn attachStrongLineSidecars(
        self: *SpectroscopyLineList,
        allocator: Allocator,
        strong_lines: SpectroscopyStrongLineSet,
        relaxation_matrix: RelaxationMatrix,
    ) !void {
        if (self.strong_lines) |owned_strong_lines| allocator.free(owned_strong_lines);
        if (self.relaxation_matrix) |*owned_relaxation_matrix| owned_relaxation_matrix.deinit(allocator);
        if (self.strong_line_match_by_line) |matches| allocator.free(matches);
        self.strong_line_match_by_line = null;

        self.strong_lines = try allocator.dupe(SpectroscopyStrongLine, strong_lines.lines);
        errdefer {
            if (self.strong_lines) |owned_strong_lines| allocator.free(owned_strong_lines);
            self.strong_lines = null;
        }
        self.relaxation_matrix = try relaxation_matrix.clone(allocator);
        try self.validateStrongLinePartition();
    }

    /// Purpose:
    ///   Build the per-line strong-line match cache used by the strong-line evaluation path.
    pub fn buildStrongLineMatchIndex(self: *SpectroscopyLineList, allocator: Allocator) !void {
        if (self.strong_line_match_by_line) |matches| {
            allocator.free(matches);
            self.strong_line_match_by_line = null;
        }
        if (!self.hasStrongLineSidecars() or self.lines.len == 0) return;
        try self.validateStrongLinePartition();

        const matches = try allocator.alloc(?u16, self.lines.len);
        errdefer allocator.free(matches);
        for (self.lines, 0..) |line, line_index| {
            if (self.usesVendorStrongLinePartition() and !isVendorO2AStrongCandidate(line)) {
                matches[line_index] = null;
                continue;
            }
            matches[line_index] = if (self.findStrongLineMatch(line.center_wavelength_nm)) |strong_index|
                @intCast(strong_index)
            else
                null;
        }
        self.strong_line_match_by_line = matches;
    }

    /// Purpose:
    ///   Evaluate total absorption cross section at one wavelength/temperature/pressure state.
    pub fn sigmaAt(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) f64 {
        return self.totalSigmaAt(wavelength_nm, temperature_k, pressure_hpa).total_sigma_cm2_per_molecule;
    }

    /// Purpose:
    ///   Apply runtime gas/isotope filtering and line-mixing controls to the line list.
    ///
    /// Decisions:
    ///   Filtering mutates the owned line list in place so downstream optics preparation and
    ///   transport see only the active spectral content for the chosen runtime stage.
    pub fn applyRuntimeControls(
        self: *SpectroscopyLineList,
        allocator: Allocator,
        gas_index: ?u16,
        active_isotopes: []const u8,
        threshold_line_scale: ?f64,
        cutoff_cm1: ?f64,
        line_mixing_factor: f64,
    ) !void {
        const replacement_active_isotopes = if (active_isotopes.len != 0)
            try allocator.dupe(u8, active_isotopes)
        else
            &.{};
        if (self.runtime_controls.active_isotopes.len != 0) allocator.free(self.runtime_controls.active_isotopes);
        self.runtime_controls = .{
            .gas_index = gas_index,
            .active_isotopes = replacement_active_isotopes,
            .threshold_line_scale = threshold_line_scale,
            .cutoff_cm1 = cutoff_cm1,
            .line_mixing_factor = line_mixing_factor,
        };

        if (gas_index != null or active_isotopes.len != 0) {
            var retained_count: usize = 0;
            for (self.lines) |line| {
                if (runtimeControlsMatchLine(gas_index, active_isotopes, line)) retained_count += 1;
            }
            if (retained_count != self.lines.len) {
                const retained = try allocator.alloc(SpectroscopyLine, retained_count);
                errdefer allocator.free(retained);
                var write_index: usize = 0;
                for (self.lines) |line| {
                    if (!runtimeControlsMatchLine(gas_index, active_isotopes, line)) continue;
                    retained[write_index] = line;
                    write_index += 1;
                }
                allocator.free(self.lines);
                self.lines = retained;
                self.lines_sorted_ascending = false;
            }
        }

        if (self.strong_line_match_by_line) |matches| {
            allocator.free(matches);
            self.strong_line_match_by_line = null;
        }
        if (self.strong_lines != null and !runtimeControlsKeepStrongLineSidecars(gas_index, active_isotopes)) {
            // GOTCHA:
            //   The bundled strong-line sidecars are only valid for O2 main-isotope selections.
            //   Filtering to a different gas or isotope disables the sidecars entirely.
            self.disableStrongLineSidecars(allocator);
            return;
        }
        try self.validateStrongLinePartition();
    }

    /// Purpose:
    ///   Evaluate the total sigma using a precomputed strong-line thermodynamic state when
    ///   available.
    pub fn sigmaAtPrepared(
        self: SpectroscopyLineList,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_state: ?*const StrongLinePreparedState,
    ) f64 {
        if (prepared_state) |state| {
            return self.totalSigmaWithPreparedStrongLineState(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
                state,
            ).total_sigma_cm2_per_molecule;
        }
        return self.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
    }

    /// Purpose:
    ///   Evaluate the full weak/strong/mixing decomposition using a prepared strong-line state
    ///   when available.
    pub fn evaluateAtPrepared(
        self: SpectroscopyLineList,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_state: ?*const StrongLinePreparedState,
    ) SpectroscopyEvaluation {
        if (prepared_state) |state| {
            return self.totalSigmaWithPreparedStrongLineState(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
                state,
            );
        }
        return self.evaluateAt(wavelength_nm, temperature_k, pressure_hpa);
    }

    /// Purpose:
    ///   Report whether both strong-line and relaxation sidecars are present.
    pub fn hasStrongLineSidecars(self: SpectroscopyLineList) bool {
        return self.strong_lines != null and self.relaxation_matrix != null;
    }

    /// Purpose:
    ///   Prepare the strong-line thermodynamic state for one temperature/pressure point.
    pub fn prepareStrongLineState(
        self: SpectroscopyLineList,
        allocator: Allocator,
        temperature_k: f64,
        pressure_hpa: f64,
    ) !?StrongLinePreparedState {
        if (!self.hasStrongLineSidecars()) return null;
        const pressure_scale = @max(pressure_hpa / 1013.25, min_spectroscopy_pressure_atm);
        const stack_state = prepareStrongLineConvTPState(
            self.strong_lines.?,
            self.relaxation_matrix.?,
            @max(temperature_k, 150.0),
            pressure_scale,
        );
        return try clonePreparedStrongLineState(allocator, stack_state);
    }

    /// Purpose:
    ///   Evaluate the full spectroscopy decomposition and a finite-difference temperature
    ///   derivative at one wavelength.
    pub fn evaluateAt(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) SpectroscopyEvaluation {
        const total = self.totalSigmaAt(wavelength_nm, temperature_k, pressure_hpa);
        const delta_t = 0.5;
        const upper = self.totalSigmaAt(wavelength_nm, temperature_k + delta_t, pressure_hpa);
        const lower = self.totalSigmaAt(wavelength_nm, @max(temperature_k - delta_t, 150.0), pressure_hpa);
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
        allocator: Allocator,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_state: ?*const StrongLinePreparedState,
    ) !SpectroscopyTrace {
        var rows = std.ArrayList(SpectroscopyTraceRow).empty;
        errdefer rows.deinit(allocator);

        const safe_temperature = @max(temperature_k, 150.0);
        const pressure_scale = @max(pressure_hpa / 1013.25, min_spectroscopy_pressure_atm);

        if (!self.hasStrongLineSidecars()) {
            const relevant_window = self.relevantLineWindowForWavelength(wavelength_nm);
            for (relevant_window.lines, 0..) |line, line_index| {
                const contribution = weakLineContribution(
                    wavelength_nm,
                    line,
                    safe_temperature,
                    pressure_scale,
                    hitran_reference_temperature_k,
                    self.runtime_controls.cutoff_cm1,
                );
                try rows.append(allocator, traceRowForWeakLine(
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
                prepareStrongLineConvTPState(strong_lines, relaxation_matrix, safe_temperature, pressure_scale)
            else
                null;
            const relevant_window = self.relevantLineWindowForWavelength(wavelength_nm);
            const relevant_lines = relevant_window.lines;
            const strong_line_anchors = self.selectStrongLineAnchors(relevant_lines, relevant_window.start_index);

            for (relevant_lines, 0..) |line, line_index| {
                const matched_strong_index = self.matchedStrongIndexForRelevantLine(
                    relevant_window.start_index,
                    line,
                    line_index,
                );
                if (self.shouldExcludeWeakLine(relevant_window.start_index, line, line_index, &strong_line_anchors)) {
                    const exclusion_kind: SpectroscopyTraceContributionKind = if (self.usesVendorStrongLinePartition())
                        .weak_excluded_vendor_partition
                    else
                        .weak_excluded_anchor;
                    try rows.append(allocator, traceRowForWeakLine(
                        wavelength_nm,
                        relevant_window.start_index + line_index,
                        line,
                        matched_strong_index,
                        exclusion_kind,
                        zeroEvaluation(),
                        pressure_scale,
                    ));
                    continue;
                }
                const contribution = weakLineContribution(
                    wavelength_nm,
                    line,
                    safe_temperature,
                    pressure_scale,
                    hitran_reference_temperature_k,
                    self.runtime_controls.cutoff_cm1,
                );
                try rows.append(allocator, traceRowForWeakLine(
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
                    strongLineContributionPrepared(
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
                    strongLineContribution(
                        wavelength_nm,
                        anchor_line,
                        strong_lines,
                        strong_index,
                        convtp_state.?,
                        safe_temperature,
                        pressure_scale,
                        self.runtime_controls.cutoff_cm1,
                    );
                try rows.append(allocator, traceRowForStrongLine(
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

    fn totalSigmaAt(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) SpectroscopyEvaluation {
        if (self.strong_lines != null and self.relaxation_matrix != null) {
            return self.totalSigmaWithStrongLineSidecars(wavelength_nm, temperature_k, pressure_hpa);
        }
        return self.totalSigmaFromLineListOnly(wavelength_nm, temperature_k, pressure_hpa);
    }

    fn totalSigmaFromLineListOnly(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) SpectroscopyEvaluation {
        if (self.lines.len == 0) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }

        const reference_temperature_k = hitran_reference_temperature_k;
        const safe_temperature = @max(temperature_k, 150.0);
        const pressure_scale = @max(pressure_hpa / 1013.25, min_spectroscopy_pressure_atm);

        const relevant_window = self.relevantLineWindowForWavelength(wavelength_nm);
        var line_sigma: f64 = 0.0;
        for (relevant_window.lines) |line| {
            const contribution = weakLineContribution(
                wavelength_nm,
                line,
                safe_temperature,
                pressure_scale,
                reference_temperature_k,
                self.runtime_controls.cutoff_cm1,
            );
            line_sigma += contribution.line_sigma_cm2_per_molecule;
        }
        const line_mixing_sigma: f64 = 0.0;
        const total_sigma = line_sigma;
        return .{
            .weak_line_sigma_cm2_per_molecule = line_sigma,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = line_sigma,
            .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
            .total_sigma_cm2_per_molecule = total_sigma,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
    }

    fn totalSigmaWithStrongLineSidecars(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) SpectroscopyEvaluation {
        if (self.lines.len == 0) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }

        const strong_lines = self.strong_lines.?;
        const relaxation_matrix = self.relaxation_matrix.?;
        const pressure_scale = @max(pressure_hpa / 1013.25, min_spectroscopy_pressure_atm);
        const safe_temperature = @max(temperature_k, 150.0);
        const convtp_state = prepareStrongLineConvTPState(
            strong_lines,
            relaxation_matrix,
            safe_temperature,
            pressure_scale,
        );
        const relevant_window = self.relevantLineWindowForWavelength(wavelength_nm);
        const relevant_lines = relevant_window.lines;
        const strong_line_anchors = self.selectStrongLineAnchors(relevant_lines, relevant_window.start_index);

        var weak_line_sigma: f64 = 0.0;
        var strong_line_sigma: f64 = 0.0;
        var line_mixing_sigma: f64 = 0.0;

        for (relevant_lines, 0..) |line, line_index| {
            if (self.shouldExcludeWeakLine(relevant_window.start_index, line, line_index, &strong_line_anchors)) continue;
            const contribution = weakLineContribution(
                wavelength_nm,
                line,
                safe_temperature,
                pressure_scale,
                hitran_reference_temperature_k,
                self.runtime_controls.cutoff_cm1,
            );
            weak_line_sigma += contribution.line_sigma_cm2_per_molecule;
        }

        for (strong_line_anchors[0..strong_lines.len], 0..) |anchor_line_index, strong_index| {
            const line_index = anchor_line_index orelse continue;
            const contribution = strongLineContribution(
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

    fn totalSigmaWithPreparedStrongLineState(
        self: SpectroscopyLineList,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_state: *const StrongLinePreparedState,
    ) SpectroscopyEvaluation {
        if (self.lines.len == 0) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }

        const strong_lines = self.strong_lines.?;
        const pressure_scale = @max(pressure_hpa / 1013.25, min_spectroscopy_pressure_atm);
        const safe_temperature = @max(temperature_k, 150.0);
        const relevant_window = self.relevantLineWindowForWavelength(wavelength_nm);
        const relevant_lines = relevant_window.lines;
        const strong_line_anchors = self.selectStrongLineAnchors(relevant_lines, relevant_window.start_index);

        var weak_line_sigma: f64 = 0.0;
        var strong_line_sigma: f64 = 0.0;
        var line_mixing_sigma: f64 = 0.0;

        for (relevant_lines, 0..) |line, line_index| {
            if (self.shouldExcludeWeakLine(relevant_window.start_index, line, line_index, &strong_line_anchors)) continue;
            const contribution = weakLineContribution(
                wavelength_nm,
                line,
                safe_temperature,
                pressure_scale,
                hitran_reference_temperature_k,
                self.runtime_controls.cutoff_cm1,
            );
            weak_line_sigma += contribution.line_sigma_cm2_per_molecule;
        }

        for (strong_line_anchors[0..strong_lines.len], 0..) |anchor_line_index, strong_index| {
            const line_index = anchor_line_index orelse continue;
            const contribution = strongLineContributionPrepared(
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

    fn findStrongLineMatch(self: SpectroscopyLineList, wavelength_nm: f64) ?usize {
        const strong_lines = self.strong_lines orelse return null;

        var best_index: ?usize = null;
        var best_delta = std.math.inf(f64);
        for (strong_lines, 0..) |strong_line, index| {
            const delta = @abs(strong_line.center_wavelength_nm - wavelength_nm);
            const tolerance_nm = @max(self.strong_line_tolerance_nm, strong_line.air_half_width_nm * 4.0);
            if (delta > tolerance_nm or delta >= best_delta) continue;
            best_index = index;
            best_delta = delta;
        }
        return best_index;
    }

    const RelevantLineWindow = struct {
        lines: []const SpectroscopyLine,
        start_index: usize,
    };

    fn relevantLineWindowForWavelength(self: SpectroscopyLineList, wavelength_nm: f64) RelevantLineWindow {
        if (!self.lines_sorted_ascending) {
            return .{
                .lines = self.lines,
                .start_index = 0,
            };
        }
        const cutoff_cm1 = self.runtime_controls.cutoff_cm1 orelse {
            return .{
                .lines = self.lines,
                .start_index = 0,
            };
        };
        const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
        const minimum_wavenumber_cm1 = @max(evaluation_wavenumber_cm1 - cutoff_cm1, 1.0e-6);
        const maximum_wavenumber_cm1 = evaluation_wavenumber_cm1 + cutoff_cm1;
        const minimum_wavelength_nm = wavenumberCm1ToWavelengthNm(maximum_wavenumber_cm1);
        const maximum_wavelength_nm = wavenumberCm1ToWavelengthNm(minimum_wavenumber_cm1);
        const lower = lowerBoundLineIndex(self.lines, minimum_wavelength_nm);
        const upper = upperBoundLineIndex(self.lines, maximum_wavelength_nm);
        return .{
            .lines = self.lines[lower..upper],
            .start_index = lower,
        };
    }

    fn selectStrongLineAnchors(
        self: SpectroscopyLineList,
        relevant_lines: []const SpectroscopyLine,
        start_index: usize,
    ) [max_strong_line_sidecars]?usize {
        var anchors = [_]?usize{null} ** max_strong_line_sidecars;
        var deltas = [_]f64{std.math.inf(f64)} ** max_strong_line_sidecars;
        const strong_lines = self.strong_lines orelse return anchors;

        for (relevant_lines, 0..) |line, line_index| {
            const strong_index = self.matchedStrongIndexForRelevantLine(start_index, line, line_index) orelse continue;
            const delta = @abs(strong_lines[strong_index].center_wavelength_nm - line.center_wavelength_nm);
            if (delta > deltas[strong_index]) continue;
            if (delta == deltas[strong_index] and anchors[strong_index] != null) {
                const incumbent = relevant_lines[anchors[strong_index].?];
                if (incumbent.line_strength_cm2_per_molecule >= line.line_strength_cm2_per_molecule) continue;
            }
            anchors[strong_index] = line_index;
            deltas[strong_index] = delta;
        }
        return anchors;
    }

    fn matchedStrongIndexForRelevantLine(
        self: SpectroscopyLineList,
        start_index: usize,
        line: SpectroscopyLine,
        line_index: usize,
    ) ?usize {
        if (self.strong_line_match_by_line) |matches| {
            const global_index = start_index + line_index;
            if (global_index < matches.len) {
                if (matches[global_index]) |strong_index| return @as(usize, strong_index);
                return null;
            }
        }
        if (self.usesVendorStrongLinePartition()) {
            if (!isVendorO2AStrongCandidate(line)) return null;
            return self.findStrongLineMatch(line.center_wavelength_nm);
        }
        return self.findStrongLineMatch(line.center_wavelength_nm);
    }

    fn shouldExcludeWeakLine(
        self: SpectroscopyLineList,
        start_index: usize,
        line: SpectroscopyLine,
        line_index: usize,
        strong_line_anchors: *const [max_strong_line_sidecars]?usize,
    ) bool {
        const strong_index = self.matchedStrongIndexForRelevantLine(start_index, line, line_index) orelse return false;
        if (self.usesVendorStrongLinePartition()) return true;
        if (self.preserve_anchor_weak_lines) return false;
        if (strong_line_anchors[strong_index]) |anchor_line_index| {
            return anchor_line_index == line_index;
        }
        return false;
    }

    fn validateStrongLinePartition(self: SpectroscopyLineList) !void {
        if (!self.usesVendorStrongLinePartition()) return;

        const strong_lines = self.strong_lines orelse return;
        if (strong_lines.len > max_strong_line_sidecars) return error.TooManyStrongLineSidecars;

        var matched_counts = [_]usize{0} ** max_strong_line_sidecars;
        for (self.lines) |line| {
            if (line.gas_index == 7 and self.findStrongLineMatch(line.center_wavelength_nm) != null and !lineHasVendorStrongLineMetadata(line)) {
                return error.MissingStrongLineMetadata;
            }
            if (!isVendorO2AStrongCandidate(line)) continue;
            const strong_index = self.findStrongLineMatch(line.center_wavelength_nm) orelse {
                return error.UnmatchedStrongLineCandidate;
            };
            matched_counts[strong_index] += 1;
        }

        for (strong_lines, 0..) |_, strong_index| {
            if (matched_counts[strong_index] == 0) return error.UnmatchedStrongLineSidecar;
        }
    }

    fn usesVendorStrongLinePartition(self: SpectroscopyLineList) bool {
        if (!self.hasStrongLineSidecars()) return false;
        if (self.runtime_controls.gas_index) |gas_index| {
            if (gas_index != 7) return false;
        }
        for (self.lines) |line| {
            if (line.gas_index != 7) continue;
            if (lineHasVendorStrongLineMetadata(line)) return true;
        }
        return false;
    }

    fn disableStrongLineSidecars(self: *SpectroscopyLineList, allocator: Allocator) void {
        if (self.strong_lines) |strong_lines| allocator.free(strong_lines);
        self.strong_lines = null;
        if (self.relaxation_matrix) |*relaxation_matrix| relaxation_matrix.deinit(allocator);
        self.relaxation_matrix = null;
        if (self.strong_line_match_by_line) |matches| allocator.free(matches);
        self.strong_line_match_by_line = null;
    }
};

fn lineIndexIsStrongAnchor(anchor_indices: []const ?usize, line_index: usize) bool {
    for (anchor_indices) |anchor| {
        if (anchor == null) continue;
        if (anchor.? == line_index) return true;
    }
    return false;
}

fn zeroEvaluation() SpectroscopyEvaluation {
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

fn traceRowForWeakLine(
    wavelength_nm: f64,
    global_line_index: usize,
    line: SpectroscopyLine,
    matched_strong_index: ?usize,
    contribution_kind: SpectroscopyTraceContributionKind,
    contribution: SpectroscopyEvaluation,
    pressure_atm: f64,
) SpectroscopyTraceRow {
    return .{
        .contribution_kind = contribution_kind,
        .wavelength_nm = wavelength_nm,
        .global_line_index = global_line_index,
        .strong_index = null,
        .matched_strong_index = matched_strong_index,
        .gas_index = line.gas_index,
        .isotope_number = line.isotope_number,
        .center_wavelength_nm = line.center_wavelength_nm,
        .center_wavenumber_cm1 = wavelengthToWavenumberCm1(line.center_wavelength_nm),
        .shifted_center_wavenumber_cm1 = shiftedLineCenterWavenumberCm1(line, pressure_atm),
        .line_strength_cm2_per_molecule = line.line_strength_cm2_per_molecule,
        .air_half_width_nm = line.air_half_width_nm,
        .lower_state_energy_cm1 = line.lower_state_energy_cm1,
        .pressure_shift_nm = line.pressure_shift_nm,
        .line_mixing_coefficient = line.line_mixing_coefficient,
        .branch_ic1 = line.branch_ic1,
        .branch_ic2 = line.branch_ic2,
        .rotational_nf = line.rotational_nf,
        .weak_line_sigma_cm2_per_molecule = contribution.weak_line_sigma_cm2_per_molecule,
        .strong_line_sigma_cm2_per_molecule = contribution.strong_line_sigma_cm2_per_molecule,
        .line_mixing_sigma_cm2_per_molecule = contribution.line_mixing_sigma_cm2_per_molecule,
        .total_sigma_cm2_per_molecule = contribution.total_sigma_cm2_per_molecule,
    };
}

fn traceRowForStrongLine(
    wavelength_nm: f64,
    global_line_index: usize,
    strong_index: usize,
    anchor_line: SpectroscopyLine,
    strong_line: SpectroscopyStrongLine,
    contribution: SpectroscopyEvaluation,
    pressure_atm: f64,
) SpectroscopyTraceRow {
    return .{
        .contribution_kind = .strong_sidecar,
        .wavelength_nm = wavelength_nm,
        .global_line_index = global_line_index,
        .strong_index = strong_index,
        .matched_strong_index = strong_index,
        .gas_index = anchor_line.gas_index,
        .isotope_number = anchor_line.isotope_number,
        .center_wavelength_nm = strong_line.center_wavelength_nm,
        .center_wavenumber_cm1 = strong_line.center_wavenumber_cm1,
        .shifted_center_wavenumber_cm1 = strong_line.center_wavenumber_cm1 + pressure_atm * strong_line.pressure_shift_cm1,
        .line_strength_cm2_per_molecule = anchor_line.line_strength_cm2_per_molecule,
        .air_half_width_nm = strong_line.air_half_width_nm,
        .lower_state_energy_cm1 = strong_line.lower_state_energy_cm1,
        .pressure_shift_nm = anchor_line.pressure_shift_nm,
        .line_mixing_coefficient = anchor_line.line_mixing_coefficient,
        .branch_ic1 = anchor_line.branch_ic1,
        .branch_ic2 = anchor_line.branch_ic2,
        .rotational_nf = anchor_line.rotational_nf,
        .weak_line_sigma_cm2_per_molecule = contribution.weak_line_sigma_cm2_per_molecule,
        .strong_line_sigma_cm2_per_molecule = contribution.strong_line_sigma_cm2_per_molecule,
        .line_mixing_sigma_cm2_per_molecule = contribution.line_mixing_sigma_cm2_per_molecule,
        .total_sigma_cm2_per_molecule = contribution.total_sigma_cm2_per_molecule,
    };
}

fn lineHasVendorStrongLineMetadata(line: SpectroscopyLine) bool {
    return line.branch_ic1 != null and line.branch_ic2 != null and line.rotational_nf != null;
}

fn wavenumberCm1ToWavelengthNm(wavenumber_cm1: f64) f64 {
    return 1.0e7 / @max(wavenumber_cm1, 1.0);
}

fn isVendorO2AStrongCandidate(line: SpectroscopyLine) bool {
    return line.gas_index == 7 and
        line.isotope_number == 1 and
        line.branch_ic1 != null and
        line.branch_ic2 != null and
        line.rotational_nf != null and
        line.branch_ic1.? == 5 and
        line.branch_ic2.? == 1 and
        line.rotational_nf.? <= 35;
}

fn runtimeControlsMatchLine(gas_index: ?u16, active_isotopes: []const u8, line: SpectroscopyLine) bool {
    if (gas_index) |expected_gas_index| {
        if (line.gas_index != expected_gas_index) return false;
    }
    if (active_isotopes.len == 0) return true;
    for (active_isotopes) |isotope_number| {
        if (line.isotope_number == isotope_number) return true;
    }
    return false;
}

fn runtimeControlsKeepStrongLineSidecars(gas_index: ?u16, active_isotopes: []const u8) bool {
    if (gas_index) |expected_gas_index| {
        if (expected_gas_index != 7) return false;
    }
    if (active_isotopes.len == 0) return true;
    for (active_isotopes) |isotope_number| {
        if (isotope_number == 1) return true;
    }
    return false;
}

pub const AirmassFactorPoint = airmass_phase.AirmassFactorPoint;
pub const MiePhasePoint = airmass_phase.MiePhasePoint;
pub const MiePhaseTable = airmass_phase.MiePhaseTable;
pub const AirmassFactorLut = airmass_phase.AirmassFactorLut;

pub const buildDemoClimatology = demo_builders.buildDemoClimatology;
pub const buildDemoCrossSections = demo_builders.buildDemoCrossSections;
pub const buildDemoAirmassFactorLut = demo_builders.buildDemoAirmassFactorLut;

const demo_spectroscopy_lines = [_]SpectroscopyLine{
    .{ .center_wavelength_nm = 429.8, .line_strength_cm2_per_molecule = 8.2e-21, .air_half_width_nm = 0.035, .temperature_exponent = 0.72, .lower_state_energy_cm1 = 112.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.04 },
    .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.041, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 140.0, .pressure_shift_nm = 0.003, .line_mixing_coefficient = 0.07 },
    .{ .center_wavelength_nm = 441.2, .line_strength_cm2_per_molecule = 9.7e-21, .air_half_width_nm = 0.038, .temperature_exponent = 0.74, .lower_state_energy_cm1 = 165.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.05 },
    .{ .center_wavelength_nm = 448.1, .line_strength_cm2_per_molecule = 7.6e-21, .air_half_width_nm = 0.034, .temperature_exponent = 0.77, .lower_state_energy_cm1 = 188.0, .pressure_shift_nm = 0.001, .line_mixing_coefficient = 0.03 },
    .{ .center_wavelength_nm = 456.0, .line_strength_cm2_per_molecule = 5.4e-21, .air_half_width_nm = 0.030, .temperature_exponent = 0.81, .lower_state_energy_cm1 = 205.0, .pressure_shift_nm = 0.001, .line_mixing_coefficient = 0.02 },
};

/// Purpose:
///   Build a tiny deterministic spectroscopy line list used by tests and demos.
pub fn buildDemoSpectroscopyLines(allocator: Allocator) !SpectroscopyLineList {
    return .{
        .lines = try allocator.dupe(SpectroscopyLine, demo_spectroscopy_lines[0..]),
        .lines_sorted_ascending = true,
    };
}

test "reference data helpers interpolate physical tables deterministically" {
    var profile = ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.5e19 },
            .{ .altitude_km = 10.0, .pressure_hpa = 260.0, .temperature_k = 223.0, .air_number_density_cm3 = 6.6e18 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = CrossSectionTable{
        .points = try std.testing.allocator.dupe(CrossSectionPoint, &.{
            .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.21e-19 },
            .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 4.17e-19 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);

    var lut = AirmassFactorLut{
        .points = try std.testing.allocator.dupe(AirmassFactorPoint, &.{
            .{ .solar_zenith_deg = 40.0, .view_zenith_deg = 10.0, .relative_azimuth_deg = 30.0, .airmass_factor = 1.241 },
            .{ .solar_zenith_deg = 60.0, .view_zenith_deg = 20.0, .relative_azimuth_deg = 60.0, .airmass_factor = 1.756 },
        }),
    };
    defer lut.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 1.58e19), profile.interpolateDensity(5.0), 1e16);
    try std.testing.expectApproxEqAbs(@as(f64, 630.0), profile.interpolatePressure(5.0), 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5.19e-19), cross_sections.meanSigmaInRange(405.0, 465.0), 1e-22);
    try std.testing.expectApproxEqAbs(@as(f64, 1.241), lut.nearest(42.0, 11.0, 35.0), 1e-9);
}

test "collision-induced absorption tables preserve pair-absorption units and interpolate coefficients" {
    var table = CollisionInducedAbsorptionTable{
        .scale_factor_cm5_per_molecule2 = 1.0e-46,
        .points = try std.testing.allocator.dupe(CollisionInducedAbsorptionPoint, &.{
            .{ .wavelength_nm = 760.0, .a0 = 4.0, .a1 = 1.0e-2, .a2 = 0.0 },
            .{ .wavelength_nm = 770.0, .a0 = 8.0, .a1 = 2.0e-2, .a2 = 0.0 },
        }),
    };
    defer table.deinit(std.testing.allocator);

    try std.testing.expect(table.sigmaAt(765.0, 293.15) > table.sigmaAt(760.0, 293.15));
    try std.testing.expectApproxEqAbs(@as(f64, 1.5e-48), table.dSigmaDTemperatureAt(765.0, 293.15), 1e-60);
    try std.testing.expect(table.meanSigmaInRange(760.0, 770.0, 293.15) > 0.0);
}

test "spectroscopy line list evaluates bounded temperature and pressure dependent sigma" {
    var lines = try buildDemoSpectroscopyLines(std.testing.allocator);
    defer lines.deinit(std.testing.allocator);

    const near_line = lines.evaluateAt(434.6, 250.0, 750.0);
    const off_line = lines.evaluateAt(420.0, 250.0, 750.0);
    const cold_dense = lines.evaluateAt(434.6, 220.0, 900.0);

    try std.testing.expect(near_line.total_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(near_line.total_sigma_cm2_per_molecule > off_line.total_sigma_cm2_per_molecule);
    try std.testing.expect(cold_dense.total_sigma_cm2_per_molecule != near_line.total_sigma_cm2_per_molecule);
    try std.testing.expect(@abs(near_line.d_sigma_d_temperature_cm2_per_molecule_per_k) > 0.0);
    try std.testing.expectEqual(@as(f64, 0.0), near_line.line_mixing_sigma_cm2_per_molecule);
}

test "weak-line sigma treats abundance fraction as metadata for HITRAN strengths" {
    var reference = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{
                .gas_index = 7,
                .isotope_number = 1,
                .abundance_fraction = 0.995262,
                .center_wavelength_nm = 771.3015,
                .line_strength_cm2_per_molecule = 1.20e-20,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .lower_state_energy_cm1 = 1804.8773,
                .pressure_shift_nm = 0.00053,
                .line_mixing_coefficient = 0.03,
            },
        }),
    };
    defer reference.deinit(std.testing.allocator);

    var metadata_only = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{
                .gas_index = 7,
                .isotope_number = 1,
                .abundance_fraction = 0.0039914,
                .center_wavelength_nm = 771.3015,
                .line_strength_cm2_per_molecule = 1.20e-20,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .lower_state_energy_cm1 = 1804.8773,
                .pressure_shift_nm = 0.00053,
                .line_mixing_coefficient = 0.03,
            },
        }),
    };
    defer metadata_only.deinit(std.testing.allocator);

    const reference_eval = reference.evaluateAt(771.3015, 255.0, 820.0);
    const metadata_only_eval = metadata_only.evaluateAt(771.3015, 255.0, 820.0);

    try std.testing.expect(reference_eval.total_sigma_cm2_per_molecule > 0.0);
    try std.testing.expectApproxEqAbs(
        reference_eval.total_sigma_cm2_per_molecule,
        metadata_only_eval.total_sigma_cm2_per_molecule,
        1.0e-18,
    );
}

test "o2 spectroscopy uses vendor-tabulated partition ratios" {
    const line = SpectroscopyLine{
        .gas_index = 7,
        .isotope_number = 1,
        .abundance_fraction = 0.995262,
        .center_wavelength_nm = 771.3015,
        .line_strength_cm2_per_molecule = 1.20e-20,
        .air_half_width_nm = 0.00164,
        .temperature_exponent = 0.63,
        .lower_state_energy_cm1 = 1804.8773,
        .pressure_shift_nm = 0.00053,
        .line_mixing_coefficient = 0.03,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 1.0), partitionRatioT0OverT(line, 296.0, 296.0), 1e-12);
    try std.testing.expect(partitionRatioT0OverT(line, 260.0, 296.0) > 1.0);
}

test "vendor-covered gas and isotope mappings reach partition tables beyond o2" {
    const representative_lines = [_]SpectroscopyLine{
        .{ .gas_index = 1, .isotope_number = 1, .center_wavelength_nm = 720.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        .{ .gas_index = 2, .isotope_number = 1, .center_wavelength_nm = 760.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        .{ .gas_index = 5, .isotope_number = 1, .center_wavelength_nm = 4800.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        .{ .gas_index = 6, .isotope_number = 1, .center_wavelength_nm = 2300.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        .{ .gas_index = 11, .isotope_number = 1, .center_wavelength_nm = 640.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
    };

    for (representative_lines) |line| {
        try std.testing.expect(partitionRatioT0OverT(line, 260.0, 296.0) > 1.0);
    }
}

test "weak-line evaluation narrows heavier isotopologues through vendor molecular weights" {
    const common = SpectroscopyLine{
        .gas_index = 7,
        .abundance_fraction = 1.0,
        .center_wavelength_nm = 771.3015,
        .line_strength_cm2_per_molecule = 1.20e-20,
        .air_half_width_nm = 0.00164,
        .temperature_exponent = 0.63,
        .lower_state_energy_cm1 = 1804.8773,
        .pressure_shift_nm = 0.00053,
        .line_mixing_coefficient = 0.03,
    };

    const lighter = weakLineContribution(
        common.center_wavelength_nm,
        .{ .isotope_number = 1, .gas_index = common.gas_index, .abundance_fraction = common.abundance_fraction, .center_wavelength_nm = common.center_wavelength_nm, .line_strength_cm2_per_molecule = common.line_strength_cm2_per_molecule, .air_half_width_nm = common.air_half_width_nm, .temperature_exponent = common.temperature_exponent, .lower_state_energy_cm1 = common.lower_state_energy_cm1, .pressure_shift_nm = common.pressure_shift_nm, .line_mixing_coefficient = common.line_mixing_coefficient },
        255.0,
        820.0 / 1013.25,
        hitran_reference_temperature_k,
        null,
    );
    const heavier = weakLineContribution(
        common.center_wavelength_nm,
        .{ .isotope_number = 2, .gas_index = common.gas_index, .abundance_fraction = common.abundance_fraction, .center_wavelength_nm = common.center_wavelength_nm, .line_strength_cm2_per_molecule = common.line_strength_cm2_per_molecule, .air_half_width_nm = common.air_half_width_nm, .temperature_exponent = common.temperature_exponent, .lower_state_energy_cm1 = common.lower_state_energy_cm1, .pressure_shift_nm = common.pressure_shift_nm, .line_mixing_coefficient = common.line_mixing_coefficient },
        255.0,
        820.0 / 1013.25,
        hitran_reference_temperature_k,
        null,
    );

    try std.testing.expect(molecularWeightForLine(.{ .gas_index = 7, .isotope_number = 2, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.001, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 }) > molecularWeightForLine(.{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.001, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 }));
    try std.testing.expect(heavier.total_sigma_cm2_per_molecule > lighter.total_sigma_cm2_per_molecule);
}

test "runtime controls filter gas and isotope selections and disable O2-only sidecars" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.0, .line_strength_cm2_per_molecule = 4.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.05 },
            .{ .gas_index = 7, .isotope_number = 2, .center_wavelength_nm = 760.1, .line_strength_cm2_per_molecule = 3.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.05 },
            .{ .gas_index = 2, .isotope_number = 1, .center_wavelength_nm = 760.2, .line_strength_cm2_per_molecule = 2.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        }),
        .strong_lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = wavelengthToWavenumberCm1(760.0),
                .center_wavelength_nm = 760.0,
                .population_t0 = 1.0,
                .dipole_ratio = 1.0,
                .dipole_t0 = 1.0,
                .lower_state_energy_cm1 = 100.0,
                .air_half_width_cm1 = 0.01,
                .air_half_width_nm = 0.001,
                .temperature_exponent = 0.7,
                .pressure_shift_cm1 = 0.0,
                .pressure_shift_nm = 0.0,
                .rotational_index_m1 = 0,
            },
        }),
        .relaxation_matrix = .{
            .line_count = 1,
            .wt0 = try std.testing.allocator.dupe(f64, &.{1.0}),
            .bw = try std.testing.allocator.dupe(f64, &.{1.0}),
        },
    };
    defer lines.deinit(std.testing.allocator);

    try lines.applyRuntimeControls(std.testing.allocator, 7, &.{2}, 0.02, 8.0, 0.4);
    try std.testing.expectEqual(@as(usize, 1), lines.lines.len);
    try std.testing.expectEqual(@as(u8, 2), lines.lines[0].isotope_number);
    try std.testing.expect(lines.strong_lines == null);
    try std.testing.expect(lines.relaxation_matrix == null);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0e-23), lines.runtime_controls.thresholdStrength(lines.lines).?, 1.0e-30);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), lines.runtime_controls.cutoff_cm1.?, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4), lines.runtime_controls.line_mixing_factor, 1.0e-12);
}

fn applyRuntimeControlsRetryWithAllocator(allocator: Allocator) !void {
    var lines = SpectroscopyLineList{
        .lines = try allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.0, .line_strength_cm2_per_molecule = 4.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.05 },
            .{ .gas_index = 7, .isotope_number = 2, .center_wavelength_nm = 760.1, .line_strength_cm2_per_molecule = 3.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.05 },
        }),
    };
    defer lines.deinit(allocator);

    try lines.applyRuntimeControls(allocator, 7, &.{1}, 0.02, 8.0, 0.4);
    try lines.applyRuntimeControls(allocator, 7, &.{2}, 0.02, 8.0, 0.4);
}

test "runtime controls preserve prior isotope storage across allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        applyRuntimeControlsRetryWithAllocator,
        .{},
    );
}

test "spectroscopy line list partitions strong and weak lanes when sidecars are attached" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35 },
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.2004, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1803.1765, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 34 },
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 769.9000, .line_strength_cm2_per_molecule = 2.50e-21, .air_half_width_nm = 0.00110, .temperature_exponent = 0.58, .lower_state_energy_cm1 = 1790.0, .pressure_shift_nm = 0.00020, .line_mixing_coefficient = 0.00, .branch_ic1 = 4, .branch_ic2 = 1, .rotational_nf = 40 },
        }),
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = SpectroscopyStrongLineSet{
        .lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
            .{
                .center_wavenumber_cm1 = 12966.8087,
                .center_wavelength_nm = 771.2004,
                .population_t0 = 4.99e-05,
                .dipole_ratio = -0.702,
                .dipole_t0 = -5.78e-04,
                .lower_state_energy_cm1 = 1803.1765,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -34,
            },
        }),
    };
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = RelaxationMatrix{
        .line_count = 2,
        .wt0 = try std.testing.allocator.dupe(f64, &.{
            0.02764486,
            0.0004338554,
            0.0004338554,
            0.02655312,
        }),
        .bw = try std.testing.allocator.dupe(f64, &.{
            0.629999646133,
            1.169364903905,
            1.169364903905,
            0.629999646133,
        }),
    };
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);

    const evaluation = lines.evaluateAt(771.25, 255.0, 820.0);
    try std.testing.expect(evaluation.weak_line_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(evaluation.strong_line_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(@abs(evaluation.line_mixing_sigma_cm2_per_molecule) > 0.0);
    try std.testing.expectApproxEqAbs(
        evaluation.weak_line_sigma_cm2_per_molecule + evaluation.strong_line_sigma_cm2_per_molecule,
        evaluation.line_sigma_cm2_per_molecule,
        1e-30,
    );
}

test "strong-line sidecars choose one anchor line per strong feature" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 759.594000, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35 },
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 759.594150, .line_strength_cm2_per_molecule = 2.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 34 },
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 759.594260, .line_strength_cm2_per_molecule = 3.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 33 },
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 759.594500, .line_strength_cm2_per_molecule = 1.5e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 32 },
        }),
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = SpectroscopyStrongLineSet{
        .lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 13165.0,
                .center_wavelength_nm = 759.594260,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
        }),
    };
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = RelaxationMatrix{
        .line_count = 1,
        .wt0 = try std.testing.allocator.dupe(f64, &.{0.02764486}),
        .bw = try std.testing.allocator.dupe(f64, &.{0.629999646133}),
    };
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);

    const anchors = lines.selectStrongLineAnchors(lines.lines, 0);
    try std.testing.expectEqual(@as(?usize, 2), anchors[0]);
    try std.testing.expect(!lineIndexIsStrongAnchor(anchors[0..1], 1));
    try std.testing.expect(!lineIndexIsStrongAnchor(anchors[0..1], 3));
}

test "cutoff-based prewindow keeps far-wing O2A lines beyond one nanometer" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03 },
        }),
        .lines_sorted_ascending = true,
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
    };
    defer lines.deinit(std.testing.allocator);

    const far_wing = lines.evaluateAt(775.0, 255.0, 820.0);
    try std.testing.expect(far_wing.total_sigma_cm2_per_molecule > 0.0);
}

test "vendor O2A partition removes every assigned strong candidate from the weak-line sum" {
    const strong_candidate_a = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35 };
    const strong_candidate_b = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.2004, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1803.1765, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 34 };
    const weak_candidate = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.0500, .line_strength_cm2_per_molecule = 1.10e-21, .air_half_width_nm = 0.00110, .temperature_exponent = 0.58, .lower_state_energy_cm1 = 1790.0, .pressure_shift_nm = 0.00020, .line_mixing_coefficient = 0.00, .branch_ic1 = 4, .branch_ic2 = 1, .rotational_nf = 40 };

    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{ strong_candidate_a, strong_candidate_b, weak_candidate }),
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = SpectroscopyStrongLineSet{
        .lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
        }),
    };
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = RelaxationMatrix{
        .line_count = 1,
        .wt0 = try std.testing.allocator.dupe(f64, &.{0.02764486}),
        .bw = try std.testing.allocator.dupe(f64, &.{0.629999646133}),
    };
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);

    const evaluation = lines.evaluateAt(771.25, 255.0, 820.0);
    const weak_only = weakLineContribution(771.25, weak_candidate, 255.0, 820.0 / 1013.25, hitran_reference_temperature_k, 200.0);

    try std.testing.expectApproxEqRel(
        weak_only.line_sigma_cm2_per_molecule,
        evaluation.weak_line_sigma_cm2_per_molecule,
        1.0e-12,
    );
    try std.testing.expect(evaluation.strong_line_sigma_cm2_per_molecule > 0.0);
}

test "fallback strong-line anchors can preserve weak contributions when requested" {
    const anchor_proxy = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03 };
    const weak_neighbor = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.0500, .line_strength_cm2_per_molecule = 1.10e-21, .air_half_width_nm = 0.00110, .temperature_exponent = 0.58, .lower_state_energy_cm1 = 1790.0, .pressure_shift_nm = 0.00020, .line_mixing_coefficient = 0.00 };

    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{ anchor_proxy, weak_neighbor }),
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
        .preserve_anchor_weak_lines = true,
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = SpectroscopyStrongLineSet{
        .lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
        }),
    };
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = RelaxationMatrix{
        .line_count = 1,
        .wt0 = try std.testing.allocator.dupe(f64, &.{0.02764486}),
        .bw = try std.testing.allocator.dupe(f64, &.{0.629999646133}),
    };
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);
    try lines.buildStrongLineMatchIndex(std.testing.allocator);

    const preserved = lines.evaluateAt(771.25, 255.0, 820.0);
    const weak_only_view = SpectroscopyLineList{
        .lines = lines.lines,
        .lines_sorted_ascending = lines.lines_sorted_ascending,
        .runtime_controls = lines.runtime_controls,
    };
    const weak_only = weak_only_view.evaluateAt(771.25, 255.0, 820.0);

    try std.testing.expectApproxEqRel(
        weak_only.weak_line_sigma_cm2_per_molecule,
        preserved.weak_line_sigma_cm2_per_molecule,
        1.0e-12,
    );
    try std.testing.expect(preserved.strong_line_sigma_cm2_per_molecule > 0.0);
}

test "vendor O2A strong candidates fail fast when they cannot be matched to a sidecar" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.0, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35 },
        }),
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = SpectroscopyStrongLineSet{
        .lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
        }),
    };
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = RelaxationMatrix{
        .line_count = 1,
        .wt0 = try std.testing.allocator.dupe(f64, &.{0.02764486}),
        .bw = try std.testing.allocator.dupe(f64, &.{0.629999646133}),
    };
    defer relaxation_matrix.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.UnmatchedStrongLineCandidate,
        lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix),
    );
}

test "vendor O2A sidecars fail fast when no tagged candidate maps to a sidecar" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35 },
        }),
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = SpectroscopyStrongLineSet{
        .lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
            .{
                .center_wavenumber_cm1 = 12966.8087,
                .center_wavelength_nm = 771.2004,
                .population_t0 = 4.99e-05,
                .dipole_ratio = -0.702,
                .dipole_t0 = -5.78e-04,
                .lower_state_energy_cm1 = 1803.1765,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -34,
            },
        }),
    };
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = RelaxationMatrix{
        .line_count = 2,
        .wt0 = try std.testing.allocator.dupe(f64, &.{
            0.02764486,
            0.0004338554,
            0.0004338554,
            0.02655312,
        }),
        .bw = try std.testing.allocator.dupe(f64, &.{
            0.629999646133,
            1.169364903905,
            1.169364903905,
            0.629999646133,
        }),
    };
    defer relaxation_matrix.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.UnmatchedStrongLineSidecar,
        lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix),
    );
}

test "strong-line convtp state applies detailed-balance and pressure-scaled line mixing" {
    const strong_lines = [_]SpectroscopyStrongLine{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
        .{
            .center_wavenumber_cm1 = 12966.8087,
            .center_wavelength_nm = 771.2004,
            .population_t0 = 4.99e-05,
            .dipole_ratio = -0.702,
            .dipole_t0 = -5.78e-04,
            .lower_state_energy_cm1 = 1803.1765,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -34,
        },
    };
    var relaxation_matrix = RelaxationMatrix{
        .line_count = 2,
        .wt0 = try std.testing.allocator.dupe(f64, &.{ 0.02764486, 0.0004338554, 0.0004338554, 0.02655312 }),
        .bw = try std.testing.allocator.dupe(f64, &.{ 0.629999646133, 1.169364903905, 1.169364903905, 0.629999646133 }),
    };
    defer relaxation_matrix.deinit(std.testing.allocator);

    const low_pressure = prepareStrongLineConvTPState(&strong_lines, relaxation_matrix, 255.0, 0.5);
    const high_pressure = prepareStrongLineConvTPState(&strong_lines, relaxation_matrix, 255.0, 1.0);

    try std.testing.expect(low_pressure.population_t[0] > 0.0);
    try std.testing.expect(@abs(low_pressure.weightAt(1, 0) - low_pressure.weightAt(0, 1)) > 1.0e-10);
    try std.testing.expect(@abs(high_pressure.line_mixing_coefficients[0]) > @abs(low_pressure.line_mixing_coefficients[0]));
    try std.testing.expect(high_pressure.half_width_cm1_at_t[0] > relaxation_matrix.weightAt(0, 0));
}

test "prepared strong-line state preserves upper-atmosphere pressure scaling" {
    var line_list = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{}),
        .strong_lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
            .{
                .center_wavenumber_cm1 = 12966.8087,
                .center_wavelength_nm = 771.2004,
                .population_t0 = 4.99e-05,
                .dipole_ratio = -0.702,
                .dipole_t0 = -5.78e-04,
                .lower_state_energy_cm1 = 1803.1765,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -34,
            },
        }),
        .relaxation_matrix = RelaxationMatrix{
            .line_count = 2,
            .wt0 = try std.testing.allocator.dupe(f64, &.{ 0.02764486, 0.0004338554, 0.0004338554, 0.02655312 }),
            .bw = try std.testing.allocator.dupe(f64, &.{ 0.629999646133, 1.169364903905, 1.169364903905, 0.629999646133 }),
        },
    };
    defer line_list.deinit(std.testing.allocator);

    var prepared_state = (try line_list.prepareStrongLineState(std.testing.allocator, 190.5, 0.000258)).?;
    defer prepared_state.deinit(std.testing.allocator);

    const pressure_atm = 0.000258 / 1013.25;
    const expected_state = prepareStrongLineConvTPState(
        line_list.strong_lines.?,
        line_list.relaxation_matrix.?,
        190.5,
        pressure_atm,
    );

    try std.testing.expectApproxEqAbs(expected_state.sig_moy_cm1, prepared_state.sig_moy_cm1, 1.0e-12);
    try std.testing.expectApproxEqAbs(expected_state.mod_sig_cm1[0], prepared_state.mod_sig_cm1[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(expected_state.half_width_cm1_at_t[0], prepared_state.half_width_cm1_at_t[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(
        expected_state.line_mixing_coefficients[0],
        prepared_state.line_mixing_coefficients[0],
        1.0e-18,
    );
}

test "demo reference assets are allocatable and physically ordered" {
    var profile = try buildDemoClimatology(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = try buildDemoCrossSections(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    var spectroscopy = try buildDemoSpectroscopyLines(std.testing.allocator);
    defer spectroscopy.deinit(std.testing.allocator);
    var lut = try buildDemoAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    try std.testing.expect(profile.rows.len >= 4);
    try std.testing.expect(cross_sections.points[0].wavelength_nm < cross_sections.points[cross_sections.points.len - 1].wavelength_nm);
    try std.testing.expect(spectroscopy.lines.len >= 4);
    try std.testing.expect(lut.points.len >= 3);
}

test "mie phase tables interpolate extinction, SSA, and coefficients deterministically" {
    var table = MiePhaseTable{
        .points = try std.testing.allocator.dupe(MiePhasePoint, &.{
            .{ .wavelength_nm = 400.0, .extinction_scale = 0.96, .single_scatter_albedo = 0.85, .phase_coefficients = .{ 1.0, 2.38, 3.47, 4.32 } },
            .{ .wavelength_nm = 500.0, .extinction_scale = 0.99, .single_scatter_albedo = 0.92, .phase_coefficients = .{ 1.0, 2.26, 3.25, 3.96 } },
        }),
    };
    defer table.deinit(std.testing.allocator);

    const interpolated = table.interpolate(450.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.975), interpolated.extinction_scale, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 2.32), interpolated.phase_coefficients[1], 1e-9);
    try std.testing.expectEqual(@as(f64, 1.0), interpolated.phase_coefficients[0]);
    try std.testing.expect(interpolated.single_scatter_albedo > 0.85);
}

test "strong-line sidecars and relaxation matrices stay typed and square" {
    var strong_lines = SpectroscopyStrongLineSet{
        .lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
            .{
                .center_wavenumber_cm1 = 12966.8087,
                .center_wavelength_nm = 771.2004,
                .population_t0 = 4.99e-05,
                .dipole_ratio = -0.702,
                .dipole_t0 = -5.78e-04,
                .lower_state_energy_cm1 = 1803.1765,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -34,
            },
        }),
    };
    defer strong_lines.deinit(std.testing.allocator);

    var matrix = RelaxationMatrix{
        .line_count = 2,
        .wt0 = try std.testing.allocator.dupe(f64, &.{
            0.02764486,
            0.0004338554,
            0.0004338554,
            0.02655312,
        }),
        .bw = try std.testing.allocator.dupe(f64, &.{
            0.629999646133,
            1.169364903905,
            1.169364903905,
            0.629999646133,
        }),
    };
    defer matrix.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), strong_lines.lines.len);
    try std.testing.expectEqual(@as(usize, 2), matrix.line_count);
    try std.testing.expect(matrix.weightAt(0, 0) > matrix.weightAt(0, 1));
    try std.testing.expect(matrix.temperatureExponentAt(0, 1) > 0.0);
}

const ComplexProbability = struct {
    wr: f64,
    wi: f64,
};

const VoigtProfile = struct {
    real: f64,
    imag: f64,
};

const WeakLineVoigtState = struct {
    prefactor: f64,
    cpf: ComplexProbability,
};

const StrongLineConvTPState = struct {
    line_count: usize,
    sig_moy_cm1: f64 = 0.0,
    population_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    dipole_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    mod_sig_cm1: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    half_width_cm1_at_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    line_mixing_coefficients: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    relaxation_weights: [max_strong_line_sidecars * max_strong_line_sidecars]f64 = [_]f64{0.0} ** (max_strong_line_sidecars * max_strong_line_sidecars),

    fn weightAt(self: StrongLineConvTPState, row: usize, col: usize) f64 {
        return self.relaxation_weights[row * max_strong_line_sidecars + col];
    }

    fn setWeight(self: *StrongLineConvTPState, row: usize, col: usize, value: f64) void {
        self.relaxation_weights[row * max_strong_line_sidecars + col] = value;
    }
};

fn clonePreparedStrongLineState(
    allocator: Allocator,
    state: StrongLineConvTPState,
) !StrongLinePreparedState {
    const population_t = try allocator.dupe(f64, state.population_t[0..state.line_count]);
    errdefer allocator.free(population_t);
    const dipole_t = try allocator.dupe(f64, state.dipole_t[0..state.line_count]);
    errdefer allocator.free(dipole_t);
    const mod_sig_cm1 = try allocator.dupe(f64, state.mod_sig_cm1[0..state.line_count]);
    errdefer allocator.free(mod_sig_cm1);
    const half_width_cm1_at_t = try allocator.dupe(f64, state.half_width_cm1_at_t[0..state.line_count]);
    errdefer allocator.free(half_width_cm1_at_t);
    const line_mixing_coefficients = try allocator.dupe(
        f64,
        state.line_mixing_coefficients[0..state.line_count],
    );
    errdefer allocator.free(line_mixing_coefficients);
    const relaxation_weights = try allocator.alloc(f64, state.line_count * state.line_count);
    errdefer allocator.free(relaxation_weights);

    for (0..state.line_count) |row_index| {
        for (0..state.line_count) |column_index| {
            relaxation_weights[row_index * state.line_count + column_index] =
                state.weightAt(row_index, column_index);
        }
    }

    return .{
        .line_count = state.line_count,
        .sig_moy_cm1 = state.sig_moy_cm1,
        .population_t = population_t,
        .dipole_t = dipole_t,
        .mod_sig_cm1 = mod_sig_cm1,
        .half_width_cm1_at_t = half_width_cm1_at_t,
        .line_mixing_coefficients = line_mixing_coefficients,
        .relaxation_weights = relaxation_weights,
    };
}

fn voigtProfile(wavelength_nm: f64, center_nm: f64, doppler_hwhm_nm: f64, lorentz_hwhm_nm: f64) VoigtProfile {
    const safe_doppler_hwhm_nm = @max(doppler_hwhm_nm, 1.0e-6);
    const cte = @sqrt(@log(2.0)) / safe_doppler_hwhm_nm;
    const cte1 = cte / @sqrt(std.math.pi);
    const cpf = complexProbabilityFunction(
        (center_nm - wavelength_nm) * cte,
        @max(lorentz_hwhm_nm, 1.0e-6) * cte,
    );
    return .{
        .real = cte1 * cpf.wr,
        .imag = cte1 * cpf.wi,
    };
}

fn linesSortedAscending(lines: []const SpectroscopyLine) bool {
    if (lines.len < 2) return true;
    for (lines[0 .. lines.len - 1], lines[1..]) |left, right| {
        if (left.center_wavelength_nm > right.center_wavelength_nm) return false;
    }
    return true;
}

fn lowerBoundLineIndex(lines: []const SpectroscopyLine, wavelength_nm: f64) usize {
    var low: usize = 0;
    var high: usize = lines.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (lines[middle].center_wavelength_nm < wavelength_nm) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low;
}

fn upperBoundLineIndex(lines: []const SpectroscopyLine, wavelength_nm: f64) usize {
    var low: usize = 0;
    var high: usize = lines.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (lines[middle].center_wavelength_nm <= wavelength_nm) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low;
}

fn complexProbabilityFunction(x: f64, y: f64) ComplexProbability {
    const t = [_]f64{ 0.314240376, 0.947788391, 1.59768264, 2.27950708, 3.02063703, 3.8897249 };
    const u = [_]f64{ 1.01172805, -0.75197147, 1.2557727e-2, 1.00220082e-2, -2.42068135e-4, 5.00848061e-7 };
    const s = [_]f64{ 1.393237, 0.231152406, -0.155351466, 6.21836624e-3, 9.19082986e-5, -6.27525958e-7 };

    var wr: f64 = 0.0;
    var wi: f64 = 0.0;
    const y1 = y + 1.5;
    const y2 = y1 * y1;

    if (y > 0.85 or @abs(x) < (18.1 * y + 1.65)) {
        for (0..t.len) |index| {
            var r = x - t[index];
            var d = 1.0 / (r * r + y2);
            const d1 = y1 * d;
            const d2 = r * d;
            r = x + t[index];
            d = 1.0 / (r * r + y2);
            const d3 = y1 * d;
            const d4 = r * d;
            wr += u[index] * (d1 + d3) - s[index] * (d2 - d4);
            wi += u[index] * (d2 + d4) + s[index] * (d1 - d3);
        }
    } else {
        if (@abs(x) < 12.0) wr = @exp(-x * x);
        const y3 = y + 3.0;
        for (0..t.len) |index| {
            var r = x - t[index];
            var r2 = r * r;
            var d = 1.0 / (r2 + y2);
            const d1 = y1 * d;
            const d2 = r * d;
            wr += y * (u[index] * (r * d2 - 1.5 * d1) + s[index] * y3 * d2) / (r2 + 2.25);

            r = x + t[index];
            r2 = r * r;
            d = 1.0 / (r2 + y2);
            const d3 = y1 * d;
            const d4 = r * d;
            wr += y * (u[index] * (r * d4 - 1.5 * d3) - s[index] * y3 * d4) / (r2 + 2.25);
            wi += u[index] * (d2 + d4) + s[index] * (d1 - d3);
        }
    }

    return .{ .wr = wr, .wi = wi };
}

fn wavelengthToWavenumberCm1(wavelength_nm: f64) f64 {
    return 1.0e7 / @max(wavelength_nm, 1.0e-9);
}

// UNITS:
//   Converts spectral widths from nanometers at the line center into `cm^-1` using the local
//   center wavenumber. This keeps the vendor strong-line width formulas in their native domain.
fn spectralWidthNmToCm1(width_nm: f64, center_wavenumber_cm1: f64) f64 {
    const safe_center = @max(center_wavenumber_cm1, 1.0);
    return width_nm * safe_center * safe_center / 1.0e7;
}

fn dopplerWidthCm1(temperature_k: f64, wavenumber_cm1: f64, molecular_weight_g_per_mol: f64) f64 {
    const prefactor = @sqrt(
        2.0 * @log(2.0) * hitran_gas_constant_j_per_mol_k /
            (hitran_speed_of_light_m_per_s * hitran_speed_of_light_m_per_s),
    );
    return prefactor *
        std.math.sqrt(@max(temperature_k, 1.0)) /
        std.math.sqrt(@max(molecular_weight_g_per_mol / 1.0e3, 1.0e-12)) *
        wavenumber_cm1;
}

fn prepareWeakLineVoigtState(
    wavelength_nm: f64,
    line: SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
) WeakLineVoigtState {
    const safe_temperature = @max(temperature_k, 150.0);
    const safe_pressure = @max(pressure_atm, min_spectroscopy_pressure_atm);
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const center_wavenumber_cm1 = wavelengthToWavenumberCm1(line.center_wavelength_nm);
    const temperature_ratio = reference_temperature_k / safe_temperature;
    const pressure_shift_cm1 = -spectralWidthNmToCm1(line.pressure_shift_nm, center_wavenumber_cm1);
    const shifted_center_wavenumber_cm1 = @max(
        center_wavenumber_cm1 + pressure_shift_cm1 * safe_pressure,
        1.0,
    );
    const half_width_cm1_at_t = @max(
        spectralWidthNmToCm1(line.air_half_width_nm, center_wavenumber_cm1) *
            std.math.pow(f64, temperature_ratio, line.temperature_exponent),
        1.0e-6,
    );
    const doppler_width_cm1 = @max(
        dopplerWidthCm1(
            safe_temperature,
            shifted_center_wavenumber_cm1,
            molecularWeightForLine(line),
        ),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / doppler_width_cm1;
    const cpf = complexProbabilityFunction(
        (shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1) * cte,
        half_width_cm1_at_t * safe_pressure * cte,
    );

    // PARITY:
    //   HITRAN line strengths already include isotopic abundance. Keep
    //   `abundance_fraction` as typed metadata, but do not apply it again here.
    var converted_strength = line.line_strength_cm2_per_molecule *
        partitionRatioT0OverT(line, safe_temperature, reference_temperature_k) *
        @exp(
            hitran_hc_over_kb_cm_k * line.lower_state_energy_cm1 *
                ((1.0 / reference_temperature_k) - (1.0 / safe_temperature)),
        ) /
        shifted_center_wavenumber_cm1;
    converted_strength *= 0.1013 /
        hitran_boltzmann_constant_j_per_k /
        safe_temperature /
        @max(
            1.0 - @exp(-hitran_hc_over_kb_cm_k * shifted_center_wavenumber_cm1 / reference_temperature_k),
            1.0e-12,
        );

    const stimulated_emission_scale = evaluation_wavenumber_cm1 *
        (1.0 - @exp(-hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature));
    const prefactor = @sqrt(@log(2.0)) /
        doppler_width_cm1 /
        @sqrt(std.math.pi) *
        safe_pressure *
        converted_strength *
        stimulated_emission_scale *
        safe_temperature *
        hitran_boltzmann_constant_cm3_hpa_per_k /
        safe_pressure /
        1013.25;

    return .{
        .prefactor = prefactor,
        .cpf = cpf,
    };
}

fn weakLineContribution(
    wavelength_nm: f64,
    line: SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
    cutoff_cm1: ?f64,
) SpectroscopyEvaluation {
    if (cutoff_cm1) |window_cm1| {
        const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
        if (@abs(shiftedLineCenterWavenumberCm1(line, pressure_atm) - evaluation_wavenumber_cm1) > window_cm1) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }
    }
    const state = prepareWeakLineVoigtState(
        wavelength_nm,
        line,
        temperature_k,
        pressure_atm,
        reference_temperature_k,
    );
    const line_sigma = @max(state.prefactor * state.cpf.wr, 0.0);
    return .{
        .weak_line_sigma_cm2_per_molecule = line_sigma,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = line_sigma,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

fn strongLineContribution(
    wavelength_nm: f64,
    line: SpectroscopyLine,
    strong_lines: []const SpectroscopyStrongLine,
    strong_index: usize,
    convtp_state: StrongLineConvTPState,
    temperature_k: f64,
    pressure_scale: f64,
    cutoff_cm1: ?f64,
) SpectroscopyEvaluation {
    _ = strong_lines;
    const safe_temperature = @max(temperature_k, 150.0);
    const safe_pressure = @max(pressure_scale, min_spectroscopy_pressure_atm);
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    if (cutoff_cm1) |window_cm1| {
        if (@abs(convtp_state.mod_sig_cm1[strong_index] - evaluation_wavenumber_cm1) > window_cm1) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }
    }
    const sig_moy_cm1 = @max(convtp_state.sig_moy_cm1, convtp_state.mod_sig_cm1[strong_index]);
    const gam_d = @max(
        dopplerWidthCm1(safe_temperature, sig_moy_cm1, molecularWeightForLine(line)),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / gam_d;
    const cte1 = cte / @sqrt(std.math.pi);
    const cpf = complexProbabilityFunction(
        (convtp_state.mod_sig_cm1[strong_index] - evaluation_wavenumber_cm1) * cte,
        convtp_state.half_width_cm1_at_t[strong_index] * safe_pressure * cte,
    );
    const cte2 = evaluation_wavenumber_cm1 *
        @max(1.0 - @exp(-hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature), 0.0);
    const base_absorption = cte1 *
        safe_pressure *
        convtp_state.population_t[strong_index] *
        convtp_state.dipole_t[strong_index] *
        convtp_state.dipole_t[strong_index] *
        cte2;
    const number_density = 1013.25 * safe_pressure / safe_temperature / hitran_boltzmann_constant_cm3_hpa_per_k;
    const line_sigma = @max(base_absorption * cpf.wr / number_density, 0.0);
    const line_mixing_sigma = (-base_absorption *
        convtp_state.line_mixing_coefficients[strong_index] *
        cpf.wi) / number_density;
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = line_sigma,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = @max(line_sigma + line_mixing_sigma, 0.0),
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

fn strongLineContributionPrepared(
    wavelength_nm: f64,
    line: SpectroscopyLine,
    strong_lines: []const SpectroscopyStrongLine,
    strong_index: usize,
    prepared_state: *const StrongLinePreparedState,
    temperature_k: f64,
    pressure_scale: f64,
    cutoff_cm1: ?f64,
) SpectroscopyEvaluation {
    _ = strong_lines;
    const safe_temperature = @max(temperature_k, 150.0);
    const safe_pressure = @max(pressure_scale, min_spectroscopy_pressure_atm);
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    if (cutoff_cm1) |window_cm1| {
        if (@abs(prepared_state.mod_sig_cm1[strong_index] - evaluation_wavenumber_cm1) > window_cm1) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }
    }
    const sig_moy_cm1 = @max(prepared_state.sig_moy_cm1, prepared_state.mod_sig_cm1[strong_index]);
    const gam_d = @max(
        dopplerWidthCm1(safe_temperature, sig_moy_cm1, molecularWeightForLine(line)),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / gam_d;
    const cte1 = cte / @sqrt(std.math.pi);
    const cpf = complexProbabilityFunction(
        (prepared_state.mod_sig_cm1[strong_index] - evaluation_wavenumber_cm1) * cte,
        prepared_state.half_width_cm1_at_t[strong_index] * safe_pressure * cte,
    );
    const cte2 = evaluation_wavenumber_cm1 *
        @max(1.0 - @exp(-hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature), 0.0);
    const base_absorption = cte1 *
        safe_pressure *
        prepared_state.population_t[strong_index] *
        prepared_state.dipole_t[strong_index] *
        prepared_state.dipole_t[strong_index] *
        cte2;
    const number_density = 1013.25 * safe_pressure / safe_temperature / hitran_boltzmann_constant_cm3_hpa_per_k;
    const line_sigma = @max(base_absorption * cpf.wr / number_density, 0.0);
    const line_mixing_sigma = (-base_absorption *
        prepared_state.line_mixing_coefficients[strong_index] *
        cpf.wi) / number_density;
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = line_sigma,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = @max(line_sigma + line_mixing_sigma, 0.0),
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

fn prepareStrongLineConvTPState(
    strong_lines: []const SpectroscopyStrongLine,
    relaxation_matrix: RelaxationMatrix,
    temperature_k: f64,
    pressure_atm: f64,
) StrongLineConvTPState {
    const reference_temperature_k = hitran_reference_temperature_k;
    const safe_temperature = @max(temperature_k, 150.0);
    const temperature_ratio = reference_temperature_k / safe_temperature;
    const partition_ratio = hitran_partition_tables.ratioT0OverT(66, safe_temperature, reference_temperature_k) orelse temperature_ratio;
    const line_count = @min(@min(strong_lines.len, relaxation_matrix.line_count), max_strong_line_sidecars);

    var state = StrongLineConvTPState{ .line_count = line_count };
    if (line_count == 0) return state;

    for (0..line_count) |row_index| {
        const strong_line = strong_lines[row_index];
        state.population_t[row_index] = strong_line.population_t0 *
            partition_ratio *
            @exp(hitran_hc_over_kb_cm_k * strong_line.lower_state_energy_cm1 * ((1.0 / reference_temperature_k) - (1.0 / safe_temperature)));
        state.dipole_t[row_index] = strong_line.dipole_t0 * std.math.sqrt(temperature_ratio);
        state.mod_sig_cm1[row_index] = strong_line.center_wavenumber_cm1 + pressure_atm * strong_line.pressure_shift_cm1;
        state.half_width_cm1_at_t[row_index] = strong_line.air_half_width_cm1 *
            std.math.pow(f64, temperature_ratio, strong_line.temperature_exponent);

        for (0..line_count) |column_index| {
            state.setWeight(
                row_index,
                column_index,
                relaxation_matrix.weightAt(row_index, column_index) *
                    std.math.pow(f64, temperature_ratio, relaxation_matrix.temperatureExponentAt(row_index, column_index)),
            );
        }
    }

    for (0..line_count) |row_index| {
        for (0..line_count) |column_index| {
            if (strong_lines[column_index].lower_state_energy_cm1 < strong_lines[row_index].lower_state_energy_cm1) continue;
            state.setWeight(
                column_index,
                row_index,
                state.weightAt(row_index, column_index) *
                    state.population_t[column_index] /
                    @max(state.population_t[row_index], 1.0e-24),
            );
        }
    }

    for (0..line_count) |index| {
        state.setWeight(index, index, state.half_width_cm1_at_t[index]);
    }

    var weighted_center_sum: f64 = 0.0;
    var weighted_center_norm: f64 = 0.0;
    for (0..line_count) |line_index| {
        const weight = state.population_t[line_index] * state.dipole_t[line_index] * state.dipole_t[line_index];
        weighted_center_sum += state.mod_sig_cm1[line_index] * weight;
        weighted_center_norm += weight;
    }
    state.sig_moy_cm1 = if (weighted_center_norm > 0.0)
        weighted_center_sum / weighted_center_norm
    else if (line_count != 0)
        state.mod_sig_cm1[0]
    else
        0.0;

    for (0..line_count) |column_index| {
        var upper_sum: f64 = 0.0;
        var lower_sum: f64 = 0.0;
        for (0..line_count) |row_index| {
            if (row_index <= column_index) {
                upper_sum += strong_lines[row_index].dipole_ratio * state.weightAt(row_index, column_index);
            } else {
                lower_sum += strong_lines[row_index].dipole_ratio * state.weightAt(row_index, column_index);
            }
        }
        if (@abs(lower_sum) <= 1.0e-24) continue;

        const rotational_gate = 1.0 - std.math.clamp(
            @abs(@as(f64, @floatFromInt(strong_lines[column_index].rotational_index_m1))) / 36.0,
            0.0,
            1.0,
        );
        const renormalization_anchor = strong_lines[column_index].dipole_ratio *
            rotational_gate *
            rotational_gate *
            0.04;
        // DECISION:
        //   The Zig strong-line path keeps the vendor-style renormalization anchor explicit here
        //   instead of hiding it in file-driven state, so parity-sensitive line-mixing tuning is
        //   localized to the prepared strong-line state.

        for (0..line_count) |row_index| {
            if (row_index <= column_index) continue;
            const renormalized = -state.weightAt(row_index, column_index) *
                (upper_sum - renormalization_anchor) /
                lower_sum;
            state.setWeight(row_index, column_index, renormalized);
            state.setWeight(
                column_index,
                row_index,
                renormalized * state.population_t[column_index] / @max(state.population_t[row_index], 1.0e-24),
            );
        }
    }

    for (0..line_count) |line_index| {
        var mixing_sum: f64 = 0.0;
        const self_dipole = if (@abs(state.dipole_t[line_index]) > 1.0e-24)
            state.dipole_t[line_index]
        else
            1.0e-24;
        for (0..line_count) |other_index| {
            if (other_index == line_index) continue;
            const delta_sig = state.mod_sig_cm1[line_index] - state.mod_sig_cm1[other_index];
            if (@abs(delta_sig) <= 1.0e-12) continue;
            mixing_sum += 2.0 * state.dipole_t[other_index] / self_dipole *
                state.weightAt(other_index, line_index) /
                delta_sig;
        }
        state.line_mixing_coefficients[line_index] = pressure_atm * mixing_sum;
    }

    return state;
}

fn shiftedLineCenterWavenumberCm1(line: SpectroscopyLine, pressure_atm: f64) f64 {
    return @max(
        wavelengthToWavenumberCm1(line.center_wavelength_nm + line.pressure_shift_nm * pressure_atm),
        1.0,
    );
}

fn partitionRatioT0OverT(line: SpectroscopyLine, temperature_k: f64, reference_temperature_k: f64) f64 {
    const isotopologue_code = deriveIsotopologueCode(line.gas_index, line.isotope_number);
    if (hitran_partition_tables.ratioT0OverT(isotopologue_code, temperature_k, reference_temperature_k)) |ratio| {
        return ratio;
    }

    const safe_temperature = @max(temperature_k, 150.0);
    const exponent: f64 = switch (isotopologue_code) {
        66, 68, 67, 101, 102 => 1.0,
        626, 636, 628, 627, 638, 637 => 1.35,
        161, 181, 171, 162, 182, 172 => 1.10,
        else => 1.0 + 0.04 * @as(f64, @floatFromInt(@max(line.isotope_number, 1) - 1)),
    };
    return std.math.pow(f64, reference_temperature_k / safe_temperature, exponent);
}

fn deriveIsotopologueCode(gas_index: u16, isotope_number: u8) i32 {
    // PARITY:
    //   These mappings preserve the vendor/HITRAN isotopologue codes that drive partition-table
    //   lookup and molecular-weight selection. Changing them silently alters line strengths.
    return switch (gas_index) {
        1 => switch (isotope_number) {
            1 => 161,
            2 => 181,
            3 => 171,
            4 => 162,
            5 => 182,
            6 => 172,
            else => 160 + @as(i32, @intCast(isotope_number)),
        },
        7 => switch (isotope_number) {
            1 => 66,
            2 => 68,
            3 => 67,
            4 => 69,
            else => 70 + @as(i32, @intCast(isotope_number)),
        },
        2 => switch (isotope_number) {
            1 => 626,
            2 => 636,
            3 => 628,
            4 => 627,
            5 => 638,
            6 => 637,
            else => 620 + @as(i32, @intCast(isotope_number)),
        },
        5 => switch (isotope_number) {
            1 => 26,
            2 => 36,
            3 => 28,
            4 => 27,
            5 => 38,
            6 => 37,
            else => 20 + @as(i32, @intCast(isotope_number)),
        },
        6 => switch (isotope_number) {
            1 => 211,
            2 => 311,
            3 => 212,
            else => 210 + @as(i32, @intCast(isotope_number)),
        },
        11 => switch (isotope_number) {
            1 => 4111,
            2 => 5111,
            else => 4100 + @as(i32, @intCast(isotope_number)),
        },
        else => @as(i32, gas_index) * 100 + @as(i32, isotope_number),
    };
}

fn molecularWeightForLine(line: SpectroscopyLine) f64 {
    return switch (deriveIsotopologueCode(line.gas_index, line.isotope_number)) {
        161 => 18.010565,
        181 => 20.014811,
        171 => 19.014780,
        162 => 19.016740,
        182 => 21.020985,
        172 => 20.020956,
        626 => 43.989830,
        636 => 44.993185,
        628 => 45.994076,
        627 => 44.994045,
        638 => 46.997431,
        637 => 45.997400,
        26 => 27.994915,
        36 => 28.998270,
        28 => 29.999161,
        27 => 28.999130,
        38 => 31.002516,
        37 => 30.002485,
        211 => 16.031300,
        311 => 17.034655,
        212 => 17.037475,
        66 => 31.989830,
        68 => 33.994076,
        67 => 32.994045,
        4111 => 17.026549,
        5111 => 18.023583,
        else => switch (line.gas_index) {
            1 => 18.01528,
            2 => 44.0095,
            5 => 28.0101,
            6 => 16.0425,
            7 => 31.9988,
            10 => 46.0055,
            11 => 17.0305,
            else => 28.97,
        },
    };
}
