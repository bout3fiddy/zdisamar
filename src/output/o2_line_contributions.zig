const std = @import("std");
const Optics = @import("../forward_model/optical_properties/root.zig");
const ReferenceData = @import("../input/ReferenceData.zig");
const LineListOps = @import("../input/reference/spectroscopy/line_list.zig");
const SpectroscopyPhysics = @import("../input/reference/spectroscopy/physics_core.zig");
const SpectroscopyStrongLines = @import("../input/reference/spectroscopy/strong_lines.zig");
const SpectroscopySupport = @import("../input/reference/spectroscopy/support.zig");
const SpectroscopyTypes = @import("../input/reference/spectroscopy/types.zig");

const Allocator = std.mem.Allocator;
const PreparedOpticalState = Optics.PreparedOpticalState;
const SpectroscopyLine = ReferenceData.SpectroscopyLine;
const SpectroscopyLineList = ReferenceData.SpectroscopyLineList;
const SpectroscopyStrongLine = ReferenceData.SpectroscopyStrongLine;

const missing_index = std.math.maxInt(u32);

// o2_line_contributions.zig ----------------------------------------------------------------------------------|
// O2 spectroscopy contribution diagnostics for prepared weak-line windows and strong-line sidecars. This file |
// renders line-level explanation rows; it does not feed the forward RTM solve.                                |
//                                                                                                             |
// called by                                                                                                   |
//   root.zig exposes buildO2LineContributions for Zig callers. api/c.zig calls the same builder, copies       |
//   rows into Context-owned C ABI storage, reports total_row_count/truncated, and frees the native table.     |
//                                                                                                             |
// main paths                                                                                                  |
//   build                   -> primary O2 line list -> requested wavelengths -> profile nodes                 |
//   appendRowsForWavelength -> relevant weak-line window plus strong-line sidecar rows for one state          |
//   weakLineRow             -> weak-line sigma unless the line is owned by a strong-line sidecar              |
//   strongLineRow           -> strong-line sidecar sigma and anchor-line metadata                             |
//                                                                                                             |
// diagnostic contract                                                                                         |
//   row_kind separates weak-line and strong-line rows. status explains inclusion, strong-line ownership, or   |
//   cutoff. max_rows limits materialized rows for large line lists; total_row_count still reports how many    |
//   rows would have been emitted without truncation.                                                          |
//                                                                                                             |
// hot path                                                                                                    |
//   This is diagnostic work over wavelength x profile-node x relevant-line grids. The prepared line states    |
//   and sidecar indexes are reused; the output path still does per-row spectroscopy evaluation by design.     |
//                                                                                                             |
// memory                                                                                                      |
//   ArrayList owns only the materialized rows up to max_rows. Rows are wide value records because they are    |
//   exported diagnostics with no referenced storage.                                                          |
// ------------------------------------------------------------------------------------------------------------|

pub const O2LineRowKind = enum(u32) {
    weak_line = 0,
    strong_line = 1,
};

pub const O2LineStatus = enum(u32) {
    weak_included = 0,
    weak_excluded_by_strong_line = 1,
    strong_sidecar = 2,
    weak_zero_after_cutoff = 3,
};

