// Shared spectroscopy carrier types and constants.

const std = @import("std");

pub const Allocator = std.mem.Allocator;
pub const max_strong_line_sidecars: usize = 128;
pub const StrongLineAnchorIndex = u32;
pub const missing_strong_line_anchor_index: StrongLineAnchorIndex = std.math.maxInt(StrongLineAnchorIndex);
pub const hitran_reference_temperature_k = 296.0;
pub const hitran_boltzmann_constant_j_per_k = 1.3806488e-23;
pub const hitran_boltzmann_constant_cm3_hpa_per_k = 1.380658e-19;
pub const hitran_hc_over_kb_cm_k = 1.4387770;
// PARITY:
//   DISAMAR's HITRAN module uses `pi = 3.1415926536D0`, not the full
//   language/library constant. The truncated literal is visible in O2 A
//   cross-section parity because it sits inside the Voigt normalization.
pub const hitran_pi = 3.1415926536;
// PARITY:
//   DISAMAR keeps the module-wide `hc_kB = 1.4387770D0` for ordinary HITRAN
//   absorption but `HITRANModule::ConvTP` uses a local `A = 1.43877696D0`
//   when temperature-scaling O2 line-mixing populations. Keep both constants
//   literal because the difference is visible at O2 A parity precision.
pub const hitran_o2_line_mixing_hc_over_kb_cm_k = 1.43877696;
pub const hitran_gas_constant_j_per_mol_k = 8.3144621;
pub const hitran_speed_of_light_m_per_s = 2.99792458e8;
pub const min_spectroscopy_pressure_atm = 1.0e-12;

// layout(64-bit):
//   size: 104 B, align: 8 B
//   field storage: 98 B across 17 fields; largest: abundance_fraction=8 B, center_wavelength_nm=8 B, center_wavenumber_cm1=8 B; padding: 6 B (48 bits)
//   unused bits: 48 padding + 7 bool-storage slack = 55 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 104 B (0.102 KiB); total = per instance * live instance count
pub const SpectroscopyLine = struct {
    gas_index: u16 = 0,
    isotope_number: u8 = 1,
    abundance_fraction: f64 = 1.0,
    vendor_filter_metadata_from_source: bool = false,
    center_wavelength_nm: f64,
    center_wavenumber_cm1: f64 = std.math.nan(f64),
    line_strength_cm2_per_molecule: f64,
    air_half_width_nm: f64,
    air_half_width_cm1: f64 = std.math.nan(f64),
    temperature_exponent: f64,
    lower_state_energy_cm1: f64,
    pressure_shift_nm: f64,
    pressure_shift_cm1: f64 = std.math.nan(f64),
    line_mixing_coefficient: f64,
    branch_ic1: ?u8 = null,
    branch_ic2: ?u8 = null,
    rotational_nf: ?u8 = null,
};

// layout(64-bit):
//   size: 96 B, align: 8 B
//   field storage: 92 B across 12 fields; largest: center_wavenumber_cm1=8 B, center_wavelength_nm=8 B, population_t0=8 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 96 B (0.094 KiB); total = per instance * live instance count
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

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: lines=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: lines carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
pub const SpectroscopyStrongLineSet = struct {
    lines: []SpectroscopyStrongLine,

    pub fn deinit(self: *SpectroscopyStrongLineSet, allocator: Allocator) void {
        allocator.free(self.lines);
        self.* = undefined;
    }
};

// layout(64-bit):
//   size: 40 B, align: 8 B
//   field storage: line_count=8 B, wt0=16 B, bw=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: wt0, bw carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 40 B (0.039 KiB); total also includes referenced storage above
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

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: 48 B across 6 fields; largest: weak_line_sigma_cm2_per_molecule=8 B, strong_line_sigma_cm2_per_molecule=8 B, line_sigma_cm2_per_molecule=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total = per instance * live instance count
pub const SpectroscopyEvaluation = struct {
    weak_line_sigma_cm2_per_molecule: f64 = 0.0,
    strong_line_sigma_cm2_per_molecule: f64 = 0.0,
    line_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
    d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
};

