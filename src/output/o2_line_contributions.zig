const std = @import("std");

const hitran_partition_tables = @import("../input/hitran_partition_tables.zig");
const o2_run_tables = @import("../setup/o2_run_tables.zig");
const readers = @import("../assets/readers.zig");

const Allocator = std.mem.Allocator;

const hitran_reference_temperature_k = 296.0;
const hitran_boltzmann_constant_j_per_k = 1.3806488e-23;
const hitran_boltzmann_constant_cm3_hpa_per_k = 1.380658e-19;
const hitran_hc_over_kb_cm_k = 1.4387770;
const hitran_gas_constant_j_per_mol_k = 8.3144621;
const hitran_speed_of_light_m_per_s = 2.99792458e8;
const hitran_pi = 3.1415926536;
const min_hitran_temperature_k = 150.0;
const min_spectroscopy_pressure_atm = 1.0e-12;
const max_strong_line_sidecars: usize = 128;
const missing_index = std.math.maxInt(u32);
const vendor_cutoff_boundary_margin_cm1 = 0.115;
const vendor_cutoff_prewindow_margin_cm1 = 0.25;

// o2_line_contributions.zig ----------------------------------------------------------------------------------|
// Public O2 line-by-line diagnostic rows for selected wavelengths and spectroscopy profile nodes.             |
//                                                                                                             |
// boundary                                                                                                    |
//   The builder renders explanation rows from prepared setup tables into the fixed Python C ABI row order.    |
//   It does not parse inputs, own C handles, call transport, or feed the forward solve.                       |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/output/o2_line_contributions.zig` over the explicit WP2/WP3 setup rows. The scalar weak   |
//   line and ConvTP sidecar math mirrors `src/cache/profile_line_memory.zig`, which carries the setup-time    |
//   spectroscopy port.                                                                                        |
//                                                                                                             |
// row order                                                                                                   |
//   wavelength-major -> spectroscopy profile node -> relevant weak-line window -> strong-line sidecars.       |
//                                                                                                             |
// memory                                                                                                      |
//   `rows` owns at most max_rows records. `total_row_count` always reports the full untruncated diagnostic    |
//   row count so Python can distinguish a short materialized table from a short route.                        |
// ------------------------------------------------------------------------------------------------------------|

// O2LineRowKind ----------------------------------------------------------------------------------------------|
// Public row kind labels used by python/zdisamar/output/tables.py.                                            |
pub const O2LineRowKind = enum(u32) {
    weak_line = 0,
    strong_line = 1,
};
// ------------------------------------------------------------------------------------------------------------|

// O2LineStatus -----------------------------------------------------------------------------------------------|
// Public row status labels used by python/zdisamar/output/tables.py.                                          |
pub const O2LineStatus = enum(u32) {
    weak_included = 0,
    weak_excluded_by_strong_line = 1,
    strong_sidecar = 2,
    weak_zero_after_cutoff = 3,
};
// ------------------------------------------------------------------------------------------------------------|

