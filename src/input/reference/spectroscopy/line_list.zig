const std = @import("std");
const PhysicsCore = @import("physics_core.zig");
const StrongLines = @import("strong_lines.zig");
const Support = @import("support.zig");
const Types = @import("types.zig");
const line_list_module = @This();

// line_list.zig --------------------------------------------------------------------------------------------- |
// Spectroscopy line-list owner, filter, window planner, and evaluation entrypoint.                            |
//                                                                                                             |
// called by                                                                                                   |
//   o2a_reference/run.zig loads and attaches vendor O2 sidecars; absorbers.zig applies runtime controls and   |
//   prepares profile/support states; carrier_eval.zig and band_means.zig call prepared evaluation paths.      |
//                                                                                                             |
// main paths                                                                                                  |
//   raw lines -> runtime controls -> sorted/filtered lines -> relevant wavelength windows -> weak sigma       |
//   raw sidecars -> vendor partition detection -> strong-line match index -> prepared strong-line state       |
//   prepared weak/strong state -> wavelength window -> total sigma + line-mixing sigma                        |
//                                                                                                             |
// setup indexes                                                                                               |
//   buildStrongLineMatchIndex, validateStrongLinePartition, and detectVendorStrongLinePartition deliberately  |
//   scan wide SpectroscopyLine rows for one or two fields. They run during setup and produce match/partition  |
//   state used by repeated wavelength evaluation; splitting a center-wavelength/gas-index column would need   |
//   benchmark evidence across the prepared evaluation boundary.                                               |
//                                                                                                             |
// hot path                                                                                                    |
//   Wavelength-time evaluation walks the binary-searched relevant weak-line window and optional strong-line   |
//   sidecars. Prepared-state routes precompute thermodynamic weak/strong terms so carrier evaluation avoids   |
//   repartitioning the list and rebuilding line-shape state for every wavelength.                             |
//                                                                                                             |
// memory                                                                                                      |
//   SpectroscopyLineList owns or borrows out-of-line line, sidecar, relaxation, match-index, and runtime      |
//   control slices. Window structs are borrowed views into those line arrays and caller-provided anchor       |
//   storage; they do not own line data.                                                                       |
// ----------------------------------------------------------------------------------------------------------- |

