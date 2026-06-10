const AbsorberModel = @import("../../../input/Absorber.zig");
const ReferenceData = @import("../../../input/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;
const Scene = @import("../../../input/Scene.zig").Scene;
const OperationalO2 = @import("operational_o2.zig");
const State = @import("state.zig");

pub const default_o2_volume_mixing_ratio = 0.20946;

// spectroscopy.zig -------------------------------------------------------------------------------------------|
// Resolves absorber spectroscopy metadata while Context is still turning a Scene into prepared optical rows.  |
// This is the species/ownership front door: it normalizes absorber species names, decides which line species  |
// is being prepared, which species owns continuum density, and what volume-mixing-ratio fraction applies at   |
// a pressure. Wavelength-dependent line-shape math lives in layer_spectroscopy.zig, state_spectroscopy.zig,   |
// and carrier_eval.zig, not here.                                                                             |
//                                                                                                             |
// build route                                                                                                 |
//   absorbers.zig owns active absorber collection and prepared row allocation. After prepared line rows or    |
//   operational O2 LUTs exist, it calls resolveActiveLineSpecies and resolveContinuumOwnerSpecies before      |
//   finalize.zig moves the results into PreparedOpticalState. layer_accumulation.zig and layer_spectroscopy   |
//   call speciesMixingRatioAtPressure while filling support-row density columns.                              |
//                                                                                                             |
// main paths                                                                                                  |
//   resolvedAbsorberSpecies           : shared mapping from input absorber controls to typed species          |
//   resolveActiveLineSpecies           : active line species from scene controls, O2 LUT, or HITRAN metadata  |
//   resolveContinuumOwnerSpecies       : continuum owner when line ownership is loose                         |
//   speciesMixingRatioAtPressure       : explicit or scene-level VMR profile interpolation at pressure        |
//                                                                                                             |
// boundary shape                                                                                              |
//   This file interprets scene/reference metadata and returns setup decisions. It does not prepare HITRAN     |
//   sidecars, evaluate line shapes, fill RTM layers, or silently invent unsupported species. Unknown HITRAN   |
//   gases become typed errors at the points where a concrete species is required.                             |
//                                                                                                             |
// row handoff                                                                                                 |
//   Active* rows are short-lived setup descriptors. PreparedLineAbsorber rows are built in absorbers.zig and  |
//   defined in state.zig; this file only inspects their species tags while choosing the continuum owner.      |
//   Later evaluation modules consume the same prepared rows for density weighting and spectroscopy lookup.    |
//                                                                                                             |
// memory                                                                                                      |
//   Helpers return optional species or scalar fractions. They borrow scene profiles, line lists, and prepared |
//   absorber rows; they do not allocate, retain scene pointers, or own hidden state.                          |
//                                                                                                             |
// hot path                                                                                                    |
//   These helpers run during setup, not inside per-wavelength RTM kernels. The only wide-row scan reads       |
//   PreparedLineAbsorber.species at [272..272] from 280 B rows while choosing the continuum owner; keeping    |
//   species beside the prepared line payload avoids a parallel column that every owner/deinit path would need |
//   to maintain.                                                                                              |
// ------------------------------------------------------------------------------------------------------------|

pub fn resolvedAbsorberSpecies(absorber: AbsorberModel.Absorber) ?AbsorberModel.AbsorberSpecies {
    return AbsorberModel.resolvedAbsorberSpecies(absorber);
}

pub fn resolveActiveLineSpecies(
    active_line_absorber: ?State.ActiveLineAbsorber,
    line_list: ?ReferenceData.SpectroscopyLineList,
    operational_o2_lut: OperationalCrossSectionLut,
) !?AbsorberModel.AbsorberSpecies {
    // resolveActiveLineSpecies -------------------------------------------------------------------------------|
    // Resolve the line-absorbing species for the single-line-list preparation route.                          |
    //                                                                                                         |
    // decision order                                                                                          |
    //   explicit active absorber species wins first                                                           |
    //   operational O2 LUT implies O2 even without a line-list owner                                          |
    //   runtime HITRAN gas_index wins when present                                                            |
    //   otherwise infer from uniform non-zero line.gas_index values                                           |
    //                                                                                                         |
    // boundary                                                                                                |
    //   Unsupported concrete HITRAN gases return UnsupportedSpectroscopyConfiguration instead of silently     |
    //   becoming O2 or an inert line list. Mixed or empty lists return null because no single species owns    |
    //   the line-list density.                                                                                |
    // --------------------------------------------------------------------------------------------------------|

    if (active_line_absorber) |line_absorber| return line_absorber.species;

    if (operational_o2_lut.enabled()) return .o2;

    const spectroscopy_lines = line_list orelse return null;

    if (spectroscopy_lines.runtime_controls.gas_index) |gas_index| {
        return speciesForHitranIndex(gas_index) orelse error.UnsupportedSpectroscopyConfiguration;
    }

    return try inferLineSpecies(spectroscopy_lines.lines);
}

pub fn resolveContinuumOwnerSpecies(
    active_line_species: ?AbsorberModel.AbsorberSpecies,
    line_absorbers: []const State.PreparedLineAbsorber,
    operational_o2_lut: OperationalCrossSectionLut,
) ?AbsorberModel.AbsorberSpecies {
    // resolveContinuumOwnerSpecies ---------------------------------------------------------------------------|
    // Choose which line-absorber species owns continuum density when scene controls did not name one.         |
    //                                                                                                         |
    // call path                                                                                               |
    //   absorbers.zig calls this once while assembling PreparedOpticalState, before wavelength evaluation.    |
    //                                                                                                         |
    // decision order                                                                                          |
    //   operational O2 LUT owns continuum when enabled.                                                       |
    //   explicit active line species wins next.                                                               |
    //   a single prepared line absorber owns its own continuum.                                               |
    //   otherwise O2 is preferred if one prepared line absorber is O2.                                        |
    //                                                                                                         |
    // memory                                                                                                  |
    //   The fallback scan reads only PreparedLineAbsorber.species at [272..272] of each 280 B row. Pointer    |
    //   capture avoids copying the row, and this setup-time choice is not repeated per wavelength. A side     |
    //   species column would add ownership/deinit surface for one rare ambiguous-continuum decision.          |
    // --------------------------------------------------------------------------------------------------------|

    if (operational_o2_lut.enabled()) return .o2;

    if (active_line_species) |species| return species;

    if (line_absorbers.len == 1) return line_absorbers[0].species;

    for (line_absorbers) |*line_absorber| {
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
    // speciesMixingRatioAtPressure ---------------------------------------------------------------------------|
    // Resolve a species volume-mixing-ratio fraction at one pressure level.                                   |
    //                                                                                                         |
    // call path                                                                                               |
    //   layer_accumulation and layer_spectroscopy call this while filling density columns for support rows.   |
    //                                                                                                         |
    // decision order                                                                                          |
    //   explicit absorber profile wins first                                                                  |
    //   matching scene absorber profile is used next                                                          |
    //   default_fraction is returned when no profile is available                                             |
    //                                                                                                         |
    // memory                                                                                                  |
    //   Profile slices are borrowed. The interpolation walk streams [pressure_hpa, ppmv] pairs and returns a  |
    //   scalar fraction; no allocation or retained cache is created.                                          |
    // --------------------------------------------------------------------------------------------------------|

    const profile_ppmv = choose_profile: {
        if (explicit_profile_ppmv.len != 0) break :choose_profile explicit_profile_ppmv;

        if (findAbsorberBySpecies(scene, species)) |absorber| {
            break :choose_profile absorber.volume_mixing_ratio_profile_ppmv;
        }

        break :choose_profile &.{};
    };

    if (profile_ppmv.len != 0) {
        return interpolateMixingRatioProfileFraction(profile_ppmv, pressure_hpa);
    }

    return default_fraction;
}

fn inferLineSpecies(lines: []const ReferenceData.SpectroscopyLine) !?AbsorberModel.AbsorberSpecies {
    // inferLineSpecies ---------------------------------------------------------------------------------------|
    // Infer a single line species from retained spectroscopy line metadata.                                   |
    //                                                                                                         |
    // boundary                                                                                                |
    //   Empty, gas_index=0, or mixed-gas line lists return null because no single density owner can be        |
    //   inferred. A uniform but unsupported HITRAN gas index becomes a typed configuration error.             |
    // --------------------------------------------------------------------------------------------------------|

    if (lines.len == 0) return null;

    const first_gas_index = lines[0].gas_index;

    if (first_gas_index == 0) return null;

    for (lines[1..]) |line| {
        if (line.gas_index != first_gas_index) return null;
    }

    return speciesForHitranIndex(first_gas_index) orelse error.UnsupportedSpectroscopyConfiguration;
}

fn speciesForHitranIndex(gas_index: u16) ?AbsorberModel.AbsorberSpecies {
    return switch (gas_index) {
        7 => .o2,
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

fn interpolateMixingRatioProfileFraction(profile_ppmv: []const [2]f64, pressure_hpa: f64) f64 {
    // interpolateMixingRatioProfileFraction ------------------------------------------------------------------|
    // Linearly interpolate a pressure/ppmv profile at one pressure and convert the result to a fraction.      |
    //                                                                                                         |
    // shape                                                                                                   |
    //   Profile pressure can be ascending or descending. Values outside the profile range clamp to the        |
    //   nearest endpoint. Duplicate pressure bounds choose the right endpoint value for that segment.         |
    //                                                                                                         |
    // math                                                                                                    |
    //   fraction = max(ppmv, 0) * 1.0e-6                                                                      |
    // --------------------------------------------------------------------------------------------------------|

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