// O2LineContributionRow --------------------------------------------------------------------------------------|
// One public O2 spectroscopy diagnostic row for one wavelength and thermodynamic profile node.                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 168 B (0.164 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] wavelength_nm                      : f64                                                         |
// [  8.. 11] profile_node_index                 : u32                                                         |
// [ 12.. 15] padding                            : 4 B                                                         |
// [ 16.. 23] altitude_km                        : f64                                                         |
// [ 24.. 27] row_kind                           : O2LineRowKind                                               |
// [ 28.. 31] status                             : O2LineStatus                                                |
// [ 32.. 35] line_index                         : u32                                                         |
// [ 36.. 39] strong_line_index                  : u32                                                         |
// [ 40.. 43] matched_strong_line_index          : u32                                                         |
// [ 44.. 45] gas_index                          : u16                                                         |
// [ 46.. 46] isotope_number                     : u8                                                          |
// [ 47.. 47] padding                            : 1 B                                                         |
// [ 48.. 51] isotopologue_code                  : i32                                                         |
// [ 52.. 55] padding                            : 4 B                                                         |
// [ 56.. 63] center_wavelength_nm               : f64                                                         |
// [ 64.. 71] center_wavenumber_cm1              : f64                                                         |
// [ 72.. 79] shifted_center_wavenumber_cm1      : f64                                                         |
// [ 80.. 87] line_strength_cm2_per_molecule     : f64                                                         |
// [ 88.. 95] air_half_width_cm1                 : f64                                                         |
// [ 96..103] pressure_shift_cm1                 : f64                                                         |
// [104..111] lower_state_energy_cm1             : f64                                                         |
// [112..119] temperature_k                      : f64                                                         |
// [120..127] pressure_hpa                       : f64                                                         |
// [128..135] weak_line_sigma_cm2_per_molecule   : f64                                                         |
// [136..143] strong_line_sigma_cm2_per_molecule : f64                                                         |
// [144..151] line_mixing_sigma_cm2_per_molecule : f64                                                         |
// [152..159] total_sigma_cm2_per_molecule       : f64                                                         |
// [160..167] abs_total_sigma_cm2_per_molecule   : f64                                                         |
pub const O2LineContributionRow = extern struct {
    wavelength_nm: f64,
    profile_node_index: u32,
    altitude_km: f64,
    row_kind: O2LineRowKind,
    status: O2LineStatus,
    line_index: u32,
    strong_line_index: u32,
    matched_strong_line_index: u32,
    gas_index: u16,
    isotope_number: u8,
    isotopologue_code: i32,
    center_wavelength_nm: f64,
    center_wavenumber_cm1: f64,
    shifted_center_wavenumber_cm1: f64,
    line_strength_cm2_per_molecule: f64,
    air_half_width_cm1: f64,
    pressure_shift_cm1: f64,
    lower_state_energy_cm1: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    weak_line_sigma_cm2_per_molecule: f64,
    strong_line_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
    abs_total_sigma_cm2_per_molecule: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// O2LineContributions ----------------------------------------------------------------------------------------|
// Owned O2 spectroscopy diagnostic table returned through root/API calls.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] rows            : []O2LineContributionRow                                                          |
// [16..23] total_row_count : usize                                                                            |
// [24..24] truncated       : bool                                                                             |
// [25..31] padding         : 7 B                                                                              |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns min(total_row_count, max_rows) records.                                                         |
pub const O2LineContributions = struct {
    rows: []O2LineContributionRow = &.{},
    total_row_count: usize = 0,
    truncated: bool = false,

    pub fn deinit(self: *O2LineContributions, allocator: Allocator) void {
        // O2LineContributions.deinit -------------------------------------------------------------------------|
        // Release materialized diagnostic rows.                                                               |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

const ThermodynamicState = struct {
    profile_node_index: u32,
    altitude_km: f64,
    temperature_k: f64,
    pressure_hpa: f64,
};

const RuntimeControls = struct {
    cutoff_cm1: f64,
    line_mixing_factor: f64,
};

const RuntimeLine = struct {
    line: readers.O2LineAssetRow,
    line_index: u32,
};

const LineWindow = struct {
    lines: []const RuntimeLine,
};

const SpectroscopyComponents = struct {
    weak_line_sigma_cm2_per_molecule: f64 = 0.0,
    strong_line_sigma_cm2_per_molecule: f64 = 0.0,
    line_sigma_cm2_per_molecule: f64 = 0.0,
    line_mixing_sigma_cm2_per_molecule: f64 = 0.0,
    total_sigma_cm2_per_molecule: f64 = 0.0,
};

const StrongLinePreparedState = struct {
    line_count: usize = 0,
    sig_moy_cm1: f64 = 0.0,
    population_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    dipole_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    mod_sig_cm1: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    half_width_cm1_at_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    line_mixing_coefficients: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
};

const ComplexProbability = struct {
    wr: f64,
    wi: f64,
};

const StrongAnchorFields = struct {
    line_index: u32,
    gas_index: u16,
    isotope_number: u8,
    isotopologue_code: i32,
    line_strength_cm2_per_molecule: f64,
};

const StrongAnchorMatch = struct {
    line: *const readers.O2LineAssetRow,
    line_index: u32,
};

pub fn build(
    allocator: Allocator,
    tables: *const o2_run_tables.O2RunTables,
    wavelengths_nm: []const f64,
    max_rows: usize,
) !O2LineContributions {
    // build --------------------------------------------------------------------------------------------------|
    // Build public O2 line-contribution diagnostics for caller-selected wavelengths.                          |
    //                                                                                                         |
    // memory                                                                                                  |
    //   Allocates one output table capped by max_rows; all spectroscopy rows and profile nodes are borrowed   |
    //   from O2RunTables.                                                                                     |
    // --------------------------------------------------------------------------------------------------------|
    if (wavelengths_nm.len == 0) return error.EmptyWavelengths;
    if (max_rows == 0) return error.InvalidRowLimit;

    const runtime = RuntimeControls{
        .cutoff_cm1 = tables.lines.cutoff_sim_cm1,
        .line_mixing_factor = tables.lines.line_mixing_factor,
    };
    const runtime_lines = try collectRuntimeLines(allocator, tables.lines.rows, tables.lines.isotopes_sim);
    defer allocator.free(runtime_lines);
    const strong_line_count = @min(tables.lines.strong_lines.len, max_strong_line_sidecars);
    var rows = std.ArrayList(O2LineContributionRow).empty;
    errdefer rows.deinit(allocator);
    try rows.ensureTotalCapacity(allocator, @min(max_rows, runtime_lines.len + strong_line_count));
    var window_rows = std.ArrayList(RuntimeLine).empty;
    defer window_rows.deinit(allocator);

    var total_row_count: usize = 0;
    for (wavelengths_nm) |wavelength_nm| {
        const window = try relevantLineWindow(
            allocator,
            &window_rows,
            runtime_lines,
            wavelength_nm,
            runtime.cutoff_cm1,
        );
        for (tables.layers.spectroscopy_profile.rows, 0..) |profile_row, profile_node_index| {
            try appendRowsForState(
                allocator,
                &rows,
                &total_row_count,
                max_rows,
                tables,
                window,
                runtime,
                wavelength_nm,
                .{
                    .profile_node_index = @intCast(profile_node_index),
                    .altitude_km = profile_row.altitude_km,
                    .temperature_k = profile_row.temperature_k,
                    .pressure_hpa = profile_row.pressure_hpa,
                },
            );
        }
    }

    return .{
        .rows = try rows.toOwnedSlice(allocator),
        .total_row_count = total_row_count,
        .truncated = total_row_count > max_rows,
    };
}

fn appendRowsForState(
    allocator: Allocator,
    rows: *std.ArrayList(O2LineContributionRow),
    total_row_count: *usize,
    max_rows: usize,
    tables: *const o2_run_tables.O2RunTables,
    window: LineWindow,
    runtime: RuntimeControls,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
) !void {
    // appendRowsForState -------------------------------------------------------------------------------------|
    // Append weak-line rows and strong-line sidecar rows for one wavelength/profile-node state.               |
    // --------------------------------------------------------------------------------------------------------|
    const pressure_atm = @max(thermodynamic_state.pressure_hpa / 1013.25, min_spectroscopy_pressure_atm);
    const safe_temperature = @max(thermodynamic_state.temperature_k, min_hitran_temperature_k);
    const vendor_partition = usesVendorStrongLinePartition(window.lines, tables.lines.strong_lines);

    for (window.lines, 0..) |runtime_line, line_index| {
        total_row_count.* += 1;
        if (rows.items.len >= max_rows) continue;
        try rows.append(allocator, weakLineRow(
            tables.lines.strong_lines,
            window,
            wavelength_nm,
            thermodynamic_state,
            safe_temperature,
            pressure_atm,
            runtime_line,
            line_index,
            vendor_partition,
            runtime,
        ));
    }

    const strong_state = prepareStrongLineState(
        tables.lines.strong_lines,
        tables.lines.relaxation_matrix,
        safe_temperature,
        pressure_atm,
    );
    for (tables.lines.strong_lines[0..strong_state.line_count], 0..) |strong_line, strong_index| {
        total_row_count.* += 1;
        if (rows.items.len >= max_rows) continue;
        try rows.append(allocator, strongLineRow(
            tables.lines.strong_lines,
            strong_line,
            strong_index,
            window,
            wavelength_nm,
            thermodynamic_state,
            safe_temperature,
            pressure_atm,
            runtime,
            vendor_partition,
            &strong_state,
        ));
    }
}

fn weakLineRow(
    strong_lines: []const readers.O2StrongLineAssetRow,
    window: LineWindow,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
    temperature_k: f64,
    pressure_atm: f64,
    runtime_line: RuntimeLine,
    line_index: usize,
    vendor_partition: bool,
    runtime: RuntimeControls,
) O2LineContributionRow {
    // weakLineRow --------------------------------------------------------------------------------------------|
    // Project one HITRAN weak-line row and its old-route inclusion status into the public diagnostic shape.   |
    // --------------------------------------------------------------------------------------------------------|
    const line = runtime_line.line;
    const matched_strong_index = matchedStrongIndexForRelevantLine(strong_lines, line, vendor_partition);
    const excluded = shouldExcludeWeakLine(line, line_index, window.lines, strong_lines, vendor_partition);

    var weak_sigma: f64 = 0.0;
    var status: O2LineStatus = .weak_excluded_by_strong_line;
    if (!excluded) {
        weak_sigma = weakLineContribution(wavelength_nm, line, temperature_k, pressure_atm, runtime);
        status = if (weak_sigma == 0.0) .weak_zero_after_cutoff else .weak_included;
    }
    const matched_strong_line_index: u32 = if (matched_strong_index) |index| @intCast(index) else missing_index;

    return .{
        .wavelength_nm = wavelength_nm,
        .profile_node_index = thermodynamic_state.profile_node_index,
        .altitude_km = thermodynamic_state.altitude_km,
        .row_kind = .weak_line,
        .status = status,
        .line_index = runtime_line.line_index,
        .strong_line_index = missing_index,
        .matched_strong_line_index = matched_strong_line_index,
        .gas_index = line.gas_index,
        .isotope_number = line.isotope_number,
        .isotopologue_code = deriveIsotopologueCode(line.gas_index, line.isotope_number),
        .center_wavelength_nm = line.center_wavelength_nm,
        .center_wavenumber_cm1 = line.center_wavenumber_cm1,
        .shifted_center_wavenumber_cm1 = shiftedCenterWavenumberCm1(line, pressure_atm),
        .line_strength_cm2_per_molecule = line.line_strength_cm2_per_molecule,
        .air_half_width_cm1 = line.air_half_width_cm1,
        .pressure_shift_cm1 = line.pressure_shift_cm1,
        .lower_state_energy_cm1 = line.lower_state_energy_cm1,
        .temperature_k = temperature_k,
        .pressure_hpa = thermodynamic_state.pressure_hpa,
        .weak_line_sigma_cm2_per_molecule = weak_sigma,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = weak_sigma,
        .abs_total_sigma_cm2_per_molecule = @abs(weak_sigma),
    };
}

fn strongLineRow(
    strong_lines: []const readers.O2StrongLineAssetRow,
    strong_line: readers.O2StrongLineAssetRow,
    strong_index: usize,
    window: LineWindow,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
    temperature_k: f64,
    pressure_atm: f64,
    runtime: RuntimeControls,
    vendor_partition: bool,
    strong_state: *const StrongLinePreparedState,
) O2LineContributionRow {
    // strongLineRow ------------------------------------------------------------------------------------------|
    // Project one LISA strong-line sidecar row and its weak-line anchor metadata into the public table.       |
    // --------------------------------------------------------------------------------------------------------|
    const contribution = strongLineContribution(wavelength_nm, strong_index, strong_state, temperature_k, pressure_atm);
    const line_mixing_sigma = contribution.line_mixing_sigma_cm2_per_molecule * runtime.line_mixing_factor;
    const total_sigma = @max(contribution.strong_line_sigma_cm2_per_molecule + line_mixing_sigma, 0.0);
    const anchor = strongAnchorLine(strong_lines, window, strong_index, vendor_partition);
    const anchor_fields = resolveStrongAnchorFields(anchor);

    return .{
        .wavelength_nm = wavelength_nm,
        .profile_node_index = thermodynamic_state.profile_node_index,
        .altitude_km = thermodynamic_state.altitude_km,
        .row_kind = .strong_line,
        .status = .strong_sidecar,
        .line_index = anchor_fields.line_index,
        .strong_line_index = @intCast(strong_index),
        .matched_strong_line_index = @intCast(strong_index),
        .gas_index = anchor_fields.gas_index,
        .isotope_number = anchor_fields.isotope_number,
        .isotopologue_code = anchor_fields.isotopologue_code,
        .center_wavelength_nm = strong_line.center_wavelength_nm,
        .center_wavenumber_cm1 = strong_line.center_wavenumber_cm1,
        .shifted_center_wavenumber_cm1 = strong_state.mod_sig_cm1[strong_index],
        .line_strength_cm2_per_molecule = anchor_fields.line_strength_cm2_per_molecule,
        .air_half_width_cm1 = strong_line.air_half_width_cm1,
        .pressure_shift_cm1 = strong_line.pressure_shift_cm1,
        .lower_state_energy_cm1 = strong_line.lower_state_energy_cm1,
        .temperature_k = temperature_k,
        .pressure_hpa = thermodynamic_state.pressure_hpa,
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = contribution.strong_line_sigma_cm2_per_molecule,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = total_sigma,
        .abs_total_sigma_cm2_per_molecule = @abs(total_sigma),
    };
}

fn resolveStrongAnchorFields(anchor: ?StrongAnchorMatch) StrongAnchorFields {
    // resolveStrongAnchorFields ------------------------------------------------------------------------------|
    // Copy weak-line metadata for sidecars, or keep the old complete-row O2 defaults when no anchor exists.   |
    // --------------------------------------------------------------------------------------------------------|
    if (anchor) |owned| {
        return .{
            .line_index = owned.line_index,
            .gas_index = owned.line.gas_index,
            .isotope_number = owned.line.isotope_number,
            .isotopologue_code = deriveIsotopologueCode(owned.line.gas_index, owned.line.isotope_number),
            .line_strength_cm2_per_molecule = owned.line.line_strength_cm2_per_molecule,
        };
    }

    return .{
        .line_index = missing_index,
        .gas_index = 7,
        .isotope_number = 1,
        .isotopologue_code = 66,
        .line_strength_cm2_per_molecule = std.math.nan(f64),
    };
}

fn strongAnchorLine(
    strong_lines: []const readers.O2StrongLineAssetRow,
    window: LineWindow,
    strong_index: usize,
    vendor_partition: bool,
) ?StrongAnchorMatch {
    // strongAnchorLine ---------------------------------------------------------------------------------------|
    // Find the weak-line row attached to one strong sidecar within the current relevant window.               |
    // --------------------------------------------------------------------------------------------------------|
    if (vendor_partition) return null;
    if (strong_index >= strong_lines.len) return null;
    const strong_line = strong_lines[strong_index];
    var best_index: ?usize = null;
    var best_delta = std.math.inf(f64);
    var best_strength: f64 = -std.math.inf(f64);

    for (window.lines, 0..) |runtime_line, line_index| {
        const line = runtime_line.line;
        const delta = @abs(strong_line.center_wavelength_nm - line.center_wavelength_nm);
        const tolerance_nm = @max(0.01, strong_line.air_half_width_nm * 4.0);

        if (delta > tolerance_nm) continue;
        if (delta > best_delta) continue;
        if (delta == best_delta and line.line_strength_cm2_per_molecule < best_strength) continue;

        best_index = line_index;
        best_delta = delta;
        best_strength = line.line_strength_cm2_per_molecule;
    }

    const index = best_index orelse return null;
    return .{ .line = &window.lines[index].line, .line_index = window.lines[index].line_index };
}

fn relevantLineWindow(
    allocator: Allocator,
    rows: *std.ArrayList(RuntimeLine),
    lines: []const RuntimeLine,
    wavelength_nm: f64,
    cutoff_cm1: f64,
) !LineWindow {
    // relevantLineWindow -------------------------------------------------------------------------------------|
    // Fill a wavelength-local weak-line prewindow, preserving old filtered source order for equal centers.    |
    // --------------------------------------------------------------------------------------------------------|
    rows.clearRetainingCapacity();
    if (lines.len == 0) return .{ .lines = rows.items };

    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const prewindow_cm1 = cutoff_cm1 + vendor_cutoff_prewindow_margin_cm1;
    const lower_wavenumber_cm1 = @max(evaluation_wavenumber_cm1 - prewindow_cm1, 1.0);
    const upper_wavenumber_cm1 = evaluation_wavenumber_cm1 + prewindow_cm1;
    const lower_wavelength_nm = wavenumberToWavelengthNm(upper_wavenumber_cm1);
    const upper_wavelength_nm = wavenumberToWavelengthNm(lower_wavenumber_cm1);
    for (lines) |line| {
        const center_wavelength_nm = line.line.center_wavelength_nm;
        if (center_wavelength_nm < lower_wavelength_nm or center_wavelength_nm >= upper_wavelength_nm) continue;
        try rows.append(allocator, line);
    }
    return .{ .lines = rows.items };
}

fn collectRuntimeLines(
    allocator: Allocator,
    lines: []const readers.O2LineAssetRow,
    active_isotopes: []const u8,
) ![]RuntimeLine {
    // collectRuntimeLines ------------------------------------------------------------------------------------|
    // Copy O2 rows that participate in old diagnostic evaluation, without applying the weak-line threshold.   |
    // --------------------------------------------------------------------------------------------------------|
    var active_count: usize = 0;
    for (lines) |line| {
        if (runtimeLine(line, active_isotopes)) active_count += 1;
    }

    const active_lines = try allocator.alloc(RuntimeLine, active_count);
    errdefer allocator.free(active_lines);

    var active_index: usize = 0;
    for (lines) |line| {
        if (!runtimeLine(line, active_isotopes)) continue;
        active_lines[active_index] = .{ .line = line, .line_index = @intCast(active_index) };
        active_index += 1;
    }

    std.sort.pdq(RuntimeLine, active_lines, {}, lessRuntimeLineByCenter);
    for (active_lines, 0..) |*line, sorted_index| {
        line.line_index = @intCast(sorted_index);
    }
    return active_lines;
}

fn lessRuntimeLineByCenter(_: void, lhs: RuntimeLine, rhs: RuntimeLine) bool {
    // lessRuntimeLineByCenter --------------------------------------------------------------------------------|
    // Match old sortLineList: pdq sort by center wavelength only. Equal-center ordering is the pdq result.    |
    // --------------------------------------------------------------------------------------------------------|
    return lhs.line.center_wavelength_nm < rhs.line.center_wavelength_nm;
}

fn runtimeLine(line: readers.O2LineAssetRow, active_isotopes: []const u8) bool {
    // runtimeLine --------------------------------------------------------------------------------------------|
    // Apply the old total-sigma gas/isotope controls without the weak-line threshold filter.                  |
    // --------------------------------------------------------------------------------------------------------|
    if (line.gas_index != 7) return false;
    if (active_isotopes.len == 0) return true;
    for (active_isotopes) |isotope_number| {
        if (line.isotope_number == isotope_number) return true;
    }
    return false;
}

fn usesVendorStrongLinePartition(
    lines: []const RuntimeLine,
    strong_lines: []const readers.O2StrongLineAssetRow,
) bool {
    // usesVendorStrongLinePartition --------------------------------------------------------------------------|
    // Detect the old O2 A sidecar partition from retained HITRAN branch metadata.                             |
    // --------------------------------------------------------------------------------------------------------|
    if (strong_lines.len == 0) return false;

    for (lines) |runtime_line| {
        const line = runtime_line.line;
        if (line.gas_index == 7 and
            line.branch_ic1 != null and
            line.branch_ic2 != null and
            line.rotational_nf != null)
        {
            return true;
        }
    }
    return false;
}

fn matchedStrongIndexForRelevantLine(
    strong_lines: []const readers.O2StrongLineAssetRow,
    line: readers.O2LineAssetRow,
    vendor_partition: bool,
) ?usize {
    // matchedStrongIndexForRelevantLine ----------------------------------------------------------------------|
    // Report the sidecar index associated with a weak line when the old partition rules assign one.           |
    // --------------------------------------------------------------------------------------------------------|
    if (vendor_partition and !isVendorO2AStrongCandidateFromSource(line)) return null;
    return findStrongLineMatch(strong_lines, line.center_wavelength_nm);
}

fn shouldExcludeWeakLine(
    line: readers.O2LineAssetRow,
    line_index: usize,
    window: []const RuntimeLine,
    strong_lines: []const readers.O2StrongLineAssetRow,
    vendor_partition: bool,
) bool {
    // shouldExcludeWeakLine ----------------------------------------------------------------------------------|
    // Keep lines covered by old O2 strong-line sidecars out of the weak-line contribution.                    |
    // --------------------------------------------------------------------------------------------------------|
    if (vendor_partition) {
        if (!isVendorO2AStrongCandidateFromSource(line)) return false;
        return findStrongLineMatch(strong_lines, line.center_wavelength_nm) != null;
    }

    const strong_index = findStrongLineMatch(strong_lines, line.center_wavelength_nm) orelse return false;
    return strongestWindowAnchorForSidecar(window, strong_lines[strong_index]) == line_index;
}

fn strongestWindowAnchorForSidecar(
    window: []const RuntimeLine,
    strong_line: readers.O2StrongLineAssetRow,
) usize {
    // strongestWindowAnchorForSidecar ------------------------------------------------------------------------|
    // Select the old generic sidecar anchor: closest line center, then strongest line on an equal delta.      |
    // --------------------------------------------------------------------------------------------------------|
    var best_index: usize = 0;
    var best_delta = std.math.inf(f64);
    var best_strength: f64 = -std.math.inf(f64);

    for (window, 0..) |runtime_line, line_index| {
        const line = runtime_line.line;
        const delta = @abs(strong_line.center_wavelength_nm - line.center_wavelength_nm);
        const tolerance_nm = @max(0.01, strong_line.air_half_width_nm * 4.0);

        if (delta > tolerance_nm) continue;
        if (delta > best_delta) continue;
        if (delta == best_delta and line.line_strength_cm2_per_molecule < best_strength) continue;

        best_index = line_index;
        best_delta = delta;
        best_strength = line.line_strength_cm2_per_molecule;
    }
    return best_index;
}

fn findStrongLineMatch(strong_lines: []const readers.O2StrongLineAssetRow, wavelength_nm: f64) ?usize {
    // findStrongLineMatch ------------------------------------------------------------------------------------|
    // Return the closest LISA sidecar center within the old tolerance rule.                                   |
    // --------------------------------------------------------------------------------------------------------|
    var best_index: ?usize = null;
    var best_delta = std.math.inf(f64);
    for (strong_lines, 0..) |strong_line, strong_index| {
        const delta = @abs(strong_line.center_wavelength_nm - wavelength_nm);
        const tolerance_nm = @max(0.01, strong_line.air_half_width_nm * 4.0);
        if (delta > tolerance_nm or delta >= best_delta) continue;
        best_index = strong_index;
        best_delta = delta;
    }
    return best_index;
}

fn isVendorO2AStrongCandidateFromSource(line: readers.O2LineAssetRow) bool {
    // isVendorO2AStrongCandidateFromSource -------------------------------------------------------------------|
    // Match old support.zig: only source-marked O2 isotope-1 P-branch rows participate in vendor partition.   |
    // --------------------------------------------------------------------------------------------------------|
    return line.vendor_filter_metadata_from_source and
        line.gas_index == 7 and
        line.isotope_number == 1 and
        line.branch_ic1 != null and
        line.branch_ic2 != null and
        line.rotational_nf != null and
        line.branch_ic1.? == 5 and
        line.branch_ic2.? == 1 and
        line.rotational_nf.? <= 35;
}

fn weakLineContribution(
    wavelength_nm: f64,
    line: readers.O2LineAssetRow,
    temperature_k: f64,
    pressure_atm: f64,
    runtime: RuntimeControls,
) f64 {
    // weakLineContribution -----------------------------------------------------------------------------------|
    // Evaluate one HITRAN weak-line contribution with the old scalar cutoff and CPF route.                    |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Mirrors `src/cache/profile_line_memory.zig` and main:`src/input/reference/spectroscopy/physics_core.zig`.
    // --------------------------------------------------------------------------------------------------------|
    if (!insideCutoff(line, wavelength_nm, pressure_atm, runtime)) return 0.0;

    const shifted_center_wavenumber_cm1 = shiftedCenterWavenumberCm1(line, pressure_atm);
    const temperature_ratio = hitran_reference_temperature_k / temperature_k;
    const half_width_cm1_at_t = @max(
        line.air_half_width_cm1 * std.math.pow(f64, temperature_ratio, line.temperature_exponent),
        1.0e-6,
    );
    const doppler_width_cm1 = @max(
        dopplerWidthCm1(temperature_k, shifted_center_wavenumber_cm1, molecularWeightForLine(line)),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / doppler_width_cm1;
    const line_shape_y = half_width_cm1_at_t * pressure_atm * cte;

    var converted_strength = line.line_strength_cm2_per_molecule *
        partitionRatioT0OverT(line, temperature_k) *
        @exp(
            hitran_hc_over_kb_cm_k * line.lower_state_energy_cm1 *
                ((1.0 / hitran_reference_temperature_k) - (1.0 / temperature_k)),
        ) /
        shifted_center_wavenumber_cm1;
    converted_strength *= 0.1013 /
        hitran_boltzmann_constant_j_per_k /
        temperature_k /
        @max(
            1.0 - @exp(-hitran_hc_over_kb_cm_k * shifted_center_wavenumber_cm1 / hitran_reference_temperature_k),
            1.0e-12,
        );

    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const cpf = complexProbabilityFunction(
        (shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1) * cte,
        line_shape_y,
    );
    const stimulated_emission_scale = evaluation_wavenumber_cm1 *
        (1.0 - @exp(-hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / temperature_k));
    const prefactor = @sqrt(@log(2.0)) /
        doppler_width_cm1 /
        @sqrt(hitran_pi) *
        pressure_atm *
        converted_strength *
        stimulated_emission_scale *
        temperature_k *
        hitran_boltzmann_constant_cm3_hpa_per_k /
        pressure_atm /
        1013.25;

    return @max(prefactor * cpf.wr, 0.0);
}

fn prepareStrongLineState(
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    temperature_k: f64,
    pressure_atm: f64,
) StrongLinePreparedState {
    // prepareStrongLineState ---------------------------------------------------------------------------------|
    // Prepare old O2 ConvTP line-mixing state for one profile-node temperature and pressure.                  |
    // --------------------------------------------------------------------------------------------------------|
    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const temperature_ratio = hitran_reference_temperature_k / safe_temperature;
    const partition_ratio = hitran_partition_tables.ratioT0OverT(
        66,
        safe_temperature,
        hitran_reference_temperature_k,
    ) orelse temperature_ratio;
    const line_count: usize = @min(@min(strong_lines.len, relaxation_matrix.line_count), max_strong_line_sidecars);
    var state = StrongLinePreparedState{ .line_count = line_count };
    if (line_count == 0) return state;

    var relaxation_weights: [max_strong_line_sidecars * max_strong_line_sidecars]f64 = undefined;
    const relaxation_weight_count: usize = line_count * line_count;
    fillStrongLineState(
        &state,
        relaxation_weights[0..relaxation_weight_count],
        strong_lines,
        relaxation_matrix,
        line_count,
        safe_temperature,
        temperature_ratio,
        partition_ratio,
        pressure_atm,
    );
    return state;
}

fn fillStrongLineState(
    state: *StrongLinePreparedState,
    relaxation_weights: []f64,
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    line_count: usize,
    safe_temperature: f64,
    temperature_ratio: f64,
    partition_ratio: f64,
    pressure_atm: f64,
) void {
    // fillStrongLineState ------------------------------------------------------------------------------------|
    // Fill old DISAMAR O2 line-mixing relaxation state for all retained strong-line sidecars.                 |
    // --------------------------------------------------------------------------------------------------------|
    for (0..line_count) |row_index| {
        const strong_line = strong_lines[row_index];
        const inverse_temperature_delta = (1.0 / hitran_reference_temperature_k) - (1.0 / safe_temperature);
        const population_energy_scale = 1.43877696 *
            strong_line.lower_state_energy_cm1 *
            inverse_temperature_delta;
        state.population_t[row_index] = strong_line.population_t0 *
            partition_ratio *
            @exp(population_energy_scale);
        state.dipole_t[row_index] = strong_line.dipole_t0 * @sqrt(temperature_ratio);
        state.mod_sig_cm1[row_index] =
            strong_line.center_wavenumber_cm1 + pressure_atm * strong_line.pressure_shift_cm1;
        state.half_width_cm1_at_t[row_index] = strong_line.air_half_width_cm1 *
            std.math.pow(f64, temperature_ratio, strong_line.temperature_exponent);

        for (0..line_count) |column_index| {
            setRelaxationWeight(
                relaxation_weights,
                line_count,
                row_index,
                column_index,
                relaxation_matrix.weightAt(row_index, column_index) *
                    std.math.pow(
                        f64,
                        temperature_ratio,
                        relaxation_matrix.temperatureExponentAt(row_index, column_index),
                    ),
            );
        }
    }

    for (0..line_count) |row_index| {
        for (0..line_count) |column_index| {
            const column_energy_cm1 = strong_lines[column_index].lower_state_energy_cm1;
            const row_energy_cm1 = strong_lines[row_index].lower_state_energy_cm1;
            if (column_energy_cm1 < row_energy_cm1) continue;

            setRelaxationWeight(
                relaxation_weights,
                line_count,
                column_index,
                row_index,
                relaxationWeightAt(relaxation_weights, line_count, row_index, column_index) *
                    state.population_t[column_index] /
                    @max(state.population_t[row_index], 1.0e-24),
            );
        }
    }

    for (0..line_count) |index| {
        setRelaxationWeight(relaxation_weights, line_count, index, index, state.half_width_cm1_at_t[index]);
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
    else
        state.mod_sig_cm1[0];

    for (0..line_count) |column_index| {
        var upper_sum: f64 = 0.0;
        var lower_sum: f64 = 0.0;
        for (0..line_count) |row_index| {
            if (row_index <= column_index) {
                upper_sum += strong_lines[row_index].dipole_ratio *
                    relaxationWeightAt(relaxation_weights, line_count, row_index, column_index);
            } else {
                lower_sum += strong_lines[row_index].dipole_ratio *
                    relaxationWeightAt(relaxation_weights, line_count, row_index, column_index);
            }
        }
        const rotational_gate = 1.0 -
            @abs(@as(f64, @floatFromInt(strong_lines[column_index].rotational_index_m1))) / 36.0;
        const renormalization_anchor = strong_lines[column_index].dipole_ratio *
            rotational_gate *
            rotational_gate *
            0.04;

        for (0..line_count) |row_index| {
            if (row_index <= column_index) continue;
            const renormalized = -relaxationWeightAt(relaxation_weights, line_count, row_index, column_index) *
                (upper_sum - renormalization_anchor) /
                lower_sum;
            setRelaxationWeight(relaxation_weights, line_count, row_index, column_index, renormalized);
            setRelaxationWeight(
                relaxation_weights,
                line_count,
                column_index,
                row_index,
                renormalized * state.population_t[column_index] / state.population_t[row_index],
            );
        }
    }

    for (0..line_count) |line_index| {
        var mixing_sum: f64 = 0.0;
        for (0..line_count) |other_index| {
            if (other_index == line_index) continue;

            const delta_sig = state.mod_sig_cm1[line_index] - state.mod_sig_cm1[other_index];
            if (delta_sig == 0.0) continue;

            mixing_sum += 2.0 * state.dipole_t[other_index] / state.dipole_t[line_index] *
                relaxationWeightAt(relaxation_weights, line_count, other_index, line_index) /
                delta_sig;
        }
        state.line_mixing_coefficients[line_index] = pressure_atm * mixing_sum;
    }
}

fn strongLineContribution(
    wavelength_nm: f64,
    strong_index: usize,
    state: *const StrongLinePreparedState,
    temperature_k: f64,
    pressure_atm: f64,
) SpectroscopyComponents {
    // strongLineContribution ---------------------------------------------------------------------------------|
    // Evaluate one prepared O2 strong-line sidecar with the old CPF line-mixing formula.                      |
    // --------------------------------------------------------------------------------------------------------|
    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const safe_pressure = @max(pressure_atm, min_spectroscopy_pressure_atm);
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const sig_moy_cm1 = @max(state.sig_moy_cm1, 1.0e-6);
    const gam_d = @max(dopplerWidthCm1(safe_temperature, sig_moy_cm1, 31.989830), 1.0e-6);
    const cte = @sqrt(@log(2.0)) / gam_d;
    const cte1 = cte / @sqrt(hitran_pi);
    const cpf = complexProbabilityFunction(
        (state.mod_sig_cm1[strong_index] - evaluation_wavenumber_cm1) * cte,
        state.half_width_cm1_at_t[strong_index] * safe_pressure * cte,
    );
    const cte2 = evaluation_wavenumber_cm1 *
        @max(1.0 - @exp(-hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature), 0.0);
    const base_absorption = cte1 *
        safe_pressure *
        state.population_t[strong_index] *
        state.dipole_t[strong_index] *
        state.dipole_t[strong_index] *
        cte2;
    const number_density = 1013.25 * safe_pressure / safe_temperature / hitran_boltzmann_constant_cm3_hpa_per_k;
    const line_sigma = @max(base_absorption * cpf.wr / number_density, 0.0);
    const line_mixing_sigma = (-base_absorption *
        state.line_mixing_coefficients[strong_index] *
        cpf.wi) / number_density;
    return .{
        .strong_line_sigma_cm2_per_molecule = line_sigma,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = @max(line_sigma + line_mixing_sigma, 0.0),
    };
}

fn relaxationWeightAt(relaxation_weights: []const f64, line_count: usize, row: usize, column: usize) f64 {
    // relaxationWeightAt -------------------------------------------------------------------------------------|
    // Read one row-major relaxation-matrix scratch value.                                                     |
    // --------------------------------------------------------------------------------------------------------|
    return relaxation_weights[row * line_count + column];
}

fn setRelaxationWeight(
    relaxation_weights: []f64,
    line_count: usize,
    row: usize,
    column: usize,
    value: f64,
) void {
    // setRelaxationWeight ------------------------------------------------------------------------------------|
    // Write one row-major relaxation-matrix scratch value.                                                    |
    // --------------------------------------------------------------------------------------------------------|
    relaxation_weights[row * line_count + column] = value;
}

fn insideCutoff(
    line: readers.O2LineAssetRow,
    wavelength_nm: f64,
    pressure_atm: f64,
    runtime: RuntimeControls,
) bool {
    // insideCutoff -------------------------------------------------------------------------------------------|
    // Apply the scalar HITRAN cutoff window around the pressure-shifted line center.                          |
    // --------------------------------------------------------------------------------------------------------|
    const shifted_center_wavenumber_cm1 = shiftedCenterWavenumberCm1(line, pressure_atm);
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    return @abs(shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1) <=
        runtime.cutoff_cm1 + vendor_cutoff_boundary_margin_cm1;
}

fn shiftedCenterWavenumberCm1(line: readers.O2LineAssetRow, pressure_atm: f64) f64 {
    // shiftedCenterWavenumberCm1 -----------------------------------------------------------------------------|
    // Apply the old pressure-shifted line-center floor before cutoff checks and public row projection.        |
    // --------------------------------------------------------------------------------------------------------|
    return @max(line.center_wavenumber_cm1 + line.pressure_shift_cm1 * pressure_atm, 1.0);
}

fn complexProbabilityFunction(x: f64, y: f64) ComplexProbability {
    // complexProbabilityFunction -----------------------------------------------------------------------------|
    // Compute the CPF approximation used by retained weak-line and strong-line Voigt formulas.                |
    // --------------------------------------------------------------------------------------------------------|
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
    // wavelengthToWavenumberCm1 ------------------------------------------------------------------------------|
    // Convert nanometer wavelength to inverse-centimeter wavenumber with a positive divisor floor.            |
    // --------------------------------------------------------------------------------------------------------|
    return 1.0e7 / @max(wavelength_nm, 1.0e-9);
}

fn wavenumberToWavelengthNm(wavenumber_cm1: f64) f64 {
    // wavenumberToWavelengthNm -------------------------------------------------------------------------------|
    // Convert inverse-centimeter wavenumber to nanometer wavelength with a positive divisor floor.            |
    // --------------------------------------------------------------------------------------------------------|
    return 1.0e7 / @max(wavenumber_cm1, 1.0e-9);
}

fn dopplerWidthCm1(temperature_k: f64, wavenumber_cm1: f64, molecular_weight_g_per_mol: f64) f64 {
    // dopplerWidthCm1 ----------------------------------------------------------------------------------------|
    // Compute HITRAN Doppler half-width in inverse centimeters from temperature and molecular mass.           |
    // --------------------------------------------------------------------------------------------------------|
    const prefactor = @sqrt(
        2.0 * @log(2.0) * hitran_gas_constant_j_per_mol_k /
            (hitran_speed_of_light_m_per_s * hitran_speed_of_light_m_per_s),
    );
    return prefactor *
        std.math.sqrt(@max(temperature_k, 1.0)) /
        std.math.sqrt(@max(molecular_weight_g_per_mol / 1.0e3, 1.0e-12)) *
        wavenumber_cm1;
}

fn partitionRatioT0OverT(line: readers.O2LineAssetRow, temperature_k: f64) f64 {
    // partitionRatioT0OverT ----------------------------------------------------------------------------------|
    // Return HITRAN partition Q(T0) / Q(T), with the retained old-route fallback exponents.                   |
    // --------------------------------------------------------------------------------------------------------|
    const isotopologue_code = deriveIsotopologueCode(line.gas_index, line.isotope_number);
    if (hitran_partition_tables.ratioT0OverT(
        isotopologue_code,
        temperature_k,
        hitran_reference_temperature_k,
    )) |ratio| {
        return ratio;
    }

    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const exponent: f64 = switch (isotopologue_code) {
        66, 68, 67, 101, 102 => 1.0,
        626, 636, 628, 627, 638, 637 => 1.35,
        161, 181, 171, 162, 182, 172 => 1.10,
        else => 1.0 + 0.04 * @as(f64, @floatFromInt(@max(line.isotope_number, 1) - 1)),
    };
    return std.math.pow(f64, hitran_reference_temperature_k / safe_temperature, exponent);
}

fn molecularWeightForLine(line: readers.O2LineAssetRow) f64 {
    // molecularWeightForLine ---------------------------------------------------------------------------------|
    // Return isotopologue molecular mass, falling back to the parent gas mass for unsupported codes.          |
    // --------------------------------------------------------------------------------------------------------|
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

fn deriveIsotopologueCode(gas_index: u16, isotope_number: u8) i32 {
    // deriveIsotopologueCode ---------------------------------------------------------------------------------|
    // Map HITRAN gas/isotope indexes to the retained DISAMAR isotopologue partition-table code.               |
    // --------------------------------------------------------------------------------------------------------|
    return switch (gas_index) {
        1 => waterIsotopologueCode(isotope_number),
        2 => co2IsotopologueCode(isotope_number),
        5 => coIsotopologueCode(isotope_number),
        6 => ch4IsotopologueCode(isotope_number),
        7 => o2IsotopologueCode(isotope_number),
        11 => no2IsotopologueCode(isotope_number),
        else => @as(i32, gas_index) * 100 + @as(i32, isotope_number),
    };
}

fn waterIsotopologueCode(isotope_number: u8) i32 {
    // waterIsotopologueCode ----------------------------------------------------------------------------------|
    // Map HITRAN water isotope numbers to retained partition-table codes.                                     |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 161,
        2 => 181,
        3 => 171,
        4 => 162,
        5 => 182,
        6 => 172,
        else => 160 + @as(i32, @intCast(isotope_number)),
    };
}

fn co2IsotopologueCode(isotope_number: u8) i32 {
    // co2IsotopologueCode ------------------------------------------------------------------------------------|
    // Map HITRAN CO2 isotope numbers to retained partition-table codes.                                       |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 626,
        2 => 636,
        3 => 628,
        4 => 627,
        5 => 638,
        6 => 637,
        else => 620 + @as(i32, @intCast(isotope_number)),
    };
}

fn coIsotopologueCode(isotope_number: u8) i32 {
    // coIsotopologueCode -------------------------------------------------------------------------------------|
    // Map HITRAN CO isotope numbers to retained partition-table codes.                                        |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 26,
        2 => 36,
        3 => 28,
        4 => 27,
        5 => 38,
        6 => 37,
        else => 20 + @as(i32, @intCast(isotope_number)),
    };
}

fn ch4IsotopologueCode(isotope_number: u8) i32 {
    // ch4IsotopologueCode ------------------------------------------------------------------------------------|
    // Map HITRAN CH4 isotope numbers to retained partition-table codes.                                       |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 211,
        2 => 311,
        3 => 212,
        else => 210 + @as(i32, @intCast(isotope_number)),
    };
}

fn o2IsotopologueCode(isotope_number: u8) i32 {
    // o2IsotopologueCode -------------------------------------------------------------------------------------|
    // Map HITRAN O2 isotope numbers to retained partition-table codes.                                        |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 66,
        2 => 68,
        3 => 67,
        4 => 69,
        else => 70 + @as(i32, @intCast(isotope_number)),
    };
}

fn no2IsotopologueCode(isotope_number: u8) i32 {
    // no2IsotopologueCode ------------------------------------------------------------------------------------|
    // Map HITRAN NO2 isotope numbers to retained partition-table codes.                                       |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 4111,
        2 => 5111,
        else => 4100 + @as(i32, @intCast(isotope_number)),
    };
}

comptime {
    std.debug.assert(@sizeOf(O2LineContributionRow) == 168);
    std.debug.assert(@sizeOf(O2LineContributions) == 32);
}
