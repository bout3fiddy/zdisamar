const internal = @import("internal");

test {
    const preparation = internal.forward_model.optical_properties;

    _ = preparation.state;
    _ = preparation.builder;
    _ = preparation.spectroscopy;
    _ = preparation.evaluation;
    _ = preparation.transport;
}
