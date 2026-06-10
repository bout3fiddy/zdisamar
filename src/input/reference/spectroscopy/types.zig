const std = @import("std");

// types.zig ------------------------------------------------------------------------------------------------- |
// Shared spectroscopy data contract: raw line rows, DISAMAR sidecars, runtime controls, and prepared states.  |
//                                                                                                             |
// called by                                                                                                   |
//   ReferenceData.zig re-exports these names as the public reference-data types. ingest/reference_assets      |
//   builds SpectroscopyLine and sidecar rows from retained CSV assets. line_list.zig owns filtering,          |
//   sidecar matching, windowing, and weak/strong sigma entrypoints. optical_properties/state_build prepares   |
//   profile/support states, and carrier_eval.zig reads the prepared arrays at wavelength time.                |
//                                                                                                             |
// main rows                                                                                                   |
//   SpectroscopyLine is the normalized HITRAN/O2 A row kept by SpectroscopyLineList. SpectroscopyStrongLine   |
//   and RelaxationMatrix carry the DISAMAR O2 line-mixing sidecar inputs. SpectroscopyRuntimeControls keeps   |
//   gas/isotope, threshold, cutoff-grid, and line-mixing controls next to the list that consumes them.        |
//   WeakLinePreparedState and StrongLinePreparedState are the exactly-sized retained arrays built for         |
//   profile nodes or support rows.                                                                            |
//                                                                                                             |
// main paths                                                                                                  |
//   CSV/resolved scene rows -> SpectroscopyLine -> SpectroscopyLineList runtime filtering                     |
//   SpectroscopyLineList + T/P -> WeakLinePreparedState and StrongLinePreparedState                           |
//   prepared states + wavelength -> carrier_eval and line_list sigma accumulation                             |
//   SpectroscopyLine rows -> adaptive_plan setup scans for strong-line interval boundaries                    |
//                                                                                                             |
// numbers                                                                                                     |
//   HITRAN and DISAMAR constants here intentionally keep reference literals such as truncated pi and the      |
//   O2 line-mixing hc/kB value. Those last digits are visible in O2 A parity checks.                          |
//                                                                                                             |
// layout                                                                                                      |
//   SpectroscopyLine is a 104 B row. Setup loops may read only center_wavelength_nm at [8..15],               |
//   line_strength_cm2_per_molecule at [24..31], or gas_index at [88..89]; the row stays whole because         |
//   wavelength-time Voigt evaluation consumes the same row's strength, width, energy, isotope, and shift      |
//   fields nearby.                                                                                            |
//                                                                                                             |
// memory                                                                                                      |
//   Line and sidecar rows are inline records copied into owned lists. Prepared states are compact owner       |
//   headers over out-of-line per-line arrays allocated during setup and reused across wavelength-time         |
//   evaluation. Runtime controls can borrow or clone control slices, so the struct owns the matching deinit   |
//   path.                                                                                                     |
// ----------------------------------------------------------------------------------------------------------- |

pub const Allocator = std.mem.Allocator;
pub const max_strong_line_sidecars: usize = 128;
pub const StrongLineAnchorIndex = u32;
pub const missing_strong_line_anchor_index: StrongLineAnchorIndex = std.math.maxInt(StrongLineAnchorIndex);
pub const hitran_reference_temperature_k = 296.0;
pub const hitran_boltzmann_constant_j_per_k = 1.3806488e-23;
pub const hitran_boltzmann_constant_cm3_hpa_per_k = 1.380658e-19;
pub const hitran_hc_over_kb_cm_k = 1.4387770;

// hitran_pi ------------------------------------------------------------------------------------------------- |
// DISAMAR's HITRAN module uses pi = 3.1415926536D0. The truncated literal is visible in O2 A cross-section    |
// parity because it sits inside the Voigt normalization.                                                      |
// ----------------------------------------------------------------------------------------------------------- |
pub const hitran_pi = 3.1415926536;

// hitran_o2_line_mixing_hc_over_kb_cm_k --------------------------------------------------------------------- |
// DISAMAR keeps hc_kB = 1.4387770D0 for ordinary HITRAN absorption, but HITRANModule::ConvTP uses a local     |
// A = 1.43877696D0 when temperature-scaling O2 line-mixing populations. Keep both literals because the        |
// difference is visible at O2 A parity precision.                                                             |
// ----------------------------------------------------------------------------------------------------------- |
pub const hitran_o2_line_mixing_hc_over_kb_cm_k = 1.43877696;
pub const hitran_gas_constant_j_per_mol_k = 8.3144621;
pub const hitran_speed_of_light_m_per_s = 2.99792458e8;
pub const min_spectroscopy_pressure_atm = 1.0e-12;

