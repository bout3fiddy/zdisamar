const std = @import("std");
const Optics = @import("../forward_model/optical_properties/root.zig");
const ReferenceData = @import("../input/ReferenceData.zig");
const LineListOps = @import("../input/reference/spectroscopy/line_list_ops.zig");
const Physics = @import("../input/reference/spectroscopy/physics.zig");
const SpectroscopySupport = @import("../input/reference/spectroscopy/support.zig");
const SpectroscopyTypes = @import("../input/reference/spectroscopy/types.zig");

const Allocator = std.mem.Allocator;
const PreparedOpticalState = Optics.PreparedOpticalState;
const SpectroscopyLine = ReferenceData.SpectroscopyLine;
const SpectroscopyLineList = ReferenceData.SpectroscopyLineList;
const SpectroscopyStrongLine = ReferenceData.SpectroscopyStrongLine;

const missing_index = std.math.maxInt(u32);

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

const ThermodynamicState = struct {
    profile_node_index: u32,
    altitude_km: f64,
    temperature_k: f64,
    pressure_hpa: f64,
};

pub const O2LineContributionTable = struct {
    rows: []O2LineContributionRow,
    total_row_count: usize,
    truncated: bool,

    pub fn deinit(self: *O2LineContributionTable, allocator: Allocator) void {
        allocator.free(self.rows);
        self.* = undefined;
    }
};

// hot path:
//   when: O2 line-contribution diagnostics are requested over wavelengths and profile nodes
//   work: iterates wavelengths/profile nodes and appends weak/strong line contribution rows
//   data: prepared spectroscopy state, primary O2 line list, row list, max-row limit
//   follow: appendRowsForWavelength and line-list relevant-window selection
pub fn build(
    allocator: Allocator,
    prepared: *const PreparedOpticalState,
    wavelengths_nm: []const f64,
    max_rows: usize,
) !O2LineContributionTable {
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

// hot path:
//   when: O2 line diagnostics expand one wavelength/profile-node pair
//   work: appends relevant weak-line rows and active strong-line sidecar rows
//   data: relevant line window, strong-line anchors, thermodynamic state, output row list
//   follow: weakLineRow, strongLineRow, and strong-line ConvTP state preparation
fn appendRowsForWavelength(
    allocator: Allocator,
    rows: *std.ArrayList(O2LineContributionRow),
    total_row_count: *usize,
    max_rows: usize,
    line_list: SpectroscopyLineList,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
) !void {
    const pressure_scale = @max(
        thermodynamic_state.pressure_hpa / 1013.25,
        SpectroscopyTypes.min_spectroscopy_pressure_atm,
    );
    const safe_temperature = @max(thermodynamic_state.temperature_k, 150.0);
    const relevant_window = LineListOps.relevantLineWindowForWavelength(line_list, wavelength_nm);
    const relevant_lines = relevant_window.lines;
    const strong_line_anchors = LineListOps.selectStrongLineAnchors(
        line_list,
        relevant_lines,
        relevant_window.start_index,
    );

    for (relevant_lines, 0..) |line, line_index| {
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
                &strong_line_anchors,
            ),
        );
    }

    if (line_list.hasStrongLineSidecars()) {
        const strong_lines = line_list.strong_lines.?;
        const relaxation_matrix = line_list.relaxation_matrix.?;
        const strong_state = Physics.prepareStrongLineConvTPState(
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
                    &strong_line_anchors,
                    relevant_lines,
                    relevant_window.start_index,
                    strong_state,
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
    line: SpectroscopyLine,
    line_index: usize,
    strong_line_anchors: *const [SpectroscopyTypes.max_strong_line_sidecars]?usize,
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
    const contribution = if (excluded)
        zeroEvaluation()
    else
        Physics.weakLineContribution(
            wavelength_nm,
            line,
            temperature_k,
            pressure_scale,
            SpectroscopyTypes.hitran_reference_temperature_k,
            line_list.runtime_controls,
        );
    const status: O2LineStatus = if (excluded)
        .weak_excluded_by_strong_line
    else if (contribution.total_sigma_cm2_per_molecule == 0.0)
        .weak_zero_after_cutoff
    else
        .weak_included;

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
        .isotopologue_code = Physics.deriveIsotopologueCode(line.gas_index, line.isotope_number),
        .center_wavelength_nm = line.center_wavelength_nm,
        .center_wavenumber_cm1 = SpectroscopySupport.lineCenterWavenumberCm1(line),
        .shifted_center_wavenumber_cm1 = Physics.shiftedLineCenterWavenumberCm1(line, pressure_scale),
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

fn strongLineRow(
    line_list: SpectroscopyLineList,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
    temperature_k: f64,
    strong_lines: []const SpectroscopyStrongLine,
    strong_line: SpectroscopyStrongLine,
    strong_index: usize,
    strong_line_anchors: *const [SpectroscopyTypes.max_strong_line_sidecars]?usize,
    relevant_lines: []const SpectroscopyLine,
    relevant_start_index: usize,
    strong_state: Physics.StrongLineConvTPState,
) O2LineContributionRow {
    const pressure_atm = @max(
        thermodynamic_state.pressure_hpa / 1013.25,
        SpectroscopyTypes.min_spectroscopy_pressure_atm,
    );
    const contribution = Physics.strongLineContribution(
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

    return .{
        .wavelength_nm = wavelength_nm,
        .profile_node_index = thermodynamic_state.profile_node_index,
        .altitude_km = thermodynamic_state.altitude_km,
        .row_kind = .strong_line,
        .status = .strong_sidecar,
        .line_index = if (anchor) |owned| owned.line_index else missing_index,
        .strong_line_index = @intCast(strong_index),
        .matched_strong_line_index = @intCast(strong_index),
        .gas_index = if (anchor) |owned| owned.line.gas_index else 7,
        .isotope_number = if (anchor) |owned| owned.line.isotope_number else 1,
        .isotopologue_code = if (anchor) |owned|
            Physics.deriveIsotopologueCode(owned.line.gas_index, owned.line.isotope_number)
        else
            66,
        .center_wavelength_nm = strong_line.center_wavelength_nm,
        .center_wavenumber_cm1 = strong_line.center_wavenumber_cm1,
        .shifted_center_wavenumber_cm1 = strong_state.mod_sig_cm1[strong_index],
        .line_strength_cm2_per_molecule = if (anchor) |owned|
            owned.line.line_strength_cm2_per_molecule
        else
            std.math.nan(f64),
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

fn strongAnchorLine(
    strong_line_anchors: *const [SpectroscopyTypes.max_strong_line_sidecars]?usize,
    relevant_lines: []const SpectroscopyLine,
    relevant_start_index: usize,
    strong_index: usize,
) ?struct {
    line: SpectroscopyLine,
    line_index: u32,
} {
    if (strong_index >= strong_line_anchors.len) return null;
    const relevant_index = strong_line_anchors[strong_index] orelse return null;
    if (relevant_index >= relevant_lines.len) return null;
    return .{
        .line = relevant_lines[relevant_index],
        .line_index = @intCast(relevant_start_index + relevant_index),
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
