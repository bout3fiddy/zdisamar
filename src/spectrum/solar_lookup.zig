const std = @import("std");

const readers = @import("../assets/readers.zig");
const solar_irradiance_memory = @import("../cache/solar_irradiance_memory.zig");
const solar_table = @import("../setup/solar_table.zig");
const sampling_table = @import("sampling_table.zig");

pub const Error = error{
    EmptySolarTable,
    ShapeMismatch,
};

// solar_lookup.zig -------------------------------------------------------------------------------------------|
// Solar irradiance lookup and instrument-integration gather for the spectrum layer.                           |
//                                                                                                             |
// provenance                                                                                                  |
//   Source order and final floor port main:`src/input/reference_data/solar_irradiance.zig`. Operational       |
//   table interpolation ports main:`src/input/instrument/solar_spectrum.zig`; cached integration ports        |
//   main:`src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`.                              |
//                                                                                                             |
// route                                                                                                       |
//   SolarTable spline rows -> exact f64-bit SolarIrradianceMemory -> nominal irradiance integration           |
//                                                                                                             |
// key contract                                                                                                |
//   Cache keys use exact wavelength bits through `SolarIrradianceMemory`. Instrument offsets are never        |
//   rounded or binned, matching the old `SpectralEvaluationCache.keyFor` behavior.                            |
//                                                                                                             |
// allocation                                                                                                  |
//   `reserveIrradianceMemory` sizes the hash map for the active sampling table before hot gathers. The        |
//   `...AssumeCapacity` calls below only update retained entries and do not grow the map.                     |
// ------------------------------------------------------------------------------------------------------------|

// minimum_source_irradiance ----------------------------------------------------------------------------------|
// Positive floor applied after source selection.                                                              |
//                                                                                                             |
// provenance                                                                                                  |
//   Old `solar_irradiance.zig` returned `@max(source_irradiance, 1e-6)` before radiance scaling.              |
pub const minimum_source_irradiance: f64 = 1.0e-6;
// ------------------------------------------------------------------------------------------------------------|

pub fn irradianceAtWavelength(
    table: solar_table.SolarTable,
    wavelength_nm: f64,
) Error!f64 {
    // irradianceAtWavelength ---------------------------------------------------------------------------------|
    // Resolve one positive operational solar irradiance sample.                                               |
    //                                                                                                         |
    // source order                                                                                            |
    //   within table : prepared DISAMAR-compatible spline, or linear when no spline state exists              |
    //   below table  : clamp to first operational row                                                         |
    //   above table  : clamp to last operational row                                                          |
    //                                                                                                         |
    // numerical guard                                                                                         |
    //   The `1.0e-6` floor preserves the old downstream radiance/reflectance protection for invalid source    |
    //   data while still surfacing malformed setup tables during table construction.                          |
    // --------------------------------------------------------------------------------------------------------|
    const source_irradiance = interpolateWithinBounds(table, wavelength_nm) orelse clampIrradiance(
        table.rows,
        wavelength_nm,
    ) orelse return error.EmptySolarTable;

    return @max(source_irradiance, minimum_source_irradiance);
}

pub fn cachedIrradianceAtWavelengthAssumeCapacity(
    table: solar_table.SolarTable,
    memory: *solar_irradiance_memory.SolarIrradianceMemory,
    wavelength_nm: f64,
) Error!f64 {
    // cachedIrradianceAtWavelengthAssumeCapacity -------------------------------------------------------------|
    // Resolve one exact wavelength from retained solar memory, inserting the old-route value on misses.       |
    //                                                                                                         |
    // caller contract                                                                                         |
    //   Call `reserveIrradianceMemory` before the gather so `putAssumeCapacity` cannot allocate in the        |
    //   per-sample loop.                                                                                      |
    // --------------------------------------------------------------------------------------------------------|
    if (memory.get(wavelength_nm)) |cached| return cached;

    const irradiance = try irradianceAtWavelength(table, wavelength_nm);
    memory.putAssumeCapacity(wavelength_nm, irradiance);
    return irradiance;
}

