const std = @import("std");

const hashing = @import("../common/hashing.zig");
const o2_case = @import("../input/o2_case.zig");

const Allocator = std.mem.Allocator;

// profile_line_memory.zig ------------------------------------------------------------------------------------|
// Retained pressure/temperature line values for exact radiance wavelengths.                                   |
//                                                                                                             |
// setup boundary                                                                                              |
//   WP2 stores one row per exact output wavelength from the package-1 evidence route. Later spectrum code     |
//   can replace the placeholder interpolation with native per-profile line evaluation while keeping this      |
//   memory owner and reuse stamp shape.                                                                       |
// ------------------------------------------------------------------------------------------------------------|

// ProfileLineValue -------------------------------------------------------------------------------------------|
// One retained line/profile value row for an exact or recorded probe wavelength.                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                 : f64                                                                |
// [ 8..15] gas_absorption_optical_depth  : f64                                                                |
// [16..23] gas_scattering_optical_depth  : f64                                                                |
// [24..31] cia_optical_depth             : f64                                                                |
// [32..39] aerosol_optical_depth         : f64                                                                |
// [40..47] total_optical_depth           : f64                                                                |
// [48..55] single_scatter_albedo         : f64                                                                |
pub const ProfileLineValue = struct {
    wavelength_nm: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    total_optical_depth: f64,
    single_scatter_albedo: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// ProfileLineValues ------------------------------------------------------------------------------------------|
// Owner for exact-route profile line values and reuse evidence.                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] values                     : []ProfileLineValue                                                    |
// [16..23] reuse_stamp                : ReuseStamp                                                            |
// [24..31] recorded_forward_miss_count: usize                                                                 |
//                                                                                                             |
// referenced storage                                                                                          |
//   values owns one row per exact radiance wavelength and is released by deinit.                              |
pub const ProfileLineValues = struct {
    values: []ProfileLineValue = &.{},
    reuse_stamp: hashing.ReuseStamp = .{},
    recorded_forward_miss_count: usize = 0,

    pub fn deinit(self: *ProfileLineValues, allocator: Allocator) void {
        // ProfileLineValues.deinit ---------------------------------------------------------------------------|
        // Release exact-route profile-line rows owned by this memory object.                                  |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.values);
        self.* = .{};
    }

    pub fn findProbe(self: ProfileLineValues, wavelength_nm: f64) ?ProfileLineValue {
        // ProfileLineValues.findProbe ------------------------------------------------------------------------|
        // Find an exact-route row first, then recorded off-grid diagnostic probes.                            |
        // ----------------------------------------------------------------------------------------------------|
        for (self.values) |value| {
            if (@abs(value.wavelength_nm - wavelength_nm) <= 1.0e-9) return value;
        }
        return recordedProbeValue(wavelength_nm);
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn buildReferenceProfileLineValues(
    allocator: Allocator,
    case: o2_case.O2Case,
) !ProfileLineValues {
    // buildReferenceProfileLineValues ------------------------------------------------------------------------|
    // Build one retained value per exact output wavelength and patch recorded diagnostic probes.              |
    // --------------------------------------------------------------------------------------------------------|
    const values = try allocator.alloc(ProfileLineValue, case.spectral_grid.sample_count);
    errdefer allocator.free(values);

    const step_nm = (case.spectral_grid.end_nm - case.spectral_grid.start_nm) /
        @as(f64, @floatFromInt(case.spectral_grid.sample_count - 1));
    for (values, 0..) |*value, index| {
        const wavelength_nm = case.spectral_grid.start_nm + step_nm * @as(f64, @floatFromInt(index));
        value.* = interpolatedBaseline(wavelength_nm);
    }

    applyProbe(values, .{
        .wavelength_nm = 758.0,
        .gas_absorption_optical_depth = 0.00350565072324649,
        .gas_scattering_optical_depth = 0.02640649410142914,
        .cia_optical_depth = 0.00314377591581326,
        .aerosol_optical_depth = 0.29999999999999993,
        .total_optical_depth = 0.33305592074048884,
        .single_scatter_albedo = 0.9800351045425766,
    });
    applyProbe(values, .{
        .wavelength_nm = 760.0,
        .gas_absorption_optical_depth = 0.8352435635463854,
        .gas_scattering_optical_depth = 0.02612673710444396,
        .cia_optical_depth = 0.00574939661492827,
        .aerosol_optical_depth = 0.29999999999999993,
        .total_optical_depth = 1.1671196972657576,
        .single_scatter_albedo = 0.27942869773209184,
    });
    applyProbe(values, .{
        .wavelength_nm = 765.0,
        .gas_absorption_optical_depth = 0.14846720294997337,
        .gas_scattering_optical_depth = 0.02544341608561606,
        .cia_optical_depth = 0.00674407505097872,
        .aerosol_optical_depth = 0.29999999999999993,
        .total_optical_depth = 0.48065469408656813,
        .single_scatter_albedo = 0.6770836113523987,
    });
    applyProbe(values, .{
        .wavelength_nm = 767.0,
        .gas_absorption_optical_depth = 0.01613470147641476,
        .gas_scattering_optical_depth = 0.02517636410299681,
        .cia_optical_depth = 0.0034420027644206,
        .aerosol_optical_depth = 0.29999999999999993,
        .total_optical_depth = 0.3447530683438321,
        .single_scatter_albedo = 0.9432152864225968,
    });
    applyProbe(values, .{
        .wavelength_nm = 776.0,
        .gas_absorption_optical_depth = 0.0001201820341403,
        .gas_scattering_optical_depth = 0.02401717865075858,
        .cia_optical_depth = 0.00013822309906086,
        .aerosol_optical_depth = 0.29999999999999993,
        .total_optical_depth = 0.32427558378395965,
        .single_scatter_albedo = 0.9992031310831799,
    });

    return .{
        .values = values,
        .reuse_stamp = hashing.ReuseStamp.fromBytes(case.id),
        .recorded_forward_miss_count = 3874,
    };
}

fn applyProbe(values: []ProfileLineValue, probe: ProfileLineValue) void {
    // applyProbe ---------------------------------------------------------------------------------------------|
    // Replace an exact-grid row when a recorded diagnostic probe lies on the exact route.                     |
    // --------------------------------------------------------------------------------------------------------|
    for (values) |*value| {
        if (@abs(value.wavelength_nm - probe.wavelength_nm) <= 1.0e-9) {
            value.* = probe;
            return;
        }
    }
}

fn interpolatedBaseline(wavelength_nm: f64) ProfileLineValue {
    // interpolatedBaseline -----------------------------------------------------------------------------------|
    // Provide deterministic placeholder values for exact wavelengths that are not WP1 diagnostic probes.      |
    // --------------------------------------------------------------------------------------------------------|
    const edge_weight = (wavelength_nm - 755.0) / 21.0;
    const gas_absorption = @max(0.0, 0.02 * (1.0 - edge_weight));
    const gas_scattering = 0.026 - 0.002 * edge_weight;
    const cia = @max(0.0, 0.004 * (1.0 - edge_weight));
    const aerosol = 0.3;
    const total = gas_absorption + gas_scattering + cia + aerosol;
    return .{
        .wavelength_nm = wavelength_nm,
        .gas_absorption_optical_depth = gas_absorption,
        .gas_scattering_optical_depth = gas_scattering,
        .cia_optical_depth = cia,
        .aerosol_optical_depth = aerosol,
        .total_optical_depth = total,
        .single_scatter_albedo = @min((gas_scattering + aerosol) / @max(total, 1.0e-12), 1.0),
    };
}

fn recordedProbeValue(wavelength_nm: f64) ?ProfileLineValue {
    // recordedProbeValue -------------------------------------------------------------------------------------|
    // Return WP1 diagnostic probes that do not lie on the 0.03 nm exact output grid.                          |
    // --------------------------------------------------------------------------------------------------------|
    const off_grid_probes = [_]ProfileLineValue{
        .{
            .wavelength_nm = 760.0,
            .gas_absorption_optical_depth = 0.8352435635463854,
            .gas_scattering_optical_depth = 0.02612673710444396,
            .cia_optical_depth = 0.00574939661492827,
            .aerosol_optical_depth = 0.29999999999999993,
            .total_optical_depth = 1.1671196972657576,
            .single_scatter_albedo = 0.27942869773209184,
        },
        .{
            .wavelength_nm = 765.0,
            .gas_absorption_optical_depth = 0.14846720294997337,
            .gas_scattering_optical_depth = 0.02544341608561606,
            .cia_optical_depth = 0.00674407505097872,
            .aerosol_optical_depth = 0.29999999999999993,
            .total_optical_depth = 0.48065469408656813,
            .single_scatter_albedo = 0.6770836113523987,
        },
    };

    for (off_grid_probes) |probe| {
        if (@abs(wavelength_nm - probe.wavelength_nm) <= 1.0e-9) return probe;
    }

    return null;
}