// SpectroscopyLine ------------------------------------------------------------------------------------------ |
// Parsed HITRAN/O2 A line row after unit normalization and optional vendor metadata retention.                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 104 B (0.102 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] abundance_fraction                  : f64                                                        |
// [  8.. 15] center_wavelength_nm                : f64                                                        |
// [ 16.. 23] center_wavenumber_cm1               : f64                                                        |
// [ 24.. 31] line_strength_cm2_per_molecule      : f64                                                        |
// [ 32.. 39] air_half_width_nm                   : f64                                                        |
// [ 40.. 47] air_half_width_cm1                  : f64                                                        |
// [ 48.. 55] temperature_exponent                : f64                                                        |
// [ 56.. 63] lower_state_energy_cm1              : f64                                                        |
// [ 64.. 71] pressure_shift_nm                   : f64                                                        |
// [ 72.. 79] pressure_shift_cm1                  : f64                                                        |
// [ 80.. 87] line_mixing_coefficient             : f64                                                        |
// [ 88.. 89] gas_index                           : u16                                                        |
// [ 90.. 90] isotope_number                      : u8                                                         |
// [ 91.. 91] vendor_filter_metadata_from_source  : bool                                                       |
// [ 92.. 93] branch_ic1                          : ?u8                                                        |
// [ 94.. 95] branch_ic2                          : ?u8                                                        |
// [ 96.. 97] rotational_nf                       : ?u8                                                        |
// [ 98..103] trailing padding                    : 6 B                                                        |
//                                                                                                             |
// unused bits: 48 padding + 7 bool-storage slack = 55 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 104 B; total = per instance * line count                                          |
//                                                                                                             |
// hot reads                                                                                                   |
//   Setup scans in line_list.zig, adaptive_plan.zig, bundled/assets.zig, and runtime controls read            |
//   center_wavelength_nm at [8..15], line_strength_cm2_per_molecule at [24..31], or gas_index at [88..89]     |
//   by pointer. Wavelength-time evaluation keeps the full row for width, energy, pressure shift, isotope,     |
//   sidecar tags, and line-mixing coefficient.                                                                |
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

// SpectroscopyStrongLine ------------------------------------------------------------------------------------ |
// Strong-line sidecar row used by DISAMAR-style O2 line-mixing evaluation.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] center_wavenumber_cm1 : f64                                                                        |
// [ 8..15] center_wavelength_nm  : f64                                                                        |
// [16..23] population_t0         : f64                                                                        |
// [24..31] dipole_ratio          : f64                                                                        |
// [32..39] dipole_t0             : f64                                                                        |
// [40..47] lower_state_energy_cm1: f64                                                                        |
// [48..55] air_half_width_cm1    : f64                                                                        |
// [56..63] air_half_width_nm     : f64                                                                        |
// [64..71] temperature_exponent  : f64                                                                        |
// [72..79] pressure_shift_cm1    : f64                                                                        |
// [80..87] pressure_shift_nm     : f64                                                                        |
// [88..91] rotational_index_m1   : i32                                                                        |
// [92..95] trailing padding      : 4 B                                                                        |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 96 B; total = per instance * strong-line count                                    |
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

// SpectroscopyStrongLineSet --------------------------------------------------------------------------------- |
// Owned strong-line sidecar slice.                                                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] lines : []SpectroscopyStrongLine                                                                   |
//                                                                                                             |
// out-of-line                                                                                                 |
//   lines owns SpectroscopyStrongLine rows; referenced storage is not included in this header size.           |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B plus owned line storage                                                      |
pub const SpectroscopyStrongLineSet = struct {
    lines: []SpectroscopyStrongLine,

    pub fn deinit(self: *SpectroscopyStrongLineSet, allocator: Allocator) void {
        allocator.free(self.lines);
        self.* = undefined;
    }
};

// RelaxationMatrix ------------------------------------------------------------------------------------------ |
// Strong-line relaxation matrices stored as row-major dense f64 arrays.                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] line_count : usize                                                                                 |
// [ 8..23] wt0        : []f64                                                                                 |
// [24..39] bw         : []f64                                                                                 |
//                                                                                                             |
// out-of-line                                                                                                 |
//   wt0 and bw own line_count * line_count f64 values; referenced storage is not included in this header.     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 40 B plus 2 dense f64 matrices                                                    |
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

