const internal = @import("internal");

test {
    const adding = internal.forward_model.radiative_transfer.adding;

    _ = adding.execution;
    _ = adding.composition;
    _ = adding.fields;
}
