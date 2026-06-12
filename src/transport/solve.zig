const std = @import("std");

const controls = @import("controls.zig");
const curved_sun_path = @import("../optics/curved_sun_path.zig");
const jacobian_states = @import("jacobian_states.zig");
const layer_depths = @import("../optics/layer_depths.zig");
const source_levels = @import("../optics/source_levels.zig");

const math = std.math;

const direct_direction_cosine_floor: f64 = 0.05;

pub const Error = controls.PrepareError || error{
    InvalidShape,
};

// solve.zig ------------------------------------------------------------------------------------------------- |
// Transport-solve dispatch for explicit WP3 optical rows.                                                     |
//                                                                                                             |
// provenance                                                                                                  |
//   The direct-surface route ports main:`src/forward_model/radiative_transfer/labos/execute.zig`              |
//   `directSurfaceOnly` and the no-scattering dispatch in `executeWithWorkspace`. The Fourier/LABOS route     |
//   remains a typed unsupported branch until this file wires the already-ported attenuation, layer RT,        |
//   scattering-order, and reflectance helpers together.                                                       |
//                                                                                                             |
// boundary                                                                                                    |
//   Inputs are explicit rows and scalars: angles, surface albedo, layer optics, source levels, curved-path    |
//   samples, and prepared transport controls. This file stores no scene, request, product storage, or cache.  |
//                                                                                                             |
// direct route                                                                                                |
//   The old scalar direct path used one total optical depth. The new explicit boundary has layer rows, so the |
//   direct route sums layer total optical depths before applying the same scalar formula.                     |
//                                                                                                             |
// allocation                                                                                                  |
//   This file allocates nothing. The work-array argument exists for the full LABOS route and is unused by     |
//   the direct-surface route.                                                                                 |
// ------------------------------------------------------------------------------------------------------------|

// ViewAngles ------------------------------------------------------------------------------------------------ |
// Direction cosines and relative azimuth for one transport solve.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] solar_mu             : f64                                                                         |
// [ 8..15] view_mu              : f64                                                                         |
// [16..23] relative_azimuth_rad : f64                                                                         |
//                                                                                                             |
// footprint: per instance = 24 B (0.023 KiB); one stack value per high-resolution wavelength                  |
pub const ViewAngles = struct {
    solar_mu: f64,
    view_mu: f64,
    relative_azimuth_rad: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

// ReflectanceResult ----------------------------------------------------------------------------------------  |
// One top-of-atmosphere reflectance result and fixed state-order Jacobian vector.                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] reflectance : f64                                                                                  |
// [ 8..31] jacobian    : [3]f64                                                                               |
//                                                                                                             |
// footprint: per instance = 32 B (0.031 KiB); returned by value                                               |
pub const ReflectanceResult = struct {
    reflectance: f64,
    jacobian: jacobian_states.Vector = jacobian_states.zero(),
};
// ------------------------------------------------------------------------------------------------------------|

// TransportWorkArrays --------------------------------------------------------------------------------------  |
// Borrowed transport scratch passed to solveReflectance.                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields yet                                                                                      |
//                                                                                                             |
// direct-route note                                                                                           |
//   The no-scattering route does not need LABOS scratch. Later Fourier orchestration fills this struct with   |
//   borrowed attenuation, RT, order, phase-row, and basis arrays from TransportWorkerMemory.                  |
pub const TransportWorkArrays = struct {};
// ------------------------------------------------------------------------------------------------------------|

pub fn solveReflectance(
    angles: ViewAngles,
    surface_albedo: f64,
    layers: []const layer_depths.LayerOptics,
    level_sources: []const source_levels.SourceLevel,
    curved_samples: []const curved_sun_path.CurvedSunPathSample,
    prepared_config: controls.SolveConfig,
    work: *TransportWorkArrays,
) Error!ReflectanceResult {
    // solveReflectance -------------------------------------------------------------------------------------  |
    // Dispatch one explicit transport solve. The implemented direct route follows old LABOS scalar behavior;  |
    // enabled scattering still returns a typed error until the full Fourier loop lands in this file.          |
    //                                                                                                         |
    // direct math                                                                                             |
    //   direct path = exp(-tau / max(mu0, 0.05)) * exp(-tau / max(muv, 0.05))                                 |
    //   reflectance = surface_albedo * direct path                                                            |
    //                                                                                                         |
    // unsupported route                                                                                       |
    //   Scattering-enabled controls are rejected here rather than silently dropping layer RT, source rows,    |
    //   curved-path samples, or Jacobian propagation.                                                         |
    // --------------------------------------------------------------------------------------------------------|
    _ = level_sources;
    _ = curved_samples;
    _ = work;

    const config = try controls.prepareSolveConfig(prepared_config);
    if (config.controls.scattering != .none) return error.UnsupportedRadiativeTransferControls;
    if (config.controls.use_spherical_correction) return error.UnsupportedRadiativeTransferControls;

    return directSurfaceOnly(
        angles,
        surface_albedo,
        totalLayerOpticalDepth(layers),
        config.derivative_mode,
        config.derivative_state_mask,
    );
}

pub fn directSurfaceOnly(
    angles: ViewAngles,
    surface_albedo: f64,
    total_optical_depth: f64,
    derivative_mode: controls.DerivativeMode,
    derivative_state_mask: jacobian_states.StateMask,
) ReflectanceResult {
    // directSurfaceOnly ------------------------------------------------------------------------------------  |
    // Scalar direct-surface path from old LABOS execute.zig.                                                  |
    //                                                                                                         |
    // math                                                                                                    |
    //   direct path = exp(-tau / mu0) * exp(-tau / muv)                                                       |
    //   reflectance = surface_albedo * direct path                                                            |
    //                                                                                                         |
    // numerical guard                                                                                         |
    //   `0.05` is the old LABOS direct-route cosine floor. It prevents grazing directions from producing      |
    //   unstable direct-beam exponentials.                                                                    |
    // --------------------------------------------------------------------------------------------------------|
    const mu0 = @max(angles.solar_mu, direct_direction_cosine_floor);
    const muv = @max(angles.view_mu, direct_direction_cosine_floor);
    const direct = math.exp(-total_optical_depth / mu0) * math.exp(-total_optical_depth / muv);
    const raw_reflectance = surface_albedo * direct;
    const wants_surface_albedo =
        derivative_mode != .none and
        jacobian_states.includes(derivative_state_mask, .surface_albedo);

    var jacobian = jacobian_states.zero();
    if (wants_surface_albedo and raw_reflectance >= 0.0 and raw_reflectance < 2.0) {
        jacobian_states.set(&jacobian, .surface_albedo, direct);
    }

    return .{
        .reflectance = math.clamp(raw_reflectance, 0.0, 2.0),
        .jacobian = jacobian,
    };
}

fn totalLayerOpticalDepth(layers: []const layer_depths.LayerOptics) f64 {
    // totalLayerOpticalDepth -------------------------------------------------------------------------------  |
    // Reduce explicit layer rows into the scalar tau consumed by the old direct-surface formula.              |
    // --------------------------------------------------------------------------------------------------------|
    var total: f64 = 0.0;
    for (layers) |layer| total += layer.total_optical_depth;
    return total;
}

comptime {
    std.debug.assert(@sizeOf(ViewAngles) == 24);
    std.debug.assert(@sizeOf(ReflectanceResult) == 32);
    std.debug.assert(@sizeOf(TransportWorkArrays) == 0);
}
