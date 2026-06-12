const std = @import("std");

const controls = @import("controls.zig");
const gauss_angles = @import("gauss_angles.zig");
const rows = @import("rows.zig");
const Perturbation = @import("../instrumentation/sensitivity.zig");
const Telemetry = @import("../instrumentation/telemetry.zig");
const Trace = @import("../instrumentation/trace.zig");

const math = std.math;

// reflectance.zig ------------------------------------------------------------------------------------------- |
// Converts LABOS order fields into Fourier reflectance terms and small solve-level reflectance helpers.       |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/radiative_transfer/labos/reflectance.zig` `calcReflectance` and             |
//   main:`src/forward_model/radiative_transfer/labos/execute.zig` Fourier weighting, Fourier tail stop,       |
//   weighted-term perturbation, and zero-Fourier surface-albedo weighting.                                    |
//                                                                                                             |
// reference names                                                                                             |
//   rho_m : reflectance coefficient for one Fourier term before azimuthal weighting                           |
//   c_m   : Fourier weight, 1 for m=0 and 2*cos(m*dphi) for m>0                                               |
//   UD_fc : accumulated upward/downward radiation field from scattering orders                                |
//                                                                                                             |
// math                                                                                                        |
//   reflectance += c_m * rho_m                                                                                |
//   tail_break = m >= fourier_floor_scalar and abs(rho_m) <= fourier_tail_reflectance_epsilon                 |
// ------------------------------------------------------------------------------------------------------------|

