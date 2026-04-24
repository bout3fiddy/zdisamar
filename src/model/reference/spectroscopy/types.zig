//! Shared spectroscopy carrier types and constants.

const std = @import("std");

pub const Allocator = std.mem.Allocator;
pub const max_strong_line_sidecars: usize = 128;
pub const hitran_reference_temperature_k = 296.0;
pub const hitran_boltzmann_constant_j_per_k = 1.3806488e-23;
pub const hitran_boltzmann_constant_cm3_hpa_per_k = 1.380658e-19;
pub const hitran_hc_over_kb_cm_k = 1.4387770;
pub const hitran_gas_constant_j_per_mol_k = 8.3144621;
pub const hitran_speed_of_light_m_per_s = 2.99792458e8;
pub const min_spectroscopy_pressure_atm = 1.0e-12;

pub const SpectroscopyLine = struct {
    gas_index: u16 = 0,
    isotope_number: u8 = 1,
    abundance_fraction: f64 = 1.0,
    vendor_filter_metadata_from_source: bool = false,
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

pub const SpectroscopyStrongLineSet = struct {
    lines: []SpectroscopyStrongLine,

    pub fn deinit(self: *SpectroscopyStrongLineSet, allocator: Allocator) void {
        allocator.free(self.lines);
        self.* = undefined;
    }
};

pub const RelaxationMatrix = struct {
    line_count: usize,
    wt0: []f64,
    bw: []f64,

    pub fn deinit(self: *RelaxationMatrix, allocator: Allocator) void {
        allocator.free(self.wt0);
        allocator.free(self.bw);
        self.* = undefined;
    }

    pub fn weightAt(self: RelaxationMatrix, row: usize, col: usize) f64 {
        return self.wt0[row * self.line_count + col];
    }

    pub fn temperatureExponentAt(self: RelaxationMatrix, row: usize, col: usize) f64 {
        return self.bw[row * self.line_count + col];
    }

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
    temperature_exponent: f64 = 0.0,
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

pub const SpectroscopyRuntimeControls = struct {
    gas_index: ?u16 = null,
    active_isotopes: []const u8 = &.{},
    threshold_line_scale: ?f64 = null,
    cutoff_cm1: ?f64 = null,
    cutoff_grid_wavelengths_nm: []const f64 = &.{},
    line_mixing_factor: f64 = 1.0,

    pub fn clone(self: SpectroscopyRuntimeControls, allocator: Allocator) !SpectroscopyRuntimeControls {
        var cloned = SpectroscopyRuntimeControls{
            .gas_index = self.gas_index,
            .threshold_line_scale = self.threshold_line_scale,
            .cutoff_cm1 = self.cutoff_cm1,
            .line_mixing_factor = self.line_mixing_factor,
        };
        errdefer cloned.deinitOwned(allocator);
        if (self.active_isotopes.len != 0) {
            cloned.active_isotopes = try allocator.dupe(u8, self.active_isotopes);
        }
        if (self.cutoff_grid_wavelengths_nm.len != 0) {
            cloned.cutoff_grid_wavelengths_nm = try allocator.dupe(f64, self.cutoff_grid_wavelengths_nm);
        }
        return cloned;
    }

    pub fn deinitOwned(self: *SpectroscopyRuntimeControls, allocator: Allocator) void {
        if (self.active_isotopes.len != 0) allocator.free(self.active_isotopes);
        if (self.cutoff_grid_wavelengths_nm.len != 0) allocator.free(self.cutoff_grid_wavelengths_nm);
        self.* = .{};
    }

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

/// Fallback margin used only when a DISAMAR high-resolution cutoff grid is not
/// available. The exact vendor path chooses nearest grid indices to the cutoff
/// endpoints, then includes both endpoints.
pub const vendor_cutoff_boundary_margin_cm1: f64 = 0.115;

/// PARITY:
///   The sorted prewindow has to be wider than the fallback scalar cutoff
///   because the exact decision is made later against the adaptive HR grid.
pub const vendor_cutoff_prewindow_margin_cm1: f64 = 0.25;

pub const StrongLinePreparedState = struct {
    line_count: usize,
    sig_moy_cm1: f64,
    population_t: []f64,
    dipole_t: []f64,
    mod_sig_cm1: []f64,
    half_width_cm1_at_t: []f64,
    line_mixing_coefficients: []f64,
    relaxation_weights: []f64,

    pub fn deinit(self: *StrongLinePreparedState, allocator: Allocator) void {
        allocator.free(self.population_t);
        allocator.free(self.dipole_t);
        allocator.free(self.mod_sig_cm1);
        allocator.free(self.half_width_cm1_at_t);
        allocator.free(self.line_mixing_coefficients);
        allocator.free(self.relaxation_weights);
        self.* = undefined;
    }

    pub fn weightAt(self: StrongLinePreparedState, row: usize, col: usize) f64 {
        return self.relaxation_weights[row * self.line_count + col];
    }
};