// layout(64-bit):
//   size: 96 B, align: 8 B
//   field storage: 92 B across 7 fields; largest: active_isotopes=16 B, threshold_line_scale=16 B, cutoff_cm1=16 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   out-of-line: active_isotopes, cutoff_grid_wavelengths_nm, cutoff_grid_wavenumbers_cm1 carry references/descriptors; referenced storage is not included in size
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 96 B (0.094 KiB); total also includes referenced storage above
pub const SpectroscopyRuntimeControls = struct {
    gas_index: ?u16 = null,
    active_isotopes: []const u8 = &.{},
    threshold_line_scale: ?f64 = null,
    cutoff_cm1: ?f64 = null,
    cutoff_grid_wavelengths_nm: []const f64 = &.{},
    cutoff_grid_wavenumbers_cm1: []const f64 = &.{},
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
        if (self.cutoff_grid_wavenumbers_cm1.len != 0) {
            cloned.cutoff_grid_wavenumbers_cm1 = try allocator.dupe(f64, self.cutoff_grid_wavenumbers_cm1);
        }
        return cloned;
    }

    pub fn deinitOwned(self: *SpectroscopyRuntimeControls, allocator: Allocator) void {
        if (self.active_isotopes.len != 0) allocator.free(self.active_isotopes);
        if (self.cutoff_grid_wavelengths_nm.len != 0) allocator.free(self.cutoff_grid_wavelengths_nm);
        if (self.cutoff_grid_wavenumbers_cm1.len != 0) allocator.free(self.cutoff_grid_wavenumbers_cm1);
        self.* = .{};
    }

    pub fn thresholdStrength(self: SpectroscopyRuntimeControls, lines: []const SpectroscopyLine) ?f64 {
        const scale = self.threshold_line_scale orelse return null;
        if (lines.len == 0) return null;

        var max_strength: f64 = 0.0;
        for (lines) |*line| {
            max_strength = @max(max_strength, line.line_strength_cm2_per_molecule);
        }
        return max_strength * scale;
    }
};

// Fallback margin used only when a DISAMAR high-resolution cutoff grid is not
// available. The exact vendor path chooses nearest grid indices to the cutoff
// endpoints, then includes both endpoints.
pub const vendor_cutoff_boundary_margin_cm1: f64 = 0.115;

// PARITY:
//   The sorted prewindow has to be wider than the fallback scalar cutoff
//   because the exact decision is made later against the adaptive HR grid.
pub const vendor_cutoff_prewindow_margin_cm1: f64 = 0.25;

// layout(64-bit):
//   size: 96 B, align: 8 B
//   field storage: 96 B across 7 fields; largest: population_t=16 B, dipole_t=16 B, mod_sig_cm1=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: population_t, dipole_t, mod_sig_cm1, half_width_cm1_at_t, line_mixing_coefficients carry references/descriptors; referenced storage is not included in size
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 96 B (0.094 KiB); total also includes referenced storage above
pub const StrongLinePreparedState = struct {
    line_count: usize,
    sig_moy_cm1: f64,
    population_t: []f64,
    dipole_t: []f64,
    mod_sig_cm1: []f64,
    half_width_cm1_at_t: []f64,
    line_mixing_coefficients: []f64,

    pub fn deinit(self: *StrongLinePreparedState, allocator: Allocator) void {
        allocator.free(self.population_t);
        allocator.free(self.dipole_t);
        allocator.free(self.mod_sig_cm1);
        allocator.free(self.half_width_cm1_at_t);
        allocator.free(self.line_mixing_coefficients);
        self.* = undefined;
    }
};

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: 32 B across 4 fields; largest: shifted_center_wavenumber_cm1=8 B, cte=8 B, line_shape_y=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count
pub const WeakLinePreparedLineState = struct {
    shifted_center_wavenumber_cm1: f64,
    cte: f64,
    line_shape_y: f64,
    prefactor_base: f64,
};

// layout(64-bit):
//   size: 40 B, align: 8 B
//   field storage: 40 B across 4 fields; largest: lines=16 B, line_count=8 B, safe_temperature=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: lines carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 40 B (0.039 KiB); total also includes referenced storage above
pub const WeakLinePreparedState = struct {
    line_count: usize,
    safe_temperature: f64 = 0.0,
    safe_pressure: f64 = 0.0,
    lines: []WeakLinePreparedLineState,

    pub fn deinit(self: *WeakLinePreparedState, allocator: Allocator) void {
        allocator.free(self.lines);
        self.* = undefined;
    }
};
