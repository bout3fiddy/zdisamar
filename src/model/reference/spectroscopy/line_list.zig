// Own a spectroscopy line list plus optional strong-line sidecars and runtime
// controls.

const Types = @import("types.zig");

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

        return .{
            .lines = owned_lines,
            .strong_lines = owned_strong_lines,
            .relaxation_matrix = owned_relaxation_matrix,
            .strong_line_tolerance_nm = self.strong_line_tolerance_nm,
            .lines_sorted_ascending = self.lines_sorted_ascending,
            .preserve_anchor_weak_lines = self.preserve_anchor_weak_lines,
            .vendor_strong_line_partition = self.vendor_strong_line_partition,
            .strong_line_match_by_line = if (self.strong_line_match_by_line) |matches|
                try allocator.dupe(?u16, matches)
            else
                null,
            .runtime_controls = try self.runtime_controls.clone(allocator),
        };
    }

    pub fn attachStrongLineSidecars(
        self: *SpectroscopyLineList,
        allocator: Types.Allocator,
        strong_lines: Types.SpectroscopyStrongLineSet,
        relaxation_matrix: Types.RelaxationMatrix,
    ) !void {
        return @import("line_list_ops.zig").attachStrongLineSidecars(self, allocator, strong_lines, relaxation_matrix);
    }

    pub fn buildStrongLineMatchIndex(self: *SpectroscopyLineList, allocator: Types.Allocator) !void {
        return @import("line_list_ops.zig").buildStrongLineMatchIndex(self, allocator);
    }

    pub fn sigmaAt(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) f64 {
        return @import("line_list_eval.zig").totalSigmaAt(self, wavelength_nm, temperature_k, pressure_hpa).total_sigma_cm2_per_molecule;
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
        return @import("line_list_ops.zig").applyRuntimeControls(
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
            return @import("line_list_eval.zig").totalSigmaWithPreparedStrongLineState(
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
            return @import("line_list_eval.zig").totalSigmaWithPreparedStrongLineState(
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
        return @import("line_list_ops.zig").prepareStrongLineState(self, allocator, temperature_k, pressure_hpa);
    }

    pub fn evaluateAt(
        self: SpectroscopyLineList,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) Types.SpectroscopyEvaluation {
        return @import("line_list_eval.zig").evaluateAt(self, wavelength_nm, temperature_k, pressure_hpa);
    }
};