// SpectroscopyEvaluation ------------------------------------------------------------------------------------ |
// Accumulated spectroscopy result for one wavelength, temperature, and pressure.                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] weak_line_sigma_cm2_per_molecule           : f64                                                   |
// [ 8..15] strong_line_sigma_cm2_per_molecule         : f64                                                   |
// [16..23] line_sigma_cm2_per_molecule                : f64                                                   |
// [24..31] line_mixing_sigma_cm2_per_molecule         : f64                                                   |
// [32..39] total_sigma_cm2_per_molecule               : f64                                                   |
// [40..47] d_sigma_d_temperature_cm2_per_molecule_per_k : f64                                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 48 B; usually stack returned                                                      |
pub const SpectroscopyEvaluation = struct {
    weak_line_sigma_cm2_per_molecule: f64 = 0.0,
    strong_line_sigma_cm2_per_molecule: f64 = 0.0,
    line_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
    d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
};

// SpectroscopyRuntimeControls ------------------------------------------------------------------------------- |
// Line-list filter and cutoff controls applied before spectroscopy evaluation.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] active_isotopes            : []const u8                                                            |
// [16..31] threshold_line_scale       : ?f64                                                                  |
// [32..47] cutoff_cm1                 : ?f64                                                                  |
// [48..63] cutoff_grid_wavelengths_nm : []const f64                                                           |
// [64..79] cutoff_grid_wavenumbers_cm1: []const f64                                                           |
// [80..87] line_mixing_factor         : f64                                                                   |
// [88..91] gas_index                  : ?u16                                                                  |
// [92..95] trailing padding           : 4 B                                                                   |
//                                                                                                             |
// out-of-line                                                                                                 |
//   active_isotopes and cutoff grids may borrow input storage or own cloned slices, depending on caller.      |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 96 B plus referenced control slices                                               |
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
        // SpectroscopyRuntimeControls.thresholdStrength ---------------------------------------------------   |
        // Return the absolute line-strength cutoff for threshold_line_scale.                                  |
        //                                                                                                     |
        // call path                                                                                           |
        //   adaptive_plan uses this during interval-plan setup before collecting strong-line centers.         |
        //   line_list filtering uses the same value before prepared weak-line windows are built.              |
        //                                                                                                     |
        // memory                                                                                              |
        //   Setup scans read only line_strength_cm2_per_molecule at [24..31] from 104 B SpectroscopyLine      |
        //   rows by pointer. The row stays whole because wavelength-time evaluation consumes the full line    |
        //   fields.                                                                                           |
        //                                                                                                     |
        // math                                                                                                |
        //   cutoff = max(line_strength_cm2_per_molecule) * threshold_line_scale                               |
        // --------------------------------------------------------------------------------------------------- |

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

// vendor_cutoff_prewindow_margin_cm1 ------------------------------------------------------------------------ |
// The sorted prewindow has to be wider than the fallback scalar cutoff because the exact decision is made     |
// later against the adaptive high-resolution grid.                                                            |
// ----------------------------------------------------------------------------------------------------------- |
pub const vendor_cutoff_prewindow_margin_cm1: f64 = 0.25;

// StrongLinePreparedState ----------------------------------------------------------------------------------- |
// Temperature/pressure-prepared strong-line arrays reused by O2 line-mixing evaluation.                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] line_count               : usize                                                                   |
// [ 8..15] sig_moy_cm1              : f64                                                                     |
// [16..31] population_t             : []f64                                                                   |
// [32..47] dipole_t                 : []f64                                                                   |
// [48..63] mod_sig_cm1              : []f64                                                                   |
// [64..79] half_width_cm1_at_t      : []f64                                                                   |
// [80..95] line_mixing_coefficients : []f64                                                                   |
//                                                                                                             |
// out-of-line                                                                                                 |
//   five owned f64 arrays each have line_count elements; referenced storage is not included in this header.   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 96 B plus 5 * line_count f64 values                                               |
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

// WeakLinePreparedLineState --------------------------------------------------------------------------------- |
// Per-line weak-lane constants prepared for one temperature and pressure.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] shifted_center_wavenumber_cm1 : f64                                                                |
// [ 8..15] cte                            : f64                                                               |
// [16..23] line_shape_y                   : f64                                                               |
// [24..31] prefactor_base                 : f64                                                               |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B; total = per instance * weak-line count                                      |
pub const WeakLinePreparedLineState = struct {
    shifted_center_wavenumber_cm1: f64,
    cte: f64,
    line_shape_y: f64,
    prefactor_base: f64,
};

// WeakLinePreparedState ------------------------------------------------------------------------------------- |
// Header over weak-line constants prepared for one temperature and pressure.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] line_count       : usize                                                                           |
// [ 8..15] safe_temperature : f64                                                                             |
// [16..23] safe_pressure    : f64                                                                             |
// [24..39] lines            : []WeakLinePreparedLineState                                                     |
//                                                                                                             |
// out-of-line                                                                                                 |
//   lines owns line_count prepared weak-line rows; referenced storage is not included in this header.         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 40 B plus 32 B * line_count                                                       |
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
