const internal = @import("internal");

test {
    const adding = internal.kernels.transport.adding;

    _ = adding.execution;
    _ = adding.composition;
    _ = adding.fields;
}
