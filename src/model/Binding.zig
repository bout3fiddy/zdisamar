//! Purpose:
//!   Define the typed binding vocabulary used to connect scene inputs, runtime assets,
//!   ingest outputs, and stage products across the engine.
//!
//! Physics:
//!   Bindings do not carry physical data themselves; they identify where physically
//!   meaningful inputs such as spectra, climatologies, and observations originate.
//!
//! Vendor:
//!   `asset/source binding resolution stage`
//!
//! Design:
//!   The Zig engine replaces stringly typed source resolution with a closed tagged union
//!   so preparation can validate source intent before any loader or runtime lookup.
//!
//! Invariants:
//!   Named references must be non-empty, ingest references must contain both ingest and
//!   output names, and owned string storage is released according to the active tag.
//!
//! Validation:
//!   Unit tests below exercise kind-specific validation and the parser for ingest names.
const std = @import("std");
const errors = @import("../core/errors.zig");
const Allocator = std.mem.Allocator;

/// Purpose:
///   Enumerate the supported source-binding categories.
pub const BindingKind = enum {
    none,
    atmosphere,
    bundle_default,
    asset,
    ingest,
    stage_product,
    external_observation,
};

/// Purpose:
///   Hold a validated named reference into assets or stage products.
pub const NamedRef = struct {
    name: []const u8,

    /// Purpose:
    ///   Ensure the reference contains a non-empty name.
    pub fn validate(self: NamedRef) errors.Error!void {
        if (self.name.len == 0) return errors.Error.InvalidRequest;
    }

    /// Purpose:
    ///   Duplicate the reference name into allocator-owned storage.
    pub fn clone(self: NamedRef, allocator: Allocator) !NamedRef {
        return .{ .name = try allocator.dupe(u8, self.name) };
    }

    /// Purpose:
    ///   Release allocator-owned name storage.
    pub fn deinitOwned(self: NamedRef, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

/// Purpose:
///   Hold an ingest reference split into ingest and output identifiers.
pub const IngestRef = struct {
    full_name: []const u8,
    ingest_name: []const u8,
    output_name: []const u8,

    /// Purpose:
    ///   Parse `ingest.output` into the split ingest reference form.
    pub fn fromFullName(full_name: []const u8) IngestRef {
        const dot_index = std.mem.indexOfScalar(u8, full_name, '.');
        return .{
            .full_name = full_name,
            .ingest_name = if (dot_index) |index| full_name[0..index] else "",
            .output_name = if (dot_index) |index| full_name[index + 1 ..] else "",
        };
    }

    /// Purpose:
    ///   Ensure both the ingest name and output name are present.
    pub fn validate(self: IngestRef) errors.Error!void {
        if (self.full_name.len == 0 or self.ingest_name.len == 0 or self.output_name.len == 0) {
            return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Duplicate the full ingest reference into allocator-owned storage.
    pub fn clone(self: IngestRef, allocator: Allocator) !IngestRef {
        return fromFullName(try allocator.dupe(u8, self.full_name));
    }

    /// Purpose:
    ///   Release allocator-owned storage for the full ingest reference.
    pub fn deinitOwned(self: IngestRef, allocator: Allocator) void {
        allocator.free(self.full_name);
    }
};

/// Purpose:
///   Identify where a model or measurement input should be sourced from.
pub const Binding = union(BindingKind) {
    none,
    atmosphere,
    bundle_default,
    asset: NamedRef,
    ingest: IngestRef,
    stage_product: NamedRef,
    external_observation: NamedRef,

    /// Purpose:
    ///   Report whether the binding requests any non-default source.
    pub fn enabled(self: Binding) bool {
        return self.kind() != .none;
    }

    /// Purpose:
    ///   Return the active source category for the binding.
    pub fn kind(self: Binding) BindingKind {
        return std.meta.activeTag(self);
    }

    /// Purpose:
    ///   Return the serialized name associated with the active binding.
    pub fn name(self: Binding) []const u8 {
        return switch (self) {
            .asset => |value| value.name,
            .ingest => |value| value.full_name,
            .stage_product => |value| value.name,
            .external_observation => |value| value.name,
            .none, .atmosphere, .bundle_default => "",
        };
    }

    /// Purpose:
    ///   Return the parsed ingest reference when the binding targets ingest output.
    pub fn ingestReference(self: Binding) ?IngestRef {
        return switch (self) {
            .ingest => |value| value,
            else => null,
        };
    }

    /// Purpose:
    ///   Ensure the active binding payload satisfies its kind-specific constraints.
    pub fn validate(self: Binding) errors.Error!void {
        switch (self) {
            .none, .atmosphere, .bundle_default => {},
            .asset => |value| try value.validate(),
            .ingest => |value| try value.validate(),
            .stage_product => |value| try value.validate(),
            .external_observation => |value| try value.validate(),
        }
    }

    /// Purpose:
    ///   Duplicate the binding payload into allocator-owned storage when needed.
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

    /// Purpose:
    ///   Release any allocator-owned payload associated with the active binding.
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
