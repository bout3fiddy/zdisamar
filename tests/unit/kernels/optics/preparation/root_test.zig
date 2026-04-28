const internal = @import("internal");

test {
    const preparation = internal.kernels.optics.preparation;

    _ = preparation.state;
    _ = preparation.builder;
    _ = preparation.spectroscopy;
    _ = preparation.evaluation;
    _ = preparation.transport;
}
