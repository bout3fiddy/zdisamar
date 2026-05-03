const std = @import("std");
const atmospheric_budget = @import("atmospheric_budget.zig");
const Optics = @import("../forward_model/optical_properties/root.zig");
const RadiativeTransfer = @import("../forward_model/radiative_transfer/root.zig");
const Scene = @import("../input/Scene.zig").Scene;

const Allocator = std.mem.Allocator;
const PreparedOpticalState = Optics.PreparedOpticalState;

pub const SpectrumView = struct {
    wavelength_nm: []const f64,
    reflectance: []const f64,
    radiance: []const f64,
};

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

pub fn build(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    route: RadiativeTransfer.Route,
    wavelengths_nm: []const f64,
    spectrum: ?SpectrumView,
) ![]RadiativeTransferDiagnosticRow {
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
            route,
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
    route: RadiativeTransfer.Route,
    airmass: f64,
    spectrum: ?SpectrumView,
) void {
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
            .n_streams = route.rtm_controls.n_streams,
            .integrate_source_function = if (route.rtm_controls.integrate_source_function) 1 else 0,
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
    while (lower_index + 1 < resolved.wavelength_nm.len and resolved.wavelength_nm[lower_index + 1] < wavelength_nm) : (lower_index += 1) {}
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
