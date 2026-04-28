const std = @import("std");
const internal = @import("internal");

const Transport = internal.forward_model.implementations.Transport;
const common = internal.forward_model.radiative_transfer;

test "transport provider exposes route fidelity and provenance helpers" {
    const provider = Transport.resolve("builtin.dispatcher") orelse unreachable;
    const route = try provider.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    try std.testing.expectEqual(common.ImplementationClass.baseline, provider.classificationForRoute(route));
    try std.testing.expectEqualStrings("baseline_labos", provider.provenanceLabelForRoute(route));
    try std.testing.expectEqual(common.DerivativeSemantics.none, provider.derivativeSemanticsForRoute(route));
}
