const std = @import("std");
const errors = @import("../core/errors.zig");
const Allocator = std.mem.Allocator;

pub const BindingKind = enum {
    none,
    atmosphere,
    bundle_default,
    asset,
    ingest,
    stage_product,
    external_observation,
};

pub const NamedRef = struct {
    name: []const u8,

    pub fn validate(self: NamedRef) errors.Error!void {
        if (self.name.len == 0) return errors.Error.InvalidRequest;
    }

    pub fn clone(self: NamedRef, allocator: Allocator) !NamedRef {
        return .{ .name = try allocator.dupe(u8, self.name) };
    }

    pub fn deinitOwned(self: NamedRef, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

pub const IngestRef = struct {
    full_name: []const u8,
    ingest_name: []const u8,
    output_name: []const u8,

    pub fn fromFullName(full_name: []const u8) IngestRef {
        const dot_index = std.mem.indexOfScalar(u8, full_name, '.');
        return .{
            .full_name = full_name,
            .ingest_name = if (dot_index) |index| full_name[0..index] else "",
            .output_name = if (dot_index) |index| full_name[index + 1 ..] else "",
        };
    }

    pub fn validate(self: IngestRef) errors.Error!void {
        if (self.full_name.len == 0 or self.ingest_name.len == 0 or self.output_name.len == 0) {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn clone(self: IngestRef, allocator: Allocator) !IngestRef {
        return fromFullName(try allocator.dupe(u8, self.full_name));
    }

    pub fn deinitOwned(self: IngestRef, allocator: Allocator) void {
        allocator.free(self.full_name);
    }
};

pub const Binding = union(BindingKind) {
    none,
    atmosphere,
    bundle_default,
    asset: NamedRef,
    ingest: IngestRef,
    stage_product: NamedRef,
    external_observation: NamedRef,

    pub fn enabled(self: Binding) bool {
        return self.kind() != .none;
    }

    pub fn kind(self: Binding) BindingKind {
        return std.meta.activeTag(self);
    }

    pub fn name(self: Binding) []const u8 {
        return switch (self) {
            .asset => |value| value.name,
            .ingest => |value| value.full_name,
            .stage_product => |value| value.name,
            .external_observation => |value| value.name,
            .none, .atmosphere, .bundle_default => "",
        };
    }

    pub fn ingestReference(self: Binding) ?IngestRef {
        return switch (self) {
            .ingest => |value| value,
            else => null,
        };
    }

    pub fn validate(self: Binding) errors.Error!void {
        switch (self) {
            .none, .atmosphere, .bundle_default => {},
            .asset => |value| try value.validate(),
            .ingest => |value| try value.validate(),
            .stage_product => |value| try value.validate(),
            .external_observation => |value| try value.validate(),
        }
    }

    pub fn clone(self: Binding, allocator: Allocator) !Binding {
        return switch (self) {
            .none => .none,
            .atmosphere => .atmosphere,
            .bundle_default => .bundle_default,
            .asset => |value| .{ .asset = try value.clone(allocator) },
            .ingest => |value| .{ .ingest = try value.clone(allocator) },
            .stage_product => |value| .{ .stage_product = try value.clone(allocator) },
            .external_observation => |value| .{ .external_observation = try value.clone(allocator) },
        };
    }

    pub fn deinitOwned(self: *Binding, allocator: Allocator) void {
        switch (self.*) {
            .asset => |value| value.deinitOwned(allocator),
            .ingest => |value| value.deinitOwned(allocator),
            .stage_product => |value| value.deinitOwned(allocator),
            .external_observation => |value| value.deinitOwned(allocator),
            .none, .atmosphere, .bundle_default => {},
        }
        self.* = .none;
    }
};

test "binding validates kind-specific naming rules" {
    try (@as(Binding, .none)).validate();
    try (@as(Binding, .atmosphere)).validate();
    try (@as(Binding, .bundle_default)).validate();
    try (Binding{ .asset = .{ .name = "solar_spectrum" } }).validate();

    try @import("std").testing.expectError(
        errors.Error.InvalidRequest,
        (Binding{ .ingest = IngestRef.fromFullName("") }).validate(),
    );
}
