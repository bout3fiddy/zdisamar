const internal = @import("internal");

test {
    const preparation = internal.forward_model.optical_properties;

    _ = preparation.state;
    _ = preparation.PreparationInputs;
    _ = preparation.prepare;
    _ = preparation.spectroscopy;
    _ = preparation.evaluation;
    _ = preparation.forward_layers;
    _ = preparation.source_interfaces;
    _ = preparation.rtm_quadrature;
    _ = preparation.pseudo_spherical;
    _ = preparation.shared_geometry;
}