// SpectroscopyLineList -------------------------------------------------------------------------------------- |
// Header over one spectroscopy line list plus optional O2 strong-line sidecars and controls.                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 208 B (0.203 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] lines                      : []SpectroscopyLine                                                  |
// [ 16.. 31] strong_lines               : ?[]SpectroscopyStrongLine                                           |
// [ 32.. 79] relaxation_matrix          : ?RelaxationMatrix                                                   |
// [ 80.. 87] strong_line_tolerance_nm   : f64                                                                 |
// [ 88..103] strong_line_match_by_line  : ?[]?u16                                                             |
// [104..199] runtime_controls           : SpectroscopyRuntimeControls                                         |
// [200..200] lines_sorted_ascending     : bool                                                                |
// [201..201] preserve_anchor_weak_lines : bool                                                                |
// [202..202] vendor_strong_line_partition : bool                                                              |
// [203..207] trailing padding           : 5 B                                                                 |
//                                                                                                             |
// out-of-line                                                                                                 |
//   lines, strong_lines, relaxation_matrix arrays, match index, and runtime-control slices may own referenced |
//   storage. Deinit follows the owning fields and clears runtime controls.                                    |
//                                                                                                             |
// unused bits: 40 padding + 21 bool-storage slack = 61 bits                                                   |
// cache span: 4 cache lines at 64 B per line                                                                  |
// footprint: per instance = 208 B plus referenced line/control storage                                        |
pub const SpectroscopyLineList = struct {
    lines: []Types.SpectroscopyLine,
    strong_lines: ?[]Types.SpectroscopyStrongLine = null,
    relaxation_matrix: ?Types.RelaxationMatrix = null,
    strong_line_tolerance_nm: f64 = 0.01,
    lines_sorted_ascending: bool = false,
    preserve_anchor_weak_lines: bool = false,
    vendor_strong_line_partition: bool = false,
    strong_line_match_by_line: ?[]?u16 = null,
    runtime_controls: Types.SpectroscopyRuntimeControls = .{},

    pub fn deinit(self: *SpectroscopyLineList, allocator: Types.Allocator) void {
        allocator.free(self.lines);
        if (self.strong_lines) |strong_lines| allocator.free(strong_lines);
        if (self.relaxation_matrix) |*relaxation_matrix| relaxation_matrix.deinit(allocator);
        if (self.strong_line_match_by_line) |matches| allocator.free(matches);
        self.runtime_controls.deinitOwned(allocator);
        self.* = undefined;
    }

    pub fn clone(self: SpectroscopyLineList, allocator: Types.Allocator) !SpectroscopyLineList {
        const owned_lines = try allocator.dupe(Types.SpectroscopyLine, self.lines);
        errdefer allocator.free(owned_lines);

        const owned_strong_lines = if (self.strong_lines) |strong_lines|
            try allocator.dupe(Types.SpectroscopyStrongLine, strong_lines)
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

        const owned_strong_line_match_by_line = if (self.strong_line_match_by_line) |matches|
            try allocator.dupe(?u16, matches)
        else
            null;
        errdefer if (owned_strong_line_match_by_line) |matches| allocator.free(matches);

        var owned_runtime_controls = try self.runtime_controls.clone(allocator);
        errdefer owned_runtime_controls.deinitOwned(allocator);

        return .{
            .lines = owned_lines,
            .strong_lines = owned_strong_lines,
            .relaxation_matrix = owned_relaxation_matrix,
            .strong_line_tolerance_nm = self.strong_line_tolerance_nm,
            .lines_sorted_ascending = self.lines_sorted_ascending,
            .preserve_anchor_weak_lines = self.preserve_anchor_weak_lines,
            .vendor_strong_line_partition = self.vendor_strong_line_partition,
            .strong_line_match_by_line = owned_strong_line_match_by_line,
            .runtime_controls = owned_runtime_controls,
        };
    }

    pub fn attachStrongLineSidecars(
        self: *SpectroscopyLineList,
        allocator: Types.Allocator,
        strong_lines: Types.SpectroscopyStrongLineSet,
        relaxation_matrix: Types.RelaxationMatrix,
    ) !void {
        return line_list_module.attachStrongLineSidecars(self, allocator, strong_lines, relaxation_matrix);
    }

    pub fn buildStrongLineMatchIndex(self: *SpectroscopyLineList, allocator: Types.Allocator) !void {
        return line_list_module.buildStrongLineMatchIndex(self, allocator);
    }

    pub fn sigmaAt(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) f64 {
        return line_list_module.totalSigmaAt(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        ).total_sigma_cm2_per_molecule;
    }

    pub fn applyRuntimeControls(
        self: *SpectroscopyLineList,
        allocator: Types.Allocator,
        gas_index: ?u16,
        active_isotopes: []const u8,
        threshold_line_scale: ?f64,
        cutoff_cm1: ?f64,
        line_mixing_factor: f64,
    ) !void {
        return line_list_module.applyRuntimeControls(
            self,
            allocator,
            gas_index,
            active_isotopes,
            threshold_line_scale,
            cutoff_cm1,
            line_mixing_factor,
        );
    }

    pub fn sigmaAtPrepared(
        self: SpectroscopyLineList,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_state: ?*const Types.StrongLinePreparedState,
    ) f64 {
        if (prepared_state) |state| {
            return line_list_module.totalSigmaWithPreparedStrongLineState(
                self,
                wavelength_nm,
                temperature_k,
                pressure_hpa,
                state,
            ).total_sigma_cm2_per_molecule;
        }
        return self.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
    }

    pub fn evaluateAtPrepared(
        self: SpectroscopyLineList,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_state: ?*const Types.StrongLinePreparedState,
    ) Types.SpectroscopyEvaluation {
        if (prepared_state) |state| {
            return line_list_module.totalSigmaWithPreparedStrongLineState(
                self,
                wavelength_nm,
                temperature_k,
                pressure_hpa,
                state,
            );
        }
        return self.evaluateAt(wavelength_nm, temperature_k, pressure_hpa);
    }

    pub fn hasStrongLineSidecars(self: SpectroscopyLineList) bool {
        return self.strong_lines != null and self.relaxation_matrix != null;
    }

    pub fn prepareStrongLineState(
        self: SpectroscopyLineList,
        allocator: Types.Allocator,
        temperature_k: f64,
        pressure_hpa: f64,
    ) !?Types.StrongLinePreparedState {
        return line_list_module.prepareStrongLineState(self, allocator, temperature_k, pressure_hpa);
    }

    pub fn allocStrongLinePreparedState(
        self: SpectroscopyLineList,
        allocator: Types.Allocator,
    ) !?Types.StrongLinePreparedState {
        return line_list_module.allocStrongLinePreparedState(self, allocator);
    }

    pub fn prepareStrongLineStateInto(
        self: SpectroscopyLineList,
        prepared: *Types.StrongLinePreparedState,
        temperature_k: f64,
        pressure_hpa: f64,
    ) void {
        return line_list_module.prepareStrongLineStateInto(self, prepared, temperature_k, pressure_hpa);
    }

    pub fn prepareStrongLineStateIntoWithScratch(
        self: SpectroscopyLineList,
        prepared: *Types.StrongLinePreparedState,
        relaxation_weights: []f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) void {
        return line_list_module.prepareStrongLineStateIntoWithScratch(
            self,
            prepared,
            relaxation_weights,
            temperature_k,
            pressure_hpa,
        );
    }

    pub fn strongLinePreparedWeightCount(self: SpectroscopyLineList) usize {
        return line_list_module.strongLinePreparedWeightCount(self);
    }

    pub fn prepareWeakLineState(
        self: SpectroscopyLineList,
        allocator: Types.Allocator,
        temperature_k: f64,
        pressure_hpa: f64,
    ) !Types.WeakLinePreparedState {
        return line_list_module.prepareWeakLineState(self, allocator, temperature_k, pressure_hpa);
    }

    pub fn allocWeakLinePreparedState(
        self: SpectroscopyLineList,
        allocator: Types.Allocator,
    ) !Types.WeakLinePreparedState {
        return line_list_module.allocWeakLinePreparedState(self, allocator);
    }

    pub fn prepareWeakLineStateInto(
        self: SpectroscopyLineList,
        prepared: *Types.WeakLinePreparedState,
        temperature_k: f64,
        pressure_hpa: f64,
    ) void {
        return line_list_module.prepareWeakLineStateInto(self, prepared, temperature_k, pressure_hpa);
    }

    pub fn evaluateAt(
        self: SpectroscopyLineList,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) Types.SpectroscopyEvaluation {
        return line_list_module.evaluateAt(self, wavelength_nm, temperature_k, pressure_hpa);
    }
};