pub fn reserveIrradianceMemory(
    memory: *solar_irradiance_memory.SolarIrradianceMemory,
    table: sampling_table.SpectrumSamplingTable,
) !void {
    // reserveIrradianceMemory --------------------------------------------------------------------------------|
    // Reserve one possible exact-key slot per irradiance integration sample before nominal gathers.           |
    // --------------------------------------------------------------------------------------------------------|
    try memory.reserve(irradianceSampleCount(table));
}

pub fn irradianceSampleCount(table: sampling_table.SpectrumSamplingTable) usize {
    // irradianceSampleCount ----------------------------------------------------------------------------------|
    // Count irradiance samples using the same direct/inline/side sample contract as the old sampling plan.    |
    // --------------------------------------------------------------------------------------------------------|
    var count: usize = 0;
    for (table.rows) |row| {
        count += row.irradiance_integration.activeSampleCount();
    }
    return count;
}

pub fn integrateIrradianceAtNominalAssumeCapacity(
    table: solar_table.SolarTable,
    memory: *solar_irradiance_memory.SolarIrradianceMemory,
    nominal_wavelength_nm: f64,
    integration: *const sampling_table.IntegrationKernelRef,
    storage: sampling_table.IntegrationKernelStorage,
) Error!f64 {
    // integrateIrradianceAtNominalAssumeCapacity -------------------------------------------------------------|
    // Gather calibrated solar irradiance for one nominal product wavelength.                                  |
    //                                                                                                         |
    // math                                                                                                    |
    //   direct     : E0(lambda_nominal)                                                                       |
    //   integrated : sum_j weight_j * E0(lambda_nominal + offset_j)                                           |
    //                                                                                                         |
    // route parity                                                                                            |
    //   This ports old `spectral_eval.zig` `integrateIrradianceAtNominal`: the disabled kernel samples the    |
    //   nominal wavelength directly, while enabled kernels add offsets before exact-key cache lookup.         |
    // --------------------------------------------------------------------------------------------------------|
    try validateKernelStorage(integration, storage);

    if (!integration.enabled()) {
        return cachedIrradianceAtWavelengthAssumeCapacity(table, memory, nominal_wavelength_nm);
    }

    var integrated: f64 = 0.0;
    const sample_count = integration.activeSampleCount();
    for (0..sample_count) |sample_index| {
        const wavelength_nm = nominal_wavelength_nm + integration.offsetNm(storage, sample_index);
        const irradiance = try cachedIrradianceAtWavelengthAssumeCapacity(table, memory, wavelength_nm);
        integrated += integration.weight(storage, sample_index) * irradiance;
    }
    return integrated;
}

pub fn interpolateWithinBounds(
    table: solar_table.SolarTable,
    wavelength_nm: f64,
) ?f64 {
    // interpolateWithinBounds --------------------------------------------------------------------------------|
    // Interpolate inside the operational solar table and return null outside so callers own fallback choice.  |
    // --------------------------------------------------------------------------------------------------------|
    if (table.rows.len == 0) return null;
    if (wavelength_nm < table.rows[0].wavelength_nm) return null;
    if (wavelength_nm > table.rows[table.rows.len - 1].wavelength_nm) return null;

    const has_prepared_spline =
        table.spline_second_derivatives.len == table.rows.len and table.rows.len >= 3;
    if (has_prepared_spline) {
        return interpolatePreparedSplineWithinBounds(
            table.rows,
            table.spline_second_derivatives,
            wavelength_nm,
        );
    }

    return interpolateLinearWithinBounds(table.rows, wavelength_nm);
}