// FourierContribution --------------------------------------------------------------------------------------- |
// One Fourier term after azimuthal weighting and tail-stop classification.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] weight     : f64                                                                                   |
// [ 8..15] rho_m      : f64                                                                                   |
// [16..23] weighted   : f64                                                                                   |
// [24..24] tail_break : bool                                                                                  |
// [25..31] padding    : 7 B                                                                                   |
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// footprint: per instance = 32 B (0.031 KiB); stack row per Fourier term                                      |
pub const FourierContribution = struct {
    weight: f64,
    rho_m: f64,
    weighted: f64,
    tail_break: bool,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn topReflectanceCoefficient(
    ud: []const rows.UDField,
    top_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
) f64 {
    // topReflectanceCoefficient ----------------------------------------------------------------------------- |
    // Non-integrated LABOS reflectance for one Fourier term.                                                  |
    //                                                                                                         |
    // zdisamar matches old `CalcReflectance`: read upward U at the top level, solar column, viewing stream.   |
    // --------------------------------------------------------------------------------------------------------|
    const solar_column: usize = 1;
    return ud[top_level].U.col[solar_column].get(geometry.viewIndex());
}

pub fn fourierWeight(fourier_index: usize, relative_azimuth_rad: f64) f64 {
    // fourierWeight ----------------------------------------------------------------------------------------- |
    // Return c_m for the old LABOS Fourier reflectance sum.                                                   |
    // --------------------------------------------------------------------------------------------------------|
    if (fourier_index == 0) return 1.0;
    return 2.0 * math.cos(@as(f64, @floatFromInt(fourier_index)) * relative_azimuth_rad);
}

pub fn weightedFourierContribution(
    fourier_index: usize,
    relative_azimuth_rad: f64,
    rho_m: f64,
    thresholds: controls.PerformanceThresholds,
) FourierContribution {
    // weightedFourierContribution --------------------------------------------------------------------------- |
    // Apply Fourier azimuthal weight, perturbation hook, telemetry, and tail-stop decision.                   |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   Perturbation can replace the weighted term and the tail decision at the same old LABOS gates.         |
    // --------------------------------------------------------------------------------------------------------|
    const weight = fourierWeight(fourier_index, relative_azimuth_rad);
    const coord = Perturbation.Coord{ .fourier_index = @intCast(fourier_index) };

    // instrumentation: perturbation: reflectance term --------------------------------------------------------|
    // captures: c_m * rho_m before adding it to total reflectance                                             |
    // why: test whether late Fourier terms can be pruned by tolerance.                                        |
    const weighted = Perturbation.scalar(
        .fourier_weighted_reflectance,
        coord,
        weight * rho_m,
    );
    // end instrumentation: perturbation: reflectance term ----------------------------------------------------|

    const tail_break = fourierTailBreak(fourier_index, rho_m, thresholds, coord);

    // instrumentation: calculation telemetry: Fourier contribution -------------------------------------------|
    // captures: Fourier contribution size and tail-break decision                                             |
    // why: compare tolerance pruning against each retained term.                                              |
    Telemetry.fourierContribution(
        fourier_index,
        weight,
        rho_m,
        weighted,
        thresholds.fourier_tail_reflectance_epsilon,
        tail_break,
    );
    // end instrumentation: calculation telemetry: Fourier contribution ---------------------------------------|

    return .{
        .weight = weight,
        .rho_m = rho_m,
        .weighted = weighted,
        .tail_break = tail_break,
    };
}

pub fn fourierTailBreak(
    fourier_index: usize,
    rho_m: f64,
    thresholds: controls.PerformanceThresholds,
    coord: Perturbation.Coord,
) bool {
    // fourierTailBreak -------------------------------------------------------------------------------------- |
    // Evaluate the old Fourier tail-stop gate.                                                                |
    //                                                                                                         |
    // tradeoff: Fourier tail stop                                                                             |
    // Stop the Fourier loop when the current unweighted term is below the configured epsilon.                 |
    // The stop is only allowed after fourier_floor_scalar.                                                    |
    // --------------------------------------------------------------------------------------------------------|

    // instrumentation: telemetry and perturbation: tail break ------------------------------------------------|
    // captures: Fourier tail-stop decision and term magnitude                                                 |
    // why: compare current convergence threshold against forced early stops.                                  |
    const tail_break_base =
        fourier_index >= thresholds.fourier_floor_scalar and
        @abs(rho_m) <= thresholds.fourier_tail_reflectance_epsilon;
    const tail_break = Perturbation.decision(.fourier_tail_break, coord, tail_break_base);
    // end instrumentation: telemetry and perturbation: tail break --------------------------------------------|

    if (tail_break) {

        // instrumentation: trace counter: tail break ---------------------------------------------------------|
        // captures: Fourier tail breaks                                                                       |
        // why: validate the tail-pruning threshold against observed exits.                                    |
        Trace.plotU("fourier_tail_breaks", 1);
        // end instrumentation: trace counter: tail break -----------------------------------------------------|

    }

    return tail_break;
}

pub fn surfaceAlbedoWeighting(
    ud: []const rows.UDField,
    geometry: *const gauss_angles.GaussGeometry,
) f64 {
    // surfaceAlbedoWeighting -------------------------------------------------------------------------------- |
    // Surface-albedo Jacobian for the zero-Fourier surface term.                                              |
    //                                                                                                         |
    // math                                                                                                    |
    //   d reflectance / d albedo = (E_view + integral D_view dmu)                                             |
    //                              * (E_sun  + integral D_sun  dmu)                                           |
    // --------------------------------------------------------------------------------------------------------|
    const surface_level: usize = 0;
    const view_column: usize = 0;
    const solar_column: usize = 1;
    var diffuse_view: f64 = 0.0;
    var diffuse_solar: f64 = 0.0;

    for (0..geometry.n_gauss) |gauss_index| {
        diffuse_view += ud[surface_level].D.col[view_column].get(gauss_index) * geometry.w[gauss_index];
        diffuse_solar += ud[surface_level].D.col[solar_column].get(gauss_index) * geometry.w[gauss_index];
    }

    const view_direct = ud[surface_level].E.get(geometry.viewIndex());
    const solar_direct = ud[surface_level].E.get(geometry.solarIndex());

    return (view_direct + diffuse_view) * (solar_direct + diffuse_solar);
}

pub fn clampPublicReflectance(reflectance: f64) f64 {
    // clampPublicReflectance -------------------------------------------------------------------------------- |
    // Clamp raw LABOS reflectance to the public forward-model output range.                                   |
    // --------------------------------------------------------------------------------------------------------|
    return math.clamp(reflectance, 0.0, 2.0);
}
