//! Spectroscopy line-list support helpers that are not themselves line-shape
//! physics.

const std = @import("std");
const Physics = @import("physics.zig");
const Types = @import("types.zig");

pub fn lineCenterWavenumberCm1(line: Types.SpectroscopyLine) f64 {
    return if (std.math.isFinite(line.center_wavenumber_cm1))
        line.center_wavenumber_cm1
    else
        Physics.wavelengthToWavenumberCm1(line.center_wavelength_nm);
}

pub fn lineAirHalfWidthCm1(line: Types.SpectroscopyLine) f64 {
    return if (std.math.isFinite(line.air_half_width_cm1))
        line.air_half_width_cm1
    else
        Physics.spectralWidthNmToCm1(line.air_half_width_nm, lineCenterWavenumberCm1(line));
}

pub fn linePressureShiftCm1(line: Types.SpectroscopyLine) f64 {
    return if (std.math.isFinite(line.pressure_shift_cm1))
        line.pressure_shift_cm1
    else
        -Physics.spectralWidthNmToCm1(line.pressure_shift_nm, lineCenterWavenumberCm1(line));
}

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
