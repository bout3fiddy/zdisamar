const std = @import("std");
const internal = @import("internal");

const binding = internal.binding;
const Binding = binding.Binding;
const IngestRef = binding.IngestRef;
const errors = internal.core.errors;

test "binding validates kind-specific naming rules" {
    try (@as(Binding, .none)).validate();
    try (@as(Binding, .atmosphere)).validate();
    try (@as(Binding, .bundle_default)).validate();
    try (Binding{ .asset = .{ .name = "solar_spectrum" } }).validate();

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (Binding{ .ingest = IngestRef.fromFullName("") }).validate(),
    );
}