fn interpolatePreparedSplineWithinBounds(
    rows: []const readers.SolarAssetRow,
    second_derivatives: []const f64,
    wavelength_nm: f64,
) f64 {
    // interpolatePreparedSplineWithinBounds ------------------------------------------------------------------|
    // Bracket one wavelength and evaluate old DISAMAR-compatible prepared spline state in Horner form.        |
    //                                                                                                         |
    // math                                                                                                    |
    //   E0(lambda) = E0_left + dx * (b + dx * (second_left / 2 + dx * d))                                     |
    //                                                                                                         |
    //   b = (E0_right - E0_left) / span - (2 * second_left + second_right) * span / 6                         |
    //   d = (second_right - second_left) / (6 * span)                                                         |
    // --------------------------------------------------------------------------------------------------------|
    if (wavelength_nm == rows[0].wavelength_nm) return rows[0].irradiance;
    if (wavelength_nm == rows[rows.len - 1].wavelength_nm) return rows[rows.len - 1].irradiance;

    var lower_index: usize = 0;
    var upper_index: usize = rows.len - 1;
    while (upper_index - lower_index > 1) {
        const middle_index = (upper_index + lower_index) / 2;
        if (rows[middle_index].wavelength_nm > wavelength_nm) {
            upper_index = middle_index;
        } else {
            lower_index = middle_index;
        }
    }

    const span_nm = rows[upper_index].wavelength_nm - rows[lower_index].wavelength_nm;
    if (span_nm == 0.0) return rows[upper_index].irradiance;

    const dx_nm = wavelength_nm - rows[lower_index].wavelength_nm;
    const slope_term = (rows[upper_index].irradiance - rows[lower_index].irradiance) / span_nm -
        (2.0 * second_derivatives[lower_index] + second_derivatives[upper_index]) * span_nm / 6.0;
    const cubic_term = (second_derivatives[upper_index] - second_derivatives[lower_index]) / (6.0 * span_nm);
    return rows[lower_index].irradiance +
        dx_nm * (slope_term + dx_nm * (second_derivatives[lower_index] / 2.0 + dx_nm * cubic_term));
}

fn interpolateLinearWithinBounds(
    rows: []const readers.SolarAssetRow,
    wavelength_nm: f64,
) ?f64 {
    // interpolateLinearWithinBounds --------------------------------------------------------------------------|
    // Linear fallback used only when setup supplied fewer than three solar rows or no prepared spline state.  |
    // --------------------------------------------------------------------------------------------------------|
    if (rows.len == 0) return null;
    if (wavelength_nm < rows[0].wavelength_nm) return null;
    if (wavelength_nm == rows[0].wavelength_nm) return rows[0].irradiance;

    for (
        rows[0 .. rows.len - 1],
        rows[1..],
    ) |left, right| {
        if (wavelength_nm <= right.wavelength_nm) {
            const span_nm = right.wavelength_nm - left.wavelength_nm;
            if (span_nm == 0.0) return right.irradiance;

            const weight = (wavelength_nm - left.wavelength_nm) / span_nm;
            return left.irradiance + weight * (right.irradiance - left.irradiance);
        }
    }

    if (wavelength_nm == rows[rows.len - 1].wavelength_nm) return rows[rows.len - 1].irradiance;
    return null;
}

fn clampIrradiance(
    rows: []const readers.SolarAssetRow,
    wavelength_nm: f64,
) ?f64 {
    // clampIrradiance ----------------------------------------------------------------------------------------|
    // Preserve old operational-table behavior outside the prepared wavelength support.                        |
    // --------------------------------------------------------------------------------------------------------|
    if (rows.len == 0) return null;
    if (wavelength_nm <= rows[0].wavelength_nm) return rows[0].irradiance;
    return rows[rows.len - 1].irradiance;
}

fn validateKernelStorage(
    integration: *const sampling_table.IntegrationKernelRef,
    storage: sampling_table.IntegrationKernelStorage,
) Error!void {
    // validateKernelStorage ----------------------------------------------------------------------------------|
    // Reject malformed kernel refs before offset/weight reads can index outside their side arrays.            |
    // --------------------------------------------------------------------------------------------------------|
    const sample_count = integration.activeSampleCount();
    switch (integration.encoding) {
        .disabled => return,
        .inline_samples => {
            if (sample_count > sampling_table.inline_integration_sample_count) return error.ShapeMismatch;
        },
        .side_samples => {
            const start: usize = @intCast(integration.side_start);
            const available_offsets = storage.offsets_nm.len -| start;
            const available_weights = storage.weights.len -| start;

            if (sample_count > available_offsets) return error.ShapeMismatch;
            if (sample_count > available_weights) return error.ShapeMismatch;
        },
    }
}