// O2LineContributionRow --------------------------------------------------------------------------------------|
// Stores one exported O2 line diagnostic row for one wavelength and one thermodynamic state.                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 160 B (0.156 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] temperature_k                      : f64                                                         |
// [  8.. 15] altitude_km                        : f64                                                         |
// [ 16.. 23] center_wavenumber_cm1              : f64                                                         |
// [ 24.. 31] center_wavelength_nm               : f64                                                         |
// [ 32.. 39] wavelength_nm                      : f64                                                         |
// [ 40.. 47] shifted_center_wavenumber_cm1      : f64                                                         |
// [ 48.. 55] line_strength_cm2_per_molecule     : f64                                                         |
// [ 56.. 63] air_half_width_cm1                 : f64                                                         |
// [ 64.. 71] pressure_shift_cm1                 : f64                                                         |
// [ 72.. 79] lower_state_energy_cm1             : f64                                                         |
// [ 80.. 87] pressure_hpa                       : f64                                                         |
// [ 88.. 95] weak_line_sigma_cm2_per_molecule   : f64                                                         |
// [ 96..103] strong_line_sigma_cm2_per_molecule : f64                                                         |
// [104..111] line_mixing_sigma_cm2_per_molecule : f64                                                         |
// [112..119] total_sigma_cm2_per_molecule       : f64                                                         |
// [120..127] abs_total_sigma_cm2_per_molecule   : f64                                                         |
// [128..131] profile_node_index                 : u32                                                         |
// [132..135] row_kind                           : O2LineRowKind                                               |
// [136..139] status                             : O2LineStatus                                                |
// [140..143] line_index                         : u32                                                         |
// [144..147] matched_strong_line_index          : u32                                                         |
// [148..151] isotopologue_code                  : i32                                                         |
// [152..155] strong_line_index                  : u32                                                         |
// [156..157] gas_index                          : u16                                                         |
// [158..158] isotope_number                     : u8                                                          |
// [159..159] trailing padding                                                                                 |
//                                                                                                             |
// unused bits: 8 padding + 0 bool-storage slack = 8 bits                                                      |
// footprint: per instance = 160 B (0.156 KiB); total = per instance * live instance count                     |
pub const O2LineContributionRow = struct {
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

// ThermodynamicState -----------------------------------------------------------------------------------------|
// Carries the profile-node state shared by weak-line and strong-line diagnostic row builders.                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] altitude_km        : f64                                                                           |
// [ 8..15] temperature_k      : f64                                                                           |
// [16..23] pressure_hpa       : f64                                                                           |
// [24..27] profile_node_index : u32                                                                           |
// [28..31] trailing padding                                                                                   |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per instance = 32 B (0.031 KiB); total = stack or caller-local temporary                         |
const ThermodynamicState = struct {
    profile_node_index: u32,
    altitude_km: f64,
    temperature_k: f64,
    pressure_hpa: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// O2LineContributionTable ------------------------------------------------------------------------------------|
// Owns the diagnostic rows returned by build and records whether max_rows truncated the materialized slice.   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] rows            : []O2LineContributionRow                                                          |
// [16..23] total_row_count : usize                                                                            |
// [24..24] truncated       : bool                                                                             |
// [25..31] trailing padding                                                                                   |
//                                                                                                             |
// out-of-line: rows owns allocator storage; referenced storage is not included in size                        |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// footprint: per instance = 32 B (0.031 KiB); total also includes owned rows                                  |
pub const O2LineContributionTable = struct {
    rows: []O2LineContributionRow,
    total_row_count: usize,
    truncated: bool,

    pub fn deinit(self: *O2LineContributionTable, allocator: Allocator) void {
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(
    allocator: Allocator,
    prepared: *const PreparedOpticalState,
    wavelengths_nm: []const f64,
    max_rows: usize,
) !O2LineContributionTable {
    // build --------------------------------------------------------------------------------------------------|
    // Builds O2 line-contribution diagnostics for requested wavelengths and available profile nodes.          |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : diagnostic requests over wavelength x profile-node grids                                   |
    //   costly   : relevant-line windowing, weak-line evaluation, and strong-line sidecar evaluation          |
    //   memory   : ArrayList grows to max_rows; total_row_count tracks rows that would have been emitted      |
    //                                                                                                         |
    // calls                                                                                                   |
    //   primaryO2LineList                                                                                     |
    //   appendRowsForWavelength                                                                               |
    // --------------------------------------------------------------------------------------------------------|

    if (wavelengths_nm.len == 0) return error.EmptyWavelengths;
    if (max_rows == 0) return error.InvalidRowLimit;

    const line_list = primaryO2LineList(prepared) orelse return error.O2LineListUnavailable;

    var rows = std.ArrayList(O2LineContributionRow).empty;
    errdefer rows.deinit(allocator);
    try rows.ensureTotalCapacity(allocator, @min(max_rows, line_list.lines.len + strongLineCount(line_list)));

    var total_row_count: usize = 0;
    for (wavelengths_nm) |wavelength_nm| {
        if (profileNodeCount(prepared)) |node_count| {
            for (0..node_count) |node_index| {
                try appendRowsForWavelength(
                    allocator,
                    &rows,
                    &total_row_count,
                    max_rows,
                    line_list,
                    wavelength_nm,
                    .{
                        .profile_node_index = @intCast(node_index),
                        .altitude_km = prepared.spectroscopy_profile_altitudes_km[node_index],
                        .temperature_k = prepared.spectroscopy_profile_temperatures_k[node_index],
                        .pressure_hpa = prepared.spectroscopy_profile_pressures_hpa[node_index],
                    },
                );
            }
        } else {
            try appendRowsForWavelength(
                allocator,
                &rows,
                &total_row_count,
                max_rows,
                line_list,
                wavelength_nm,
                .{
                    .profile_node_index = missing_index,
                    .altitude_km = std.math.nan(f64),
                    .temperature_k = prepared.effective_temperature_k,
                    .pressure_hpa = prepared.effective_pressure_hpa,
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

fn primaryO2LineList(prepared: *const PreparedOpticalState) ?SpectroscopyLineList {
    if (prepared.spectroscopy_lines) |line_list| return line_list;
    for (prepared.line_absorbers) |line_absorber| {
        if (line_absorber.species == .o2) return line_absorber.line_list;
    }
    return null;
}

fn profileNodeCount(prepared: *const PreparedOpticalState) ?usize {
    const node_count = prepared.spectroscopy_profile_altitudes_km.len;
    if (node_count == 0) return null;
    if (prepared.spectroscopy_profile_pressures_hpa.len != node_count) return null;
    if (prepared.spectroscopy_profile_temperatures_k.len != node_count) return null;
    return node_count;
}

fn strongLineCount(line_list: SpectroscopyLineList) usize {
    if (!line_list.hasStrongLineSidecars()) return 0;
    return @min(line_list.strong_lines.?.len, SpectroscopyTypes.max_strong_line_sidecars);
}

fn appendRowsForWavelength(
    allocator: Allocator,
    rows: *std.ArrayList(O2LineContributionRow),
    total_row_count: *usize,
    max_rows: usize,
    line_list: SpectroscopyLineList,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
) !void {
    // appendRowsForWavelength --------------------------------------------------------------------------------|
    // Appends weak-line rows and strong-line sidecar rows for one wavelength and thermodynamic state.         |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : every wavelength/profile-node pair in build                                                |
    //   costly   : relevant-line window scan, weak-line contribution, strong-line ConvTP state preparation    |
    //   memory   : caller-owned ArrayList; anchor_storage is a bounded stack array                            |
    //                                                                                                         |
    // calls                                                                                                   |
    //   weakLineRow                                                                                           |
    //   strongLineRow                                                                                         |
    // --------------------------------------------------------------------------------------------------------|

    const pressure_scale = @max(
        thermodynamic_state.pressure_hpa / 1013.25,
        SpectroscopyTypes.min_spectroscopy_pressure_atm,
    );
    const safe_temperature = @max(thermodynamic_state.temperature_k, 150.0);
    const relevant_window = LineListOps.relevantLineWindowForWavelength(line_list, wavelength_nm);
    const relevant_lines = relevant_window.lines;
    var anchor_storage: [SpectroscopyTypes.max_strong_line_sidecars]SpectroscopyTypes.StrongLineAnchorIndex = undefined;
    const strong_line_anchors = LineListOps.selectStrongLineAnchors(
        line_list,
        relevant_lines,
        relevant_window.start_index,
        &anchor_storage,
    );

    for (relevant_lines, 0..) |*line, line_index| {
        total_row_count.* += 1;
        if (rows.items.len >= max_rows) continue;
        try rows.append(
            allocator,
            weakLineRow(
                line_list,
                wavelength_nm,
                thermodynamic_state,
                safe_temperature,
                pressure_scale,
                relevant_window.start_index,
                line,
                line_index,
                strong_line_anchors,
            ),
        );
    }

    if (line_list.hasStrongLineSidecars()) {
        const strong_lines = line_list.strong_lines.?;
        const relaxation_matrix = line_list.relaxation_matrix.?;
        const strong_state = SpectroscopyStrongLines.prepareStrongLineConvTPState(
            strong_lines,
            relaxation_matrix,
            safe_temperature,
            pressure_scale,
        );
        for (strong_lines[0..strong_state.line_count], 0..) |strong_line, strong_index| {
            total_row_count.* += 1;
            if (rows.items.len >= max_rows) continue;
            try rows.append(
                allocator,
                strongLineRow(
                    line_list,
                    wavelength_nm,
                    thermodynamic_state,
                    safe_temperature,
                    strong_lines,
                    strong_line,
                    strong_index,
                    strong_line_anchors,
                    relevant_lines,
                    relevant_window.start_index,
                    &strong_state,
                ),
            );
        }
    }
}

fn weakLineRow(
    line_list: SpectroscopyLineList,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
    temperature_k: f64,
    pressure_scale: f64,
    start_index: usize,
    line: *const SpectroscopyLine,
    line_index: usize,
    strong_line_anchors: []const SpectroscopyTypes.StrongLineAnchorIndex,
) O2LineContributionRow {
    const matched_strong_index = LineListOps.matchedStrongIndexForRelevantLine(
        line_list,
        start_index,
        line,
        line_index,
    );
    const excluded = LineListOps.shouldExcludeWeakLine(
        line_list,
        start_index,
        line,
        line_index,
        strong_line_anchors,
    );

    const contribution = choose_contribution: {
        if (excluded) break :choose_contribution zeroEvaluation();
        break :choose_contribution SpectroscopyPhysics.weakLineContribution(
            wavelength_nm,
            line.*,
            temperature_k,
            pressure_scale,
            SpectroscopyTypes.hitran_reference_temperature_k,
            line_list.runtime_controls,
        );
    };

    const status: O2LineStatus = choose_status: {
        if (excluded) break :choose_status .weak_excluded_by_strong_line;
        if (contribution.total_sigma_cm2_per_molecule == 0.0) break :choose_status .weak_zero_after_cutoff;
        break :choose_status .weak_included;
    };

    return .{
        .wavelength_nm = wavelength_nm,
        .profile_node_index = thermodynamic_state.profile_node_index,
        .altitude_km = thermodynamic_state.altitude_km,
        .row_kind = .weak_line,
        .status = status,
        .line_index = @intCast(start_index + line_index),
        .strong_line_index = missing_index,
        .matched_strong_line_index = optionalIndex(matched_strong_index),
        .gas_index = line.gas_index,
        .isotope_number = line.isotope_number,
        .isotopologue_code = SpectroscopyStrongLines.deriveIsotopologueCode(line.gas_index, line.isotope_number),
        .center_wavelength_nm = line.center_wavelength_nm,
        .center_wavenumber_cm1 = SpectroscopySupport.lineCenterWavenumberCm1(line),
        .shifted_center_wavenumber_cm1 = SpectroscopyStrongLines.shiftedLineCenterWavenumberCm1(line.*, pressure_scale),
        .line_strength_cm2_per_molecule = line.line_strength_cm2_per_molecule,
        .air_half_width_cm1 = SpectroscopySupport.lineAirHalfWidthCm1(line),
        .pressure_shift_cm1 = SpectroscopySupport.linePressureShiftCm1(line),
        .lower_state_energy_cm1 = line.lower_state_energy_cm1,
        .temperature_k = temperature_k,
        .pressure_hpa = thermodynamic_state.pressure_hpa,
        .weak_line_sigma_cm2_per_molecule = contribution.weak_line_sigma_cm2_per_molecule,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = contribution.total_sigma_cm2_per_molecule,
        .abs_total_sigma_cm2_per_molecule = @abs(contribution.total_sigma_cm2_per_molecule),
    };
}

const StrongAnchorFields = struct {
    line_index: u32,
    gas_index: u16,
    isotope_number: u8,
    isotopologue_code: i32,
    line_strength_cm2_per_molecule: f64,
};

fn strongLineRow(
    line_list: SpectroscopyLineList,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
    temperature_k: f64,
    strong_lines: []const SpectroscopyStrongLine,
    strong_line: SpectroscopyStrongLine,
    strong_index: usize,
    strong_line_anchors: []const SpectroscopyTypes.StrongLineAnchorIndex,
    relevant_lines: []const SpectroscopyLine,
    relevant_start_index: usize,
    strong_state: *const SpectroscopyStrongLines.StrongLineConvTPState,
) O2LineContributionRow {
    const pressure_atm = @max(
        thermodynamic_state.pressure_hpa / 1013.25,
        SpectroscopyTypes.min_spectroscopy_pressure_atm,
    );
    const contribution = SpectroscopyStrongLines.strongLineContribution(
        wavelength_nm,
        strong_lines,
        strong_index,
        strong_state,
        temperature_k,
        pressure_atm,
    );
    const line_mixing_sigma =
        contribution.line_mixing_sigma_cm2_per_molecule *
        line_list.runtime_controls.line_mixing_factor;
    const total_sigma = @max(contribution.strong_line_sigma_cm2_per_molecule + line_mixing_sigma, 0.0);
    const anchor = strongAnchorLine(strong_line_anchors, relevant_lines, relevant_start_index, strong_index);
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
    if (anchor) |owned| {
        return .{
            .line_index = owned.line_index,
            .gas_index = owned.line.gas_index,
            .isotope_number = owned.line.isotope_number,
            .isotopologue_code = SpectroscopyStrongLines.deriveIsotopologueCode(
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

// StrongAnchorMatch ------------------------------------------------------------------------------------------|
// Carries the weak-line anchor attached to one strong-line sidecar, when the relevant window contains it.     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] line       : *const SpectroscopyLine                                                               |
// [ 8..11] line_index : u32                                                                                   |
// [12..15] trailing padding                                                                                   |
//                                                                                                             |
// out-of-line: line points into the relevant-line slice; pointed storage is not included in size              |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per present optional payload = 16 B (0.016 KiB); total = stack temporary                         |
const StrongAnchorMatch = struct {
    line: *const SpectroscopyLine,
    line_index: u32,
};
// ------------------------------------------------------------------------------------------------------------|

fn strongAnchorLine(
    strong_line_anchors: []const SpectroscopyTypes.StrongLineAnchorIndex,
    relevant_lines: []const SpectroscopyLine,
    relevant_start_index: usize,
    strong_index: usize,
) ?StrongAnchorMatch {
    if (strong_index >= strong_line_anchors.len) return null;

    const relevant_index = strong_line_anchors[strong_index];
    if (relevant_index == SpectroscopyTypes.missing_strong_line_anchor_index) return null;

    const relevant_index_usize: usize = @intCast(relevant_index);
    if (relevant_index_usize >= relevant_lines.len) return null;

    return .{
        .line = &relevant_lines[relevant_index_usize],
        .line_index = @intCast(relevant_start_index + relevant_index_usize),
    };
}

fn optionalIndex(index: ?usize) u32 {
    return if (index) |value| @intCast(value) else missing_index;
}

fn zeroEvaluation() ReferenceData.SpectroscopyEvaluation {
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}
