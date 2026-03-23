const std = @import("std");
const AbsorberModel = @import("../../../model/Absorber.zig");
const ReferenceData = @import("../../../model/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../model/Instrument.zig").OperationalCrossSectionLut;
const Scene = @import("../../../model/Scene.zig").Scene;
const OperationalO2 = @import("operational_o2.zig");
const State = @import("state.zig");

const Allocator = std.mem.Allocator;
const default_no2_volume_mixing_ratio = 5.0e-8;

pub fn collectActiveLineAbsorbers(allocator: Allocator, scene: *const Scene) ![]State.ActiveLineAbsorber {
    var active = std.ArrayList(State.ActiveLineAbsorber).empty;
    defer active.deinit(allocator);

    for (scene.absorbers.items) |absorber| {
        const species = resolvedAbsorberSpecies(absorber) orelse continue;
        if (!species.isLineAbsorbing()) continue;
        if (absorber.spectroscopy.mode != .line_by_line) continue;
        try active.append(allocator, .{
            .species = species,
            .controls = absorber.spectroscopy.line_gas_controls,
            .volume_mixing_ratio_profile_ppmv = absorber.volume_mixing_ratio_profile_ppmv,
        });
    }
    return active.toOwnedSlice(allocator);
}

pub fn resolvedAbsorberSpecies(absorber: AbsorberModel.Absorber) ?AbsorberModel.AbsorberSpecies {
    if (absorber.resolved_species) |species| return species;
    if (std.meta.stringToEnum(AbsorberModel.AbsorberSpecies, absorber.species)) |species| return species;
    if (std.ascii.eqlIgnoreCase(absorber.species, "o2o2")) return .o2_o2;
    if (std.ascii.eqlIgnoreCase(absorber.species, "o2-o2")) return .o2_o2;
    return null;
}

pub fn resolveActiveLineSpecies(
    active_line_absorber: ?State.ActiveLineAbsorber,
    line_list: ?ReferenceData.SpectroscopyLineList,
    operational_o2_lut: OperationalCrossSectionLut,
) ?AbsorberModel.AbsorberSpecies {
    if (active_line_absorber) |line_absorber| return line_absorber.species;
    if (operational_o2_lut.enabled()) return .o2;
    const spectroscopy_lines = line_list orelse return null;
    if (spectroscopy_lines.runtime_controls.gas_index) |gas_index| {
        return speciesForHitranIndex(gas_index);
    }
    return inferLineSpecies(spectroscopy_lines.lines);
}

pub fn resolveContinuumOwnerSpecies(
    active_line_species: ?AbsorberModel.AbsorberSpecies,
    line_absorbers: []const State.PreparedLineAbsorber,
    operational_o2_lut: OperationalCrossSectionLut,
) ?AbsorberModel.AbsorberSpecies {
    if (operational_o2_lut.enabled()) return .o2;
    if (active_line_species) |species| return species;
    if (line_absorbers.len == 1) return line_absorbers[0].species;
    for (line_absorbers) |line_absorber| {
        if (line_absorber.species == .o2) return .o2;
    }
    return null;
}

pub fn operationalO2EvaluationAtWavelength(
    operational_o2_lut: OperationalCrossSectionLut,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) ReferenceData.SpectroscopyEvaluation {
    return OperationalO2.operationalO2EvaluationAtWavelength(
        operational_o2_lut,
        wavelength_nm,
        temperature_k,
        pressure_hpa,
    );
}

pub fn speciesMixingRatioAtPressure(
    scene: *const Scene,
    species: AbsorberModel.AbsorberSpecies,
    explicit_profile_ppmv: []const [2]f64,
    pressure_hpa: f64,
    default_fraction: ?f64,
) ?f64 {
    const profile_ppmv = if (explicit_profile_ppmv.len != 0)
        explicit_profile_ppmv
    else if (findAbsorberBySpecies(scene, species)) |absorber|
        absorber.volume_mixing_ratio_profile_ppmv
    else
        &.{};
    if (profile_ppmv.len != 0) {
        return interpolateMixingRatioProfileFraction(profile_ppmv, pressure_hpa);
    }
    return default_fraction orelse defaultVolumeMixingRatioForScene(scene, species);
}