// StrongLineWavelengthWindow -------------------------------------------------------------------------------- |
// Borrowed weak-line window plus strong-line anchor indexes for one wavelength.                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] lines       : []const SpectroscopyLine                                                             |
// [16..23] start_index : usize                                                                                |
// [24..39] anchors     : []const StrongLineAnchorIndex                                                        |
//                                                                                                             |
// out-of-line                                                                                                 |
//   lines borrows a slice of SpectroscopyLineList.lines. anchors borrows caller-provided anchor storage.      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 40 B plus borrowed line and anchor storage                                        |
pub const StrongLineWavelengthWindow = struct {
    lines: []const Types.SpectroscopyLine,
    start_index: usize,
    anchors: []const Types.StrongLineAnchorIndex,
};

pub fn evaluateAt(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) Types.SpectroscopyEvaluation {
    // evaluateAt -------------------------------------------------------------------------------------------- |
    // Computes base sigma and finite-temperature derivative samples for one active line absorber.             |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Support-row spectroscopy calls this when no caller-supplied prepared state is available. The base     |
    //   total and two temperature perturbations share the same totalSigma* routing.                           |
    // ------------------------------------------------------------------------------------------------------- |

    const total = totalSigmaAt(self, wavelength_nm, temperature_k, pressure_hpa);
    const delta_t = 0.5;
    const upper = totalSigmaAt(self, wavelength_nm, temperature_k + delta_t, pressure_hpa);
    const lower = totalSigmaAt(self, wavelength_nm, @max(temperature_k - delta_t, 150.0), pressure_hpa);
    const d_sigma_d_temperature =
        (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / (2.0 * delta_t);

    return .{
        .weak_line_sigma_cm2_per_molecule = total.weak_line_sigma_cm2_per_molecule,
        .strong_line_sigma_cm2_per_molecule = total.strong_line_sigma_cm2_per_molecule,
        .line_sigma_cm2_per_molecule = total.line_sigma_cm2_per_molecule,
        .line_mixing_sigma_cm2_per_molecule = total.line_mixing_sigma_cm2_per_molecule,
        .total_sigma_cm2_per_molecule = total.total_sigma_cm2_per_molecule,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = d_sigma_d_temperature,
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
    // totalSigmaFromLineListOnly ---------------------------------------------------------------------------- |
    // Scans the relevant weak-line window and sums weak-line contributions.                                   |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Used for line lists without strong-line sidecars. The relevant-window helper keeps cutoff filtering   |
    //   outside the inner contribution loop when sorted line centers are available.                           |
    // ------------------------------------------------------------------------------------------------------- |

    if (self.lines.len == 0) return Support.zeroEvaluation();

    const safe_temperature = @max(temperature_k, 150.0);
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const relevant_window = line_list_module.relevantLineWindowForWavelength(self, wavelength_nm);
    var line_sigma: f64 = 0.0;
    for (relevant_window.lines) |line| {
        const contribution = PhysicsCore.weakLineContribution(
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

pub fn totalSigmaWithStrongLineSidecars(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) Types.SpectroscopyEvaluation {
    // totalSigmaWithStrongLineSidecars ---------------------------------------------------------------------- |
    // Sums weak-line contributions plus one-shot strong-line sidecar contributions.                           |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Builds a stack ConvTP state for this thermodynamic point, then walks the relevant weak-line window    |
    //   and all strong-line sidecars.                                                                         |
    // ------------------------------------------------------------------------------------------------------- |

    if (self.lines.len == 0) return Support.zeroEvaluation();

    const strong_lines = self.strong_lines.?;
    const relaxation_matrix = self.relaxation_matrix.?;
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const safe_temperature = @max(temperature_k, 150.0);
    const convtp_state = StrongLines.prepareStrongLineConvTPState(
        strong_lines,
        relaxation_matrix,
        safe_temperature,
        pressure_scale,
    );
    const relevant_window = line_list_module.relevantLineWindowForWavelength(self, wavelength_nm);
    const relevant_lines = relevant_window.lines;
    var anchor_storage: [Types.max_strong_line_sidecars]Types.StrongLineAnchorIndex = undefined;
    const strong_line_anchors = line_list_module.selectStrongLineAnchors(
        self,
        relevant_lines,
        relevant_window.start_index,
        &anchor_storage,
    );

    var weak_line_sigma: f64 = 0.0;
    var strong_line_sigma: f64 = 0.0;
    var line_mixing_sigma: f64 = 0.0;

    for (relevant_lines, 0..) |*line, line_index| {
        if (line_list_module.shouldExcludeWeakLine(
            self,
            relevant_window.start_index,
            line,
            line_index,
            strong_line_anchors,
        )) continue;

        const contribution = PhysicsCore.weakLineContribution(
            wavelength_nm,
            line.*,
            safe_temperature,
            pressure_scale,
            Types.hitran_reference_temperature_k,
            self.runtime_controls,
        );
        weak_line_sigma += contribution.line_sigma_cm2_per_molecule;
    }

    for (strong_lines, 0..) |_, strong_index| {
        const contribution = StrongLines.strongLineContribution(
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

    var anchor_storage: [Types.max_strong_line_sidecars]Types.StrongLineAnchorIndex = undefined;
    const window = prepareStrongLineWavelengthWindow(self, wavelength_nm, &anchor_storage);
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
    anchor_storage: []Types.StrongLineAnchorIndex,
) StrongLineWavelengthWindow {
    const relevant_window = line_list_module.relevantLineWindowForWavelength(self, wavelength_nm);
    return .{
        .lines = relevant_window.lines,
        .start_index = relevant_window.start_index,
        .anchors = line_list_module.selectStrongLineAnchors(
            self,
            relevant_window.lines,
            relevant_window.start_index,
            anchor_storage,
        ),
    };
}

pub fn totalSigmaWithPreparedStrongLineStateAndWindow(
    self: SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_state: *const Types.StrongLinePreparedState,
    prepared_weak_state: ?*const Types.WeakLinePreparedState,
    window: *const StrongLineWavelengthWindow,
) Types.SpectroscopyEvaluation {
    // totalSigmaWithPreparedStrongLineStateAndWindow -------------------------------------------------------- |
    // Sums prepared weak-line and prepared strong-line sigma contributions for one wavelength window.         |
    //                                                                                                         |
    // hot path                                                                                                |
    //   This is the repeated evaluation path used by carrier and band-mean code when prepared state is        |
    //   available. Weak-line wavelength state and thermodynamic scales are computed once per window.          |
    // ------------------------------------------------------------------------------------------------------- |

    if (self.lines.len == 0) return Support.zeroEvaluation();

    const strong_lines = self.strong_lines.?;
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const safe_temperature = @max(temperature_k, 150.0);

    var weak_line_sigma: f64 = 0.0;
    var strong_line_sigma: f64 = 0.0;
    var line_mixing_sigma: f64 = 0.0;
    const weak_line_wavelength_state = PhysicsCore.prepareWeakLineWavelengthState(wavelength_nm, self.runtime_controls);

    const WeakLineRoute = struct {
        states: ?[]const Types.WeakLinePreparedLineState,
        stimulated_emission_scale: f64,
        thermodynamic_scale: f64,
    };
    const weak_line_route: WeakLineRoute = choose_weak_line_route: {
        const state = prepared_weak_state orelse break :choose_weak_line_route .{
            .states = null,
            .stimulated_emission_scale = 0.0,
            .thermodynamic_scale = 0.0,
        };

        if (state.line_count != self.lines.len) {
            break :choose_weak_line_route .{
                .states = null,
                .stimulated_emission_scale = 0.0,
                .thermodynamic_scale = 0.0,
            };
        }

        break :choose_weak_line_route .{
            .states = state.lines,
            .stimulated_emission_scale = PhysicsCore.weakLinePreparedStimulatedEmissionScale(
                weak_line_wavelength_state,
                state.safe_temperature,
            ),
            .thermodynamic_scale = PhysicsCore.weakLinePreparedThermodynamicScale(
                state.safe_temperature,
                state.safe_pressure,
            ),
        };
    };
    const uses_vendor_weak_exclusions =
        line_list_module.usesVendorStrongLinePartition(self) and !self.preserve_anchor_weak_lines;
    const vendor_weak_exclusions = if (uses_vendor_weak_exclusions)
        self.strong_line_match_by_line
    else
        null;

    for (window.lines, 0..) |*line, line_index| {
        const exclude_weak_line = choose_exclude_weak_line: {
            if (vendor_weak_exclusions) |matches| {
                const global_index = window.start_index + line_index;
                break :choose_exclude_weak_line global_index < matches.len and matches[global_index] != null;
            }

            break :choose_exclude_weak_line line_list_module.shouldExcludeWeakLine(
                self,
                window.start_index,
                line,
                line_index,
                window.anchors,
            );
        };
        if (exclude_weak_line) continue;

        if (weak_line_route.states) |states| {
            weak_line_sigma += PhysicsCore.weakLineSigmaPreparedWithStimulatedEmissionScale(
                weak_line_wavelength_state,
                states[window.start_index + line_index],
                self.runtime_controls,
                weak_line_route.stimulated_emission_scale,
                weak_line_route.thermodynamic_scale,
            );
        } else {
            const contribution = PhysicsCore.weakLineContributionWithWavelengthState(
                wavelength_nm,
                line.*,
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
        const contribution = StrongLines.strongLineContributionPrepared(
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

pub fn attachStrongLineSidecars(
    self: *SpectroscopyLineList,
    allocator: Types.Allocator,
    strong_lines: Types.SpectroscopyStrongLineSet,
    relaxation_matrix: Types.RelaxationMatrix,
) !void {
    if (self.strong_lines) |owned_strong_lines| allocator.free(owned_strong_lines);
    if (self.relaxation_matrix) |*owned_relaxation_matrix| owned_relaxation_matrix.deinit(allocator);
    if (self.strong_line_match_by_line) |matches| allocator.free(matches);
    self.strong_line_match_by_line = null;

    self.strong_lines = try allocator.dupe(Types.SpectroscopyStrongLine, strong_lines.lines);
    errdefer {
        if (self.strong_lines) |owned_strong_lines| allocator.free(owned_strong_lines);
        self.strong_lines = null;
    }
    self.relaxation_matrix = try relaxation_matrix.clone(allocator);
    self.vendor_strong_line_partition = detectVendorStrongLinePartition(self.*);
    try validateStrongLinePartition(self);
}

pub fn buildStrongLineMatchIndex(self: *SpectroscopyLineList, allocator: Types.Allocator) !void {
    // buildStrongLineMatchIndex --------------------------------------------------------------------------    |
    // Build the per-line pointer into the O2 strong-line sidecar table.                                       |
    //                                                                                                         |
    // call path                                                                                               |
    //   absorbers.zig and reference-data tests call this after sidecars/runtime controls are attached.        |
    //   Prepared line-state setup then reuses the match slice instead of searching sidecars per wavelength.   |
    //                                                                                                         |
    // memory                                                                                                  |
    //   SpectroscopyLine is a 104 B row. This setup pass reads center_wavelength_nm by pointer and writes a   |
    //   compact ?u16 match row with the same index order as self.lines.                                       |
    //                                                                                                         |
    // math                                                                                                    |
    //   match when abs(line center - strong-line center) <= strong_line_tolerance_nm                          |
    // ------------------------------------------------------------------------------------------------------- |

    if (self.strong_line_match_by_line) |matches| {
        allocator.free(matches);
        self.strong_line_match_by_line = null;
    }
    if (!self.hasStrongLineSidecars() or self.lines.len == 0) return;
    try validateStrongLinePartition(self);

    const matches = try allocator.alloc(?u16, self.lines.len);
    errdefer allocator.free(matches);

    for (self.lines, 0..) |*line, line_index| {
        const should_skip_vendor_line =
            usesVendorStrongLinePartition(self.*) and !Support.isVendorO2AStrongCandidateFromSource(line);
        if (should_skip_vendor_line) {
            matches[line_index] = null;
            continue;
        }

        matches[line_index] = if (findStrongLineMatch(self.*, line.center_wavelength_nm)) |strong_index|
            @intCast(strong_index)
        else
            null;
    }

    self.strong_line_match_by_line = matches;
}

pub fn applyRuntimeControls(
    self: *SpectroscopyLineList,
    allocator: Types.Allocator,
    gas_index: ?u16,
    active_isotopes: []const u8,
    threshold_line_scale: ?f64,
    cutoff_cm1: ?f64,
    line_mixing_factor: f64,
) !void {
    // applyRuntimeControls ---------------------------------------------------------------------------------- |
    // Filters and partitions lines according to runtime gas, isotope, threshold, cutoff, and line-mixing      |
    // controls.                                                                                               |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Runs during scene/session line-list preparation. The resulting line-list shape is consumed by         |
    //   relevantLineWindowForWavelength and prepared-state builders.                                          |
    // ------------------------------------------------------------------------------------------------------- |

    const replacement_active_isotopes = if (active_isotopes.len != 0)
        try allocator.dupe(u8, active_isotopes)
    else
        &.{};
    self.runtime_controls.deinitOwned(allocator);
    self.runtime_controls = .{
        .gas_index = gas_index,
        .active_isotopes = replacement_active_isotopes,
        .threshold_line_scale = threshold_line_scale,
        .cutoff_cm1 = cutoff_cm1,
        .line_mixing_factor = line_mixing_factor,
    };

    const should_filter_lines = gas_index != null or active_isotopes.len != 0;
    if (should_filter_lines) {
        var retained_count: usize = 0;
        for (self.lines) |*line| {
            if (Support.runtimeControlsMatchLine(gas_index, active_isotopes, line)) retained_count += 1;
        }

        if (retained_count != self.lines.len) {
            const retained = try allocator.alloc(Types.SpectroscopyLine, retained_count);
            errdefer allocator.free(retained);

            var write_index: usize = 0;
            for (self.lines) |*line| {
                if (!Support.runtimeControlsMatchLine(gas_index, active_isotopes, line)) continue;
                retained[write_index] = line.*;
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
    if (self.strong_lines != null and !Support.runtimeControlsKeepStrongLineSidecars(gas_index, active_isotopes)) {
        disableStrongLineSidecars(self, allocator);
        return;
    }
    self.vendor_strong_line_partition = detectVendorStrongLinePartition(self.*);
    try validateStrongLinePartition(self);
}

pub fn prepareStrongLineState(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
    temperature_k: f64,
    pressure_hpa: f64,
) !?Types.StrongLinePreparedState {
    if (!self.hasStrongLineSidecars()) return null;
    var prepared = (try allocStrongLinePreparedState(self, allocator)).?;
    errdefer prepared.deinit(allocator);
    const weight_count = strongLinePreparedWeightCount(self);
    const relaxation_weights = try allocator.alloc(f64, weight_count);
    defer allocator.free(relaxation_weights);
    prepareStrongLineStateIntoWithScratch(self, &prepared, relaxation_weights, temperature_k, pressure_hpa);
    return prepared;
}

pub fn allocStrongLinePreparedState(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
) !?Types.StrongLinePreparedState {
    if (!self.hasStrongLineSidecars()) return null;
    const line_count = strongLinePreparedLineCount(self);
    const population_t = try allocator.alloc(f64, line_count);
    errdefer allocator.free(population_t);
    const dipole_t = try allocator.alloc(f64, line_count);
    errdefer allocator.free(dipole_t);
    const mod_sig_cm1 = try allocator.alloc(f64, line_count);
    errdefer allocator.free(mod_sig_cm1);
    const half_width_cm1_at_t = try allocator.alloc(f64, line_count);
    errdefer allocator.free(half_width_cm1_at_t);
    const line_mixing_coefficients = try allocator.alloc(f64, line_count);
    return .{
        .line_count = line_count,
        .sig_moy_cm1 = 0.0,
        .population_t = population_t,
        .dipole_t = dipole_t,
        .mod_sig_cm1 = mod_sig_cm1,
        .half_width_cm1_at_t = half_width_cm1_at_t,
        .line_mixing_coefficients = line_mixing_coefficients,
    };
}

pub fn prepareStrongLineStateInto(
    self: SpectroscopyLineList,
    prepared: *Types.StrongLinePreparedState,
    temperature_k: f64,
    pressure_hpa: f64,
) void {
    // prepareStrongLineStateInto ---------------------------------------------------------------------------- |
    // Fills pressure/temperature-dependent strong-line relaxation state.                                      |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Runs while preparing profile-node or effective strong-line spectroscopy state. The prepared sidecar   |
    //   ordering is consumed by strongLineContributionPrepared.                                               |
    // ------------------------------------------------------------------------------------------------------- |

    var relaxation_weights: [Types.max_strong_line_sidecars * Types.max_strong_line_sidecars]f64 = undefined;
    prepareStrongLineStateIntoWithScratch(
        self,
        prepared,
        relaxation_weights[0..strongLinePreparedWeightCount(self)],
        temperature_k,
        pressure_hpa,
    );
}

pub fn prepareStrongLineStateIntoWithScratch(
    self: SpectroscopyLineList,
    prepared: *Types.StrongLinePreparedState,
    relaxation_weights: []f64,
    temperature_k: f64,
    pressure_hpa: f64,
) void {
    std.debug.assert(self.hasStrongLineSidecars());
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    StrongLines.prepareStrongLinePreparedStateInto(
        self.strong_lines.?,
        self.relaxation_matrix.?,
        @max(temperature_k, 150.0),
        pressure_scale,
        relaxation_weights,
        prepared,
    );
}

pub fn prepareWeakLineState(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
    temperature_k: f64,
    pressure_hpa: f64,
) !Types.WeakLinePreparedState {
    var prepared = try allocWeakLinePreparedState(self, allocator);
    prepareWeakLineStateInto(self, &prepared, temperature_k, pressure_hpa);
    return prepared;
}

pub fn allocWeakLinePreparedState(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
) !Types.WeakLinePreparedState {
    return .{
        .line_count = self.lines.len,
        .lines = try allocator.alloc(Types.WeakLinePreparedLineState, self.lines.len),
    };
}

pub fn prepareWeakLineStateInto(
    self: SpectroscopyLineList,
    prepared: *Types.WeakLinePreparedState,
    temperature_k: f64,
    pressure_hpa: f64,
) void {
    // prepareWeakLineStateInto ------------------------------------------------------------------------------ |
    // Fills thermodynamic weak-line state for repeated wavelength evaluation.                                 |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Runs while preparing profile-node or effective weak-line spectroscopy state. The output rows are      |
    //   streamed by weakLineSigmaPreparedWithStimulatedEmissionScale.                                         |
    // ------------------------------------------------------------------------------------------------------- |

    std.debug.assert(prepared.lines.len >= self.lines.len);
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const safe_temperature = @max(temperature_k, 150.0);
    prepared.safe_temperature = safe_temperature;
    prepared.safe_pressure = pressure_scale;
    for (self.lines, prepared.lines[0..self.lines.len]) |line, *slot| {
        slot.* = PhysicsCore.prepareWeakLinePreparedLineStateFromSafe(
            line,
            safe_temperature,
            pressure_scale,
            Types.hitran_reference_temperature_k,
        );
    }
    prepared.line_count = self.lines.len;
}

pub fn strongLinePreparedWeightCount(self: SpectroscopyLineList) usize {
    const line_count = strongLinePreparedLineCount(self);
    return line_count * line_count;
}

fn strongLinePreparedLineCount(self: SpectroscopyLineList) usize {
    return @min(
        @min(self.strong_lines.?.len, self.relaxation_matrix.?.line_count),
        Types.max_strong_line_sidecars,
    );
}

pub fn findStrongLineMatch(self: SpectroscopyLineList, wavelength_nm: f64) ?usize {
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

// RelevantLineWindow ---------------------------------------------------------------------------------------- |
// Borrowed weak-line window selected for one wavelength before optional strong-line anchoring.                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] lines       : []const SpectroscopyLine                                                             |
// [16..23] start_index : usize                                                                                |
//                                                                                                             |
// out-of-line                                                                                                 |
//   lines borrows a SpectroscopyLineList.lines subrange; storage lives outside this header.                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 24 B plus borrowed line storage                                                   |
pub const RelevantLineWindow = struct {
    lines: []const Types.SpectroscopyLine,
    start_index: usize,
};

pub fn relevantLineWindowForWavelength(self: SpectroscopyLineList, wavelength_nm: f64) RelevantLineWindow {
    // relevantLineWindowForWavelength ----------------------------------------------------------------------- |
    // Maps one wavelength to the compact weak-line window used by sigma accumulation loops.                   |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Called by every wavelength/support-row line-list evaluation. Sorted line centers allow binary-search  |
    //   bounds when vendor cutoff controls are active; otherwise the full line list is returned.              |
    // ------------------------------------------------------------------------------------------------------- |

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
    const vendor_discrete_cutoff_cm1 = cutoff_cm1 + Types.vendor_cutoff_prewindow_margin_cm1;
    const evaluation_wavenumber_cm1 = PhysicsCore.wavelengthToWavenumberCm1(wavelength_nm);
    const minimum_wavenumber_cm1 = @max(evaluation_wavenumber_cm1 - vendor_discrete_cutoff_cm1, 1.0e-6);
    const maximum_wavenumber_cm1 = evaluation_wavenumber_cm1 + vendor_discrete_cutoff_cm1;
    const minimum_wavelength_nm = Support.wavenumberCm1ToWavelengthNm(maximum_wavenumber_cm1);
    const maximum_wavelength_nm = Support.wavenumberCm1ToWavelengthNm(minimum_wavenumber_cm1);
    const lower = PhysicsCore.lowerBoundLineIndex(self.lines, minimum_wavelength_nm);
    const upper = PhysicsCore.upperBoundLineIndex(self.lines, maximum_wavelength_nm);
    return .{
        .lines = self.lines[lower..upper],
        .start_index = lower,
    };
}

pub fn selectStrongLineAnchors(
    self: SpectroscopyLineList,
    relevant_lines: []const Types.SpectroscopyLine,
    start_index: usize,
    anchor_storage: []Types.StrongLineAnchorIndex,
) []const Types.StrongLineAnchorIndex {
    // selectStrongLineAnchors ------------------------------------------------------------------------------- |
    // Selects nearby strong-line anchors for the current weak-line window.                                    |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Runs before line-mixing evaluation when sidecars are active. Anchor storage is caller-owned so this   |
    //   helper does not allocate per wavelength.                                                              |
    // ------------------------------------------------------------------------------------------------------- |

    const strong_lines = self.strong_lines orelse return &.{};
    if (usesVendorStrongLinePartition(self)) return &.{};
    const anchor_count = @min(strong_lines.len, @min(anchor_storage.len, Types.max_strong_line_sidecars));
    const anchors = anchor_storage[0..anchor_count];
    @memset(anchors, Types.missing_strong_line_anchor_index);

    var deltas = [_]f64{std.math.inf(f64)} ** Types.max_strong_line_sidecars;
    for (relevant_lines, 0..) |*line, line_index| {
        const strong_index = matchedStrongIndexForRelevantLine(self, start_index, line, line_index) orelse continue;

        if (strong_index >= anchors.len) continue;
        if (line_index > std.math.maxInt(Types.StrongLineAnchorIndex)) continue;

        const delta = @abs(strong_lines[strong_index].center_wavelength_nm - line.center_wavelength_nm);
        if (delta > deltas[strong_index]) continue;

        if (delta == deltas[strong_index] and anchors[strong_index] != Types.missing_strong_line_anchor_index) {
            const incumbent = &relevant_lines[@intCast(anchors[strong_index])];
            if (incumbent.line_strength_cm2_per_molecule >= line.line_strength_cm2_per_molecule) continue;
        }

        anchors[strong_index] = @intCast(line_index);
        deltas[strong_index] = delta;
    }

    return anchors;
}

pub fn matchedStrongIndexForRelevantLine(
    self: SpectroscopyLineList,
    start_index: usize,
    line: *const Types.SpectroscopyLine,
    line_index: usize,
) ?usize {
    if (self.strong_line_match_by_line) |matches| {
        const global_index = start_index + line_index;

        if (global_index < matches.len) {
            if (matches[global_index]) |strong_index| return @as(usize, strong_index);
            return null;
        }
    }

    if (usesVendorStrongLinePartition(self)) {
        if (!Support.isVendorO2AStrongCandidateFromSource(line)) return null;
        return findStrongLineMatch(self, line.center_wavelength_nm);
    }

    return findStrongLineMatch(self, line.center_wavelength_nm);
}

pub fn shouldExcludeWeakLine(
    self: SpectroscopyLineList,
    start_index: usize,
    line: *const Types.SpectroscopyLine,
    line_index: usize,
    strong_line_anchors: []const Types.StrongLineAnchorIndex,
) bool {
    // shouldExcludeWeakLine --------------------------------------------------------------------------------- |
    // Checks vendor partition rules and strong-line anchor matches for one relevant weak line.                |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Called inside weak-line sigma loops. The decision keeps lines covered by strong sidecars out of the   |
    //   weak contribution unless preserve_anchor_weak_lines is enabled.                                       |
    // ------------------------------------------------------------------------------------------------------- |

    if (usesVendorStrongLinePartition(self)) {
        if (self.preserve_anchor_weak_lines) return false;
        if (!Support.isVendorO2AStrongCandidateFromSource(line)) return false;

        return matchedStrongIndexForRelevantLine(self, start_index, line, line_index) != null;
    }

    const strong_index = matchedStrongIndexForRelevantLine(self, start_index, line, line_index) orelse return false;

    if (self.preserve_anchor_weak_lines) return false;
    if (strong_index >= strong_line_anchors.len) return false;
    if (strong_line_anchors[strong_index] == Types.missing_strong_line_anchor_index) return false;

    return @as(usize, @intCast(strong_line_anchors[strong_index])) == line_index;
}

pub fn validateStrongLinePartition(self: *const SpectroscopyLineList) !void {
    // validateStrongLinePartition ----------------------------------------------------------------------      |
    // Reject a vendor O2 strong-line partition that exposes candidates but matches none of them.              |
    //                                                                                                         |
    // call path                                                                                               |
    //   attachStrongLineSidecars and buildStrongLineMatchIndex call this before prepared state is built.      |
    //                                                                                                         |
    // memory                                                                                                  |
    //   Setup-only scan over SpectroscopyLine rows. It reads vendor metadata and center wavelength by pointer.|
    //   The result protects later strong-line state reuse; there is no wavelength-time allocation.            |
    //                                                                                                         |
    // math                                                                                                    |
    //   at least one vendor strong-line candidate must match a sidecar center within tolerance                |
    // ------------------------------------------------------------------------------------------------------- |

    if (!usesVendorStrongLinePartition(self.*)) return;

    const strong_lines = self.strong_lines orelse return;
    if (strong_lines.len > Types.max_strong_line_sidecars) return error.TooManyStrongLineSidecars;

    var saw_candidate = false;
    var matched_candidate = false;
    for (self.lines) |*line| {
        if (!Support.isVendorO2AStrongCandidateFromSource(line)) continue;

        saw_candidate = true;
        _ = findStrongLineMatch(self.*, line.center_wavelength_nm) orelse continue;

        matched_candidate = true;
    }

    if (saw_candidate and !matched_candidate) return error.UnmatchedStrongLineCandidate;
}

pub fn usesVendorStrongLinePartition(self: SpectroscopyLineList) bool {
    return self.hasStrongLineSidecars() and self.vendor_strong_line_partition;
}

pub fn disableStrongLineSidecars(self: *SpectroscopyLineList, allocator: Types.Allocator) void {
    if (self.strong_lines) |strong_lines| allocator.free(strong_lines);
    self.strong_lines = null;
    if (self.relaxation_matrix) |*relaxation_matrix| relaxation_matrix.deinit(allocator);
    self.relaxation_matrix = null;
    if (self.strong_line_match_by_line) |matches| allocator.free(matches);
    self.strong_line_match_by_line = null;
    self.vendor_strong_line_partition = false;
}

fn detectVendorStrongLinePartition(self: SpectroscopyLineList) bool {
    // detectVendorStrongLinePartition -----------------------------------------------------------------       |
    // Detect whether attached sidecars correspond to the vendor O2 A strong-line partition.                   |
    //                                                                                                         |
    // call path                                                                                               |
    //   attachStrongLineSidecars uses this once to choose vendor partition handling before validation.        |
    //                                                                                                         |
    // memory                                                                                                  |
    //   Reads gas_index and vendor metadata from wide line rows by pointer during setup only.                 |
    //   A gas-index side column would not remove wavelength-time work; this decides retained metadata mode.   |
    // ------------------------------------------------------------------------------------------------------- |

    if (!self.hasStrongLineSidecars()) return false;

    if (self.runtime_controls.gas_index) |gas_index| {
        if (gas_index != 7) return false;
    }

    for (self.lines) |*line| {
        if (line.gas_index != 7) continue;
        if (Support.lineHasVendorStrongLineMetadata(line)) return true;
    }

    return false;
}
