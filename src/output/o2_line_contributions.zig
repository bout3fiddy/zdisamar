const std = @import("std");

const o2_run_tables = @import("../setup/o2_run_tables.zig");
const readers = @import("../assets/readers.zig");
const line_physics = @import("../spectrum/line_physics.zig");

const Allocator = std.mem.Allocator;

const min_spectroscopy_pressure_atm = 1.0e-12;
const missing_index = std.math.maxInt(u32);
const vendor_cutoff_prewindow_margin_cm1 = line_physics.vendor_cutoff_prewindow_margin_cm1;

// o2_line_contributions.zig ----------------------------------------------------------------------------------|
// Public O2 line-by-line diagnostic rows for selected wavelengths and spectroscopy profile nodes.             |
//                                                                                                             |
// boundary                                                                                                    |
//   The builder renders explanation rows from prepared setup tables into the fixed Python C ABI row order.    |
//   It does not parse inputs, own C handles, call transport, or feed the forward solve.                       |
//                                                                                                             |
//   line and ConvTP sidecar math is delegated to `src/spectrum/line_physics.zig`; this file only attaches     |
//   diagnostic row metadata and public row-status labels.                                                     |
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

const StrongLinePreparedState = line_physics.StrongLinePreparedState;

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
    const strong_line_count = @min(tables.lines.strong_lines.len, line_physics.max_strong_line_sidecars);
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
    const safe_temperature = @max(thermodynamic_state.temperature_k, line_physics.min_hitran_temperature_k);
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

    const strong_state = line_physics.prepareStrongLineState(
        tables.lines.strong_lines,
        tables.lines.relaxation_matrix,
        safe_temperature,
        pressure_atm,
        null,
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
    // Project one HITRAN weak-line row and its canonical inclusion status into the public diagnostic shape.   |
    // --------------------------------------------------------------------------------------------------------|
    const line = runtime_line.line;
    const matched_strong_index = matchedStrongIndexForRelevantLine(strong_lines, line, vendor_partition);
    const excluded = shouldExcludeWeakLine(line, line_index, window.lines, strong_lines, vendor_partition);

    var weak_sigma: f64 = 0.0;
    var status: O2LineStatus = .weak_excluded_by_strong_line;

    if (!excluded) {
        weak_sigma = line_physics.weakLineContribution(
            wavelength_nm,
            line,
            temperature_k,
            pressure_atm,
            runtime.cutoff_cm1,
            &.{},
            &.{},
            null,
        );

        status = if (weak_sigma == 0.0) .weak_zero_after_cutoff else .weak_included;
    }

    const matched_strong_line_index: u32 = if (matched_strong_index) |index|
        @intCast(index)
    else
        missing_index;

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
        .isotopologue_code = line_physics.deriveIsotopologueCode(line.gas_index, line.isotope_number),
        .center_wavelength_nm = line.center_wavelength_nm,
        .center_wavenumber_cm1 = line.center_wavenumber_cm1,
        .shifted_center_wavenumber_cm1 = line_physics.shiftedCenterWavenumberCm1(line, pressure_atm),
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
    const contribution = line_physics.strongLineContribution(
        wavelength_nm,
        strong_index,
        strong_state,
        temperature_k,
        pressure_atm,
    );
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
    // Copy weak-line metadata for sidecars, or keep the complete-row O2 defaults when no anchor exists.       |
    // --------------------------------------------------------------------------------------------------------|
    if (anchor) |owned| {
        return .{
            .line_index = owned.line_index,
            .gas_index = owned.line.gas_index,
            .isotope_number = owned.line.isotope_number,
            .isotopologue_code = line_physics.deriveIsotopologueCode(
                owned.line.gas_index,
                owned.line.isotope_number,
            ),
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
    // Fill a wavelength-local weak-line prewindow, preserving filtered source order for equal centers.        |
    // --------------------------------------------------------------------------------------------------------|
    rows.clearRetainingCapacity();
    if (lines.len == 0) return .{ .lines = rows.items };

    const evaluation_wavenumber_cm1 = line_physics.wavelengthToWavenumberCm1(wavelength_nm);
    const prewindow_cm1 = cutoff_cm1 + vendor_cutoff_prewindow_margin_cm1;
    const lower_wavenumber_cm1 = @max(evaluation_wavenumber_cm1 - prewindow_cm1, 1.0);
    const upper_wavenumber_cm1 = evaluation_wavenumber_cm1 + prewindow_cm1;
    const lower_wavelength_nm = line_physics.wavenumberToWavelengthNm(upper_wavenumber_cm1);
    const upper_wavelength_nm = line_physics.wavenumberToWavelengthNm(lower_wavenumber_cm1);
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
    // Copy O2 rows that participate in diagnostic evaluation, without applying the weak-line threshold.       |
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
    // Match sortLineList: pdq sort by center wavelength only. Equal-center ordering is the pdq result.        |
    // --------------------------------------------------------------------------------------------------------|
    return lhs.line.center_wavelength_nm < rhs.line.center_wavelength_nm;
}

fn runtimeLine(line: readers.O2LineAssetRow, active_isotopes: []const u8) bool {
    // runtimeLine --------------------------------------------------------------------------------------------|
    // Apply the total-sigma gas/isotope controls without the weak-line threshold filter.                      |
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
    // Detect the O2 A sidecar partition from retained HITRAN branch metadata.                                 |
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
    // Report the sidecar index associated with a weak line when the partition rules assign one.               |
    // --------------------------------------------------------------------------------------------------------|
    if (vendor_partition and !line_physics.isVendorO2AStrongCandidateFromSource(line)) return null;
    return line_physics.findStrongLineMatch(strong_lines, line.center_wavelength_nm);
}

fn shouldExcludeWeakLine(
    line: readers.O2LineAssetRow,
    line_index: usize,
    window: []const RuntimeLine,
    strong_lines: []const readers.O2StrongLineAssetRow,
    vendor_partition: bool,
) bool {
    // shouldExcludeWeakLine ----------------------------------------------------------------------------------|
    // Keep lines covered by O2 strong-line sidecars out of the weak-line contribution.                        |
    // --------------------------------------------------------------------------------------------------------|
    if (vendor_partition) {
        if (!line_physics.isVendorO2AStrongCandidateFromSource(line)) return false;
        return line_physics.findStrongLineMatch(strong_lines, line.center_wavelength_nm) != null;
    }

    const strong_index = line_physics.findStrongLineMatch(strong_lines, line.center_wavelength_nm) orelse return false;
    return strongestWindowAnchorForSidecar(window, strong_lines[strong_index]) == line_index;
}

fn strongestWindowAnchorForSidecar(
    window: []const RuntimeLine,
    strong_line: readers.O2StrongLineAssetRow,
) usize {
    // strongestWindowAnchorForSidecar ------------------------------------------------------------------------|
    // Select the generic sidecar anchor: closest line center, then strongest line on an equal delta.          |
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

comptime {
    std.debug.assert(@sizeOf(O2LineContributionRow) == 168);
    std.debug.assert(@sizeOf(O2LineContributions) == 32);
}
