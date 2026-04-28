const internal = @import("internal");

test {
    const measurement = internal.kernels.transport.measurement;

    _ = measurement.types;
    _ = measurement.workspace;
    _ = measurement.cache;
    _ = measurement.forward_input;
    _ = measurement.spectral_eval;
    _ = measurement.product;
    _ = measurement.simulate;
}
