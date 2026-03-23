const Scene = @import("../../../model/Scene.zig").Scene;
const OpticsPreparation = @import("../../optics/preparation.zig");
const common = @import("../common.zig");
const Workspace = @import("workspace.zig");

pub fn configuredForwardInput(
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
) common.ForwardInput {
    var input = OpticsPreparation.transport.toForwardInputAtWavelengthWithLayers(
        prepared,
        scene,
        wavelength_nm,
        layer_inputs,
    );
    OpticsPreparation.transport.fillSourceInterfacesAtWavelengthWithLayers(
        prepared,
        wavelength_nm,
        input.layers,
        source_interfaces[0 .. input.layers.len + 1],
    );
    input.source_interfaces = source_interfaces[0 .. input.layers.len + 1];
    if (route.rtm_controls.integrate_source_function) {
        if (OpticsPreparation.transport.fillRtmQuadratureAtWavelengthWithLayers(
            prepared,
            wavelength_nm,
            input.layers,
            rtm_quadrature_levels[0 .. input.layers.len + 1],
        )) {
            input.rtm_quadrature = .{
                .levels = rtm_quadrature_levels[0 .. input.layers.len + 1],
            };
        }
    }
    if (route.rtm_controls.use_spherical_correction) {
        if (OpticsPreparation.transport.fillPseudoSphericalGridAtWavelength(
            prepared,
            scene,
            wavelength_nm,
            input.layers.len,
            pseudo_spherical_layers,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
        )) {
            input.pseudo_spherical_grid = .{
                .samples = pseudo_spherical_samples[0..Workspace.resolvedPseudoSphericalSampleCount(scene, route, prepared)],
                .level_sample_starts = pseudo_spherical_level_starts[0 .. input.layers.len + 1],
                .level_altitudes_km = pseudo_spherical_level_altitudes[0 .. input.layers.len + 1],
            };
        }
    }
    input.rtm_controls = route.rtm_controls;
    return input;
}
