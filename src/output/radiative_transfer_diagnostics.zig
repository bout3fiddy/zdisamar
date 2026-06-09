const std = @import("std");
const atmospheric_budget = @import("atmospheric_budget.zig");
const Optics = @import("../forward_model/optical_properties/root.zig");
const RadiativeTransfer = @import("../forward_model/radiative_transfer/root.zig");
const Scene = @import("../input/Scene.zig").Scene;

const Allocator = std.mem.Allocator;
const PreparedOpticalState = Optics.PreparedOpticalState;

// radiative_transfer_diagnostics.zig -------------------------------------------------------------------------|
// Builds RT diagnostic rows by joining atmospheric-budget rows with optional final spectrum columns.          |
//                                                                                                             |
// main paths                                                                                                  |
//   build              allocates diagnostics for all budget rows and groups them by wavelength                |
//   fillWavelengthRows walks one wavelength's vertical rows and accumulates optical depth above               |
//   interpolateSpectrum samples final radiance or reflectance from an optional spectrum view                  |
//                                                                                                             |
// memory                                                                                                      |
//   SpectrumView borrows caller-owned slices. The returned diagnostic row slice is owned by the caller.       |
// ------------------------------------------------------------------------------------------------------------|

// SpectrumView -----------------------------------------------------------------------------------------------|
// Borrows final spectrum columns used to attach reflectance and radiance to diagnostic rows.                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelength_nm : []const f64                                                                        |
// [16..31] reflectance   : []const f64                                                                        |
// [32..47] radiance      : []const f64                                                                        |
//                                                                                                             |
// out-of-line: slices borrow caller-owned arrays; referenced storage is not included in size                  |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 48 B (0.047 KiB); total also includes borrowed storage above                      |
pub const SpectrumView = struct {
    wavelength_nm: []const f64,
    reflectance: []const f64,
    radiance: []const f64,
};
// ------------------------------------------------------------------------------------------------------------|

// RadiativeTransferDiagnosticRow -----------------------------------------------------------------------------|
// Stores one RT diagnostic row for one wavelength and one layer or sublayer.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 136 B (0.133 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] wavelength_nm                       : f64                                                        |
// [  8.. 15] altitude_km                         : f64                                                        |
// [ 16.. 23] total_optical_depth                 : f64                                                        |
// [ 24.. 31] total_absorption_optical_depth      : f64                                                        |
// [ 32.. 39] total_scattering_optical_depth      : f64                                                        |
// [ 40.. 47] single_scatter_albedo               : f64                                                        |
// [ 48.. 55] cumulative_optical_depth_above      : f64                                                        |
// [ 56.. 63] mid_layer_transmission_proxy        : f64                                                        |
// [ 64.. 71] direct_surface_transmission_proxy   : f64                                                        |
// [ 72.. 79] atmospheric_scattering_source_proxy : f64                                                        |
// [ 80.. 87] absorption_loss_proxy               : f64                                                        |
// [ 88.. 95] pseudo_spherical_airmass_factor     : f64                                                        |
// [ 96..103] final_reflectance                   : f64                                                        |
// [104..111] final_radiance                      : f64                                                        |
// [112..115] layer_index                         : u32                                                        |
// [116..119] sublayer_index                      : u32                                                        |
// [120..123] global_sublayer_index               : u32                                                        |
// [124..127] interval_index_1based               : u32                                                        |
// [128..131] n_streams                           : u32                                                        |
// [132..132] integrate_source_function           : u8                                                         |
// [133..135] trailing padding                                                                                 |
//                                                                                                             |
// unused bits: 24 padding + 0 bool-storage slack = 24 bits                                                    |
// footprint: per instance = 136 B (0.133 KiB); total = per instance * live instance count                     |
pub const RadiativeTransferDiagnosticRow = struct {
    wavelength_nm: f64,
    layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32,
    interval_index_1based: u32,
    altitude_km: f64,
    total_optical_depth: f64,
    total_absorption_optical_depth: f64,
    total_scattering_optical_depth: f64,
    single_scatter_albedo: f64,
    cumulative_optical_depth_above: f64,
    mid_layer_transmission_proxy: f64,
    direct_surface_transmission_proxy: f64,
    atmospheric_scattering_source_proxy: f64,
    absorption_loss_proxy: f64,
    pseudo_spherical_airmass_factor: f64,
    n_streams: u32,
    integrate_source_function: u8,
    final_reflectance: f64,
    final_radiance: f64,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    rtm_config: RadiativeTransfer.SolveConfig,
    wavelengths_nm: []const f64,
    spectrum: ?SpectrumView,
) ![]RadiativeTransferDiagnosticRow {
    // build --------------------------------------------------------------------------------------------------|
    // Builds RT diagnostic rows from atmospheric-budget rows and optional final spectrum columns.             |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : radiative-transfer diagnostics after a forward run                                         |
    //   costly   : atmospheric_budget.build plus one vertical pass per wavelength                             |
    //   memory   : temporary budget slice plus caller-owned diagnostic output slice                           |
    //                                                                                                         |
    // calls                                                                                                   |
    //   atmospheric_budget.build                                                                              |
    //   fillWavelengthRows                                                                                    |
    // --------------------------------------------------------------------------------------------------------|

    const budget = try atmospheric_budget.build(allocator, scene, prepared, wavelengths_nm);
    defer allocator.free(budget);

    const rows = try allocator.alloc(RadiativeTransferDiagnosticRow, budget.len);
    errdefer allocator.free(rows);

    const airmass = airmassFactor(scene);
    var row_index: usize = 0;
    while (row_index < budget.len) {
        const wavelength_nm = budget[row_index].wavelength_nm;
        var end_index = row_index;
        while (end_index < budget.len and budget[end_index].wavelength_nm == wavelength_nm) : (end_index += 1) {}
        fillWavelengthRows(
            budget[row_index..end_index],
            rows[row_index..end_index],
            rtm_config,
            airmass,
            spectrum,
        );
        row_index = end_index;
    }

    return rows;
}

