const errors = @import("../core/errors.zig");

pub const BindingKind = enum {
    none,
    atmosphere,
    bundle_default,
    asset,
    ingest,
    stage_product,
    external_observation,
};

pub const Binding = struct {
    kind: BindingKind = .none,
    name: []const u8 = "",

    pub fn enabled(self: Binding) bool {
        return self.kind != .none;
    }

    pub fn validate(self: Binding) errors.Error!void {
        switch (self.kind) {
            .none => {
                if (self.name.len != 0) return errors.Error.InvalidRequest;
            },
            .atmosphere, .bundle_default => {
                if (self.name.len != 0) return errors.Error.InvalidRequest;
            },
            .asset, .ingest, .stage_product, .external_observation => {
                if (self.name.len == 0) return errors.Error.InvalidRequest;
            },
        }
    }
};

test "binding validates kind-specific naming rules" {
    try (Binding{}).validate();
    try (Binding{ .kind = .atmosphere }).validate();
    try (Binding{ .kind = .bundle_default }).validate();
    try (Binding{ .kind = .asset, .name = "solar_spectrum" }).validate();

    try @import("std").testing.expectError(
        errors.Error.InvalidRequest,
        (Binding{ .kind = .ingest }).validate(),
    );
    try @import("std").testing.expectError(
        errors.Error.InvalidRequest,
        (Binding{ .kind = .none, .name = "unexpected" }).validate(),
    );
}