pub fn defaultVolumeMixingRatio(species: AbsorberModel.AbsorberSpecies) ?f64 {
    return switch (species) {
        .no2, .trop_no2, .strat_no2 => default_no2_volume_mixing_ratio,
        else => null,
    };
}

fn defaultVolumeMixingRatioForScene(
    scene: *const Scene,
    species: AbsorberModel.AbsorberSpecies,
) ?f64 {
    return switch (species) {
        .trop_no2, .strat_no2 => if (usesSplitNo2PartitionFallback(scene))
            default_no2_volume_mixing_ratio * 0.5
        else
            default_no2_volume_mixing_ratio,
        else => defaultVolumeMixingRatio(species),
    };
}

fn inferLineSpecies(lines: []const ReferenceData.SpectroscopyLine) ?AbsorberModel.AbsorberSpecies {
    if (lines.len == 0) return null;
    const first_gas_index = lines[0].gas_index;
    if (first_gas_index == 0) return null;
    for (lines[1..]) |line| {
        if (line.gas_index != first_gas_index) return null;
    }
    return speciesForHitranIndex(first_gas_index);
}

fn speciesForHitranIndex(gas_index: u16) ?AbsorberModel.AbsorberSpecies {
    return switch (gas_index) {
        1 => .h2o,
        2 => .co2,
        5 => .co,
        6 => .ch4,
        7 => .o2,
        10 => .no2,
        11 => .nh3,
        else => null,
    };
}

fn findAbsorberBySpecies(
    scene: *const Scene,
    species: AbsorberModel.AbsorberSpecies,
) ?*const AbsorberModel.Absorber {
    for (scene.absorbers.items) |*absorber| {
        if (resolvedAbsorberSpecies(absorber.*) == species) return absorber;
    }
    return null;
}

fn usesSplitNo2PartitionFallback(scene: *const Scene) bool {
    const trop = findAbsorberBySpecies(scene, .trop_no2) orelse return false;
    const strat = findAbsorberBySpecies(scene, .strat_no2) orelse return false;
    return trop.volume_mixing_ratio_profile_ppmv.len == 0 and
        strat.volume_mixing_ratio_profile_ppmv.len == 0;
}

fn interpolateMixingRatioProfileFraction(profile_ppmv: []const [2]f64, pressure_hpa: f64) f64 {
    if (profile_ppmv.len == 0) return 0.0;
    const safe_pressure_hpa = @max(pressure_hpa, 0.0);
    if (profile_ppmv.len == 1) return ppmvToFraction(profile_ppmv[0][1]);

    const first_pressure_hpa = profile_ppmv[0][0];
    const last_pressure_hpa = profile_ppmv[profile_ppmv.len - 1][0];
    const descending = first_pressure_hpa >= last_pressure_hpa;
    if ((descending and safe_pressure_hpa >= first_pressure_hpa) or
        (!descending and safe_pressure_hpa <= first_pressure_hpa))
    {
        return ppmvToFraction(profile_ppmv[0][1]);
    }
    if ((descending and safe_pressure_hpa <= last_pressure_hpa) or
        (!descending and safe_pressure_hpa >= last_pressure_hpa))
    {
        return ppmvToFraction(profile_ppmv[profile_ppmv.len - 1][1]);
    }

    for (profile_ppmv[0 .. profile_ppmv.len - 1], profile_ppmv[1..]) |left, right| {
        const in_segment = if (descending)
            safe_pressure_hpa <= left[0] and safe_pressure_hpa >= right[0]
        else
            safe_pressure_hpa >= left[0] and safe_pressure_hpa <= right[0];
        if (!in_segment) continue;

        const span = right[0] - left[0];
        if (span == 0.0) return ppmvToFraction(right[1]);
        const weight = (safe_pressure_hpa - left[0]) / span;
        return ppmvToFraction(left[1] + weight * (right[1] - left[1]));
    }

    return ppmvToFraction(profile_ppmv[profile_ppmv.len - 1][1]);
}

fn ppmvToFraction(value_ppmv: f64) f64 {
    return @max(value_ppmv, 0.0) * 1.0e-6;
}