fn fillWavelengthRows(
    budget: []const atmospheric_budget.AtmosphericBudgetRow,
    rows: []RadiativeTransferDiagnosticRow,
    rtm_config: RadiativeTransfer.SolveConfig,
    airmass: f64,
    spectrum: ?SpectrumView,
) void {
    // fillWavelengthRows -------------------------------------------------------------------------------------|
    // Derives RT proxy columns for one wavelength group while walking vertical rows top to bottom.            |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : once per unique wavelength in the budget table                                             |
    //   costly   : exponential transmission proxies and optional final-spectrum interpolation                 |
    //   memory   : reads budget slice and writes caller-owned row slice                                       |
    //                                                                                                         |
    // math                                                                                                    |
    //   mid-depth transmission proxy = exp(-airmass * (cumulative + 0.5 * optical_depth))                     |
    // --------------------------------------------------------------------------------------------------------|

    var cumulative: f64 = 0.0;
    for (budget, rows) |source, *target| {
        const optical_depth = @max(source.total_optical_depth, 0.0);
        const mid_depth = cumulative + 0.5 * optical_depth;
        const transmission = @exp(-airmass * mid_depth);
        target.* = .{
            .wavelength_nm = source.wavelength_nm,
            .layer_index = source.layer_index,
            .sublayer_index = source.sublayer_index,
            .global_sublayer_index = source.global_sublayer_index,
            .interval_index_1based = source.interval_index_1based,
            .altitude_km = source.altitude_km,
            .total_optical_depth = source.total_optical_depth,
            .total_absorption_optical_depth = source.total_absorption_optical_depth,
            .total_scattering_optical_depth = source.total_scattering_optical_depth,
            .single_scatter_albedo = source.single_scatter_albedo,
            .cumulative_optical_depth_above = cumulative,
            .mid_layer_transmission_proxy = transmission,
            .direct_surface_transmission_proxy = @exp(-airmass * (cumulative + optical_depth)),
            .atmospheric_scattering_source_proxy = source.total_scattering_optical_depth * transmission,
            .absorption_loss_proxy = source.total_absorption_optical_depth * transmission,
            .pseudo_spherical_airmass_factor = airmass,
            .n_streams = rtm_config.rtm_controls.n_streams,
            .integrate_source_function = if (rtm_config.rtm_controls.integrate_source_function) 1 else 0,
            .final_reflectance = interpolateSpectrum(spectrum, .reflectance, source.wavelength_nm),
            .final_radiance = interpolateSpectrum(spectrum, .radiance, source.wavelength_nm),
        };
        cumulative += optical_depth;
    }
}

const SpectrumColumn = enum {
    reflectance,
    radiance,
};

fn interpolateSpectrum(spectrum: ?SpectrumView, column: SpectrumColumn, wavelength_nm: f64) f64 {
    const resolved = spectrum orelse return std.math.nan(f64);
    const values = switch (column) {
        .reflectance => resolved.reflectance,
        .radiance => resolved.radiance,
    };

    if (resolved.wavelength_nm.len == 0 or values.len == 0) return std.math.nan(f64);
    if (wavelength_nm <= resolved.wavelength_nm[0]) return values[0];
    const last_index = @min(resolved.wavelength_nm.len, values.len) - 1;
    if (wavelength_nm >= resolved.wavelength_nm[last_index]) return values[last_index];

    var lower_index: usize = 0;
    while (lower_index + 1 < resolved.wavelength_nm.len and
        resolved.wavelength_nm[lower_index + 1] < wavelength_nm) : (lower_index += 1)
    {}
    const upper_index = lower_index + 1;
    const lower_wavelength = resolved.wavelength_nm[lower_index];
    const upper_wavelength = resolved.wavelength_nm[upper_index];
    const denominator = upper_wavelength - lower_wavelength;
    if (denominator == 0.0) return values[upper_index];
    const blend = (wavelength_nm - lower_wavelength) / denominator;
    return values[lower_index] + blend * (values[upper_index] - values[lower_index]);
}

fn airmassFactor(scene: *const Scene) f64 {
    const mu0 = @max(scene.geometry.solarCosineAtAltitude(0.0), 0.05);
    const muv = @max(scene.geometry.viewingCosineAtAltitude(0.0), 0.05);
    return (1.0 / mu0) + (1.0 / muv);
}
