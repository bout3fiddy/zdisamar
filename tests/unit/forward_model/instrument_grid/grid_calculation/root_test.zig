const internal = @import("internal");

test {
    const measurement = internal.forward_model.instrument_grid;

    _ = measurement.types;
    _ = measurement.storage;
    _ = measurement.cache;
    _ = measurement.forward_input;
    _ = measurement.spectral_eval;
    _ = measurement.product;
    _ = measurement.simulate;
}
