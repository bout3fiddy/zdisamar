const std = @import("std");
const PhysicsCore = @import("physics_core.zig");
const Types = @import("types.zig");

// support.zig -----------------------------------------------------------------------------------------------|
// Spectroscopy metadata predicates and unit fallbacks shared by line-list setup and diagnostics.             |
//                                                                                                            |
// called by                                                                                                  |
//   line_list.zig uses these helpers while filtering runtime controls, preserving sidecars, detecting vendor |
//   O2 A strong-line partitions, and returning zero evaluations for empty windows.                           |
//   output/o2_line_contributions.zig uses the unit helpers so diagnostic rows report canonical               |
//   wavenumber/half-width/pressure-shift values even when the source list stored wavelength-space fields.    |
//                                                                                                            |
// unit fallback rules                                                                                        |
//   lineCenterWavenumberCm1, lineAirHalfWidthCm1, and linePressureShiftCm1 return finite cm^-1 source        |
//   fields when present. Otherwise they derive the value from nm fields through physics_core conversions.    |
//   Pressure-shift conversion keeps the sign convention used by HITRAN-style wavenumber shifts.              |
//                                                                                                            |
// vendor O2 A metadata                                                                                       |
//   A vendor strong-line candidate must be O2 gas 7, isotope 1, branch_ic1=5, branch_ic2=1, and              |
//   rotational_nf<=35. The *FromSource variants additionally require vendor_filter_metadata_from_source so   |
//   inferred metadata is not mistaken for vendor-provided partition evidence.                                |
//                                                                                                            |
// runtime controls                                                                                           |
//   runtimeControlsMatchLine applies the active gas and isotope filters to one wide SpectroscopyLine row.    |
//   runtimeControlsKeepStrongLineSidecars keeps sidecar storage only for unfiltered or O2 isotope-1 paths.   |
//                                                                                                            |
// boundary and hot path                                                                                      |
//   This file owns no storage, allocates nothing, and does not evaluate line shapes. Helpers take pointers   |
//   to SpectroscopyLine because the row is wide and most callers need only one or two metadata fields.       |
// -----------------------------------------------------------------------------------------------------------|

pub fn lineCenterWavenumberCm1(line: *const Types.SpectroscopyLine) f64 {
    return if (std.math.isFinite(line.center_wavenumber_cm1))
        line.center_wavenumber_cm1
    else
        PhysicsCore.wavelengthToWavenumberCm1(line.center_wavelength_nm);
}

pub fn lineAirHalfWidthCm1(line: *const Types.SpectroscopyLine) f64 {
    return if (std.math.isFinite(line.air_half_width_cm1))
        line.air_half_width_cm1
    else
        PhysicsCore.spectralWidthNmToCm1(line.air_half_width_nm, lineCenterWavenumberCm1(line));
}

pub fn linePressureShiftCm1(line: *const Types.SpectroscopyLine) f64 {
    return if (std.math.isFinite(line.pressure_shift_cm1))
        line.pressure_shift_cm1
    else
        -PhysicsCore.spectralWidthNmToCm1(line.pressure_shift_nm, lineCenterWavenumberCm1(line));
}

pub fn lineIndexIsStrongAnchor(anchor_indices: []const Types.StrongLineAnchorIndex, line_index: usize) bool {
    for (anchor_indices) |anchor| {
        if (anchor == Types.missing_strong_line_anchor_index) continue;
        if (@as(usize, @intCast(anchor)) == line_index) return true;
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

pub fn lineHasVendorStrongLineMetadata(line: *const Types.SpectroscopyLine) bool {
    return line.branch_ic1 != null and line.branch_ic2 != null and line.rotational_nf != null;
}

pub fn lineHasVendorStrongLineMetadataFromSource(line: *const Types.SpectroscopyLine) bool {
    return line.vendor_filter_metadata_from_source and lineHasVendorStrongLineMetadata(line);
}

pub fn wavenumberCm1ToWavelengthNm(wavenumber_cm1: f64) f64 {
    return 1.0e7 / @max(wavenumber_cm1, 1.0);
}

pub fn isVendorO2AStrongCandidate(line: *const Types.SpectroscopyLine) bool {
    return line.gas_index == 7 and
        line.isotope_number == 1 and
        line.branch_ic1 != null and
        line.branch_ic2 != null and
        line.rotational_nf != null and
        line.branch_ic1.? == 5 and
        line.branch_ic2.? == 1 and
        line.rotational_nf.? <= 35;
}

pub fn isVendorO2AStrongCandidateFromSource(line: *const Types.SpectroscopyLine) bool {
    return line.vendor_filter_metadata_from_source and isVendorO2AStrongCandidate(line);
}

pub fn runtimeControlsMatchLine(
    gas_index: ?u16,
    active_isotopes: []const u8,
    line: *const Types.SpectroscopyLine,
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
