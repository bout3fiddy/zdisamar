//! Spectroscopy line-list support helpers that are not themselves line-shape
//! physics.

const Physics = @import("physics.zig");
const Types = @import("types.zig");

pub fn lineIndexIsStrongAnchor(anchor_indices: []const ?usize, line_index: usize) bool {
    for (anchor_indices) |anchor| {
        if (anchor == null) continue;
        if (anchor.? == line_index) return true;
    }
    return false;
}

pub fn zeroEvaluation() Types.SpectroscopyEvaluation {
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

pub fn traceRowForWeakLine(
    wavelength_nm: f64,
    global_line_index: usize,
    line: Types.SpectroscopyLine,
    matched_strong_index: ?usize,
    contribution_kind: Types.SpectroscopyTraceContributionKind,
    contribution: Types.SpectroscopyEvaluation,
    pressure_atm: f64,
) Types.SpectroscopyTraceRow {
    return .{
        .contribution_kind = contribution_kind,
        .wavelength_nm = wavelength_nm,
        .global_line_index = global_line_index,
        .strong_index = null,
        .matched_strong_index = matched_strong_index,
        .gas_index = line.gas_index,
        .isotope_number = line.isotope_number,
        .center_wavelength_nm = line.center_wavelength_nm,
        .center_wavenumber_cm1 = Physics.wavelengthToWavenumberCm1(line.center_wavelength_nm),
        .shifted_center_wavenumber_cm1 = Physics.shiftedLineCenterWavenumberCm1(line, pressure_atm),
        .line_strength_cm2_per_molecule = line.line_strength_cm2_per_molecule,
        .air_half_width_nm = line.air_half_width_nm,
        .temperature_exponent = line.temperature_exponent,
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

pub fn traceRowForStrongLine(
    wavelength_nm: f64,
    global_line_index: ?usize,
    strong_index: usize,
    anchor_line: ?Types.SpectroscopyLine,
    strong_line: Types.SpectroscopyStrongLine,
    contribution: Types.SpectroscopyEvaluation,
    pressure_atm: f64,
) Types.SpectroscopyTraceRow {
    const gas_index = if (anchor_line) |line| line.gas_index else 7;
    const isotope_number = if (anchor_line) |line| line.isotope_number else 1;
    const line_strength_cm2_per_molecule = if (anchor_line) |line| line.line_strength_cm2_per_molecule else 0.0;
    const line_mixing_coefficient = if (anchor_line) |line| line.line_mixing_coefficient else 0.0;
    const temperature_exponent = if (anchor_line) |line| line.temperature_exponent else 0.0;
    const branch_ic1 = if (anchor_line) |line| line.branch_ic1 else null;
    const branch_ic2 = if (anchor_line) |line| line.branch_ic2 else null;
    const rotational_nf = if (anchor_line) |line| line.rotational_nf else null;
    return .{
        .contribution_kind = .strong_sidecar,
        .wavelength_nm = wavelength_nm,
        .global_line_index = global_line_index,
        .strong_index = strong_index,
        .matched_strong_index = strong_index,
        .gas_index = gas_index,
        .isotope_number = isotope_number,
        .center_wavelength_nm = strong_line.center_wavelength_nm,
        .center_wavenumber_cm1 = strong_line.center_wavenumber_cm1,
        .shifted_center_wavenumber_cm1 = strong_line.center_wavenumber_cm1 + pressure_atm * strong_line.pressure_shift_cm1,
        .line_strength_cm2_per_molecule = line_strength_cm2_per_molecule,
        .air_half_width_nm = strong_line.air_half_width_nm,
        .temperature_exponent = temperature_exponent,
        .lower_state_energy_cm1 = strong_line.lower_state_energy_cm1,
        .pressure_shift_nm = strong_line.pressure_shift_nm,
        .line_mixing_coefficient = line_mixing_coefficient,
        .branch_ic1 = branch_ic1,
        .branch_ic2 = branch_ic2,
        .rotational_nf = rotational_nf,
        .weak_line_sigma_cm2_per_molecule = contribution.weak_line_sigma_cm2_per_molecule,
        .strong_line_sigma_cm2_per_molecule = contribution.strong_line_sigma_cm2_per_molecule,
        .line_mixing_sigma_cm2_per_molecule = contribution.line_mixing_sigma_cm2_per_molecule,
        .total_sigma_cm2_per_molecule = contribution.total_sigma_cm2_per_molecule,
    };
}

pub fn lineHasVendorStrongLineMetadata(line: Types.SpectroscopyLine) bool {
    return line.branch_ic1 != null and line.branch_ic2 != null and line.rotational_nf != null;
}

pub fn lineHasVendorStrongLineMetadataFromSource(line: Types.SpectroscopyLine) bool {
    return line.vendor_filter_metadata_from_source and lineHasVendorStrongLineMetadata(line);
}

pub fn wavenumberCm1ToWavelengthNm(wavenumber_cm1: f64) f64 {
    return 1.0e7 / @max(wavenumber_cm1, 1.0);
}

pub fn isVendorO2AStrongCandidate(line: Types.SpectroscopyLine) bool {
    return line.gas_index == 7 and
        line.isotope_number == 1 and
        line.branch_ic1 != null and
        line.branch_ic2 != null and
        line.rotational_nf != null and
        line.branch_ic1.? == 5 and
        line.branch_ic2.? == 1 and
        line.rotational_nf.? <= 35;
}

pub fn isVendorO2AStrongCandidateFromSource(line: Types.SpectroscopyLine) bool {
    return line.vendor_filter_metadata_from_source and isVendorO2AStrongCandidate(line);
}

pub fn runtimeControlsMatchLine(
    gas_index: ?u16,
    active_isotopes: []const u8,
    line: Types.SpectroscopyLine,
) bool {
    if (gas_index) |expected_gas_index| {
        if (line.gas_index != expected_gas_index) return false;
    }
    if (active_isotopes.len == 0) return true;
    for (active_isotopes) |isotope_number| {
        if (line.isotope_number == isotope_number) return true;
    }
    return false;
}

pub fn runtimeControlsKeepStrongLineSidecars(gas_index: ?u16, active_isotopes: []const u8) bool {
    if (gas_index) |expected_gas_index| {
        if (expected_gas_index != 7) return false;
    }
    if (active_isotopes.len == 0) return true;
    for (active_isotopes) |isotope_number| {
        if (isotope_number == 1) return true;
    }
    return false;
}
