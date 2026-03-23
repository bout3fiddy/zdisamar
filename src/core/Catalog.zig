//! Purpose:
//!   Own the bootstrap-time catalog of bundled model families and exporter identifiers
//!   that the engine can advertise before any request-specific preparation occurs.
//!
//! Physics:
//!   This file does not implement a physical transform; it names the supported model
//!   families that downstream preparation routes to atmospheric and radiative-transfer
//!   kernels.
//!
//! Vendor:
//!   `engine bootstrap catalog stage`
//!
//! Design:
//!   The Zig scaffold keeps catalog data as an explicit, allocator-owned value instead
//!   of relying on process-global registration tables or implicit startup hooks.
//!
//! Invariants:
//!   Bootstrapping is idempotent, builtins append in a deterministic order, and partial
//!   failures roll the catalog back to its pre-bootstrap lengths.
//!
//! Validation:
//!   Covered indirectly by preparation tests that require a bootstrapped catalog before
//!   plan compilation and by compile-time uses of the builtin model family names.
const std = @import("std");

/// Purpose:
///   Describe a model family exposed through the public catalog surface.
///
/// Outputs:
///   Carries the stable family name used in templates plus a user-facing description.
pub const ModelFamily = struct {
    name: []const u8,
    description: []const u8,
};

/// Purpose:
///   Store the bootstrapped builtin model families and exporter identifiers.
pub const Catalog = struct {
    model_families: std.ArrayListUnmanaged(ModelFamily) = .{},
    exporters: std.ArrayListUnmanaged([]const u8) = .{},
    bootstrapped: bool = false,

    /// Purpose:
    ///   Populate the catalog with the bundled engine families and exporters.
    ///
    /// Outputs:
    ///   Appends builtin entries in deterministic order and marks the catalog as
    ///   bootstrapped once the full set is present.
    ///
    /// Assumptions:
    ///   Callers reuse one catalog instance and do not require duplicate builtin rows.
    pub fn bootstrapBuiltin(self: *Catalog, allocator: std.mem.Allocator) !void {
        if (self.bootstrapped) return;

        const start_model_family_count = self.model_families.items.len;
        const start_exporter_count = self.exporters.items.len;
        errdefer {
            self.model_families.items.len = start_model_family_count;
            self.exporters.items.len = start_exporter_count;
            self.bootstrapped = false;
        }

        // DECISION:
        //   The scaffold publishes one canonical DISAMAR-derived family name instead of
        //   mirroring the vendor's broader process-wide configuration matrix.
        try self.model_families.append(allocator, .{
            .name = "disamar_standard",
            .description = "Bundled DISAMAR 1D family on the reusable typed-provider RT scaffold.",
        });
        try self.exporters.append(allocator, "netcdf_cf");
        try self.exporters.append(allocator, "zarr");

        self.bootstrapped = true;
    }

    /// Purpose:
    ///   Release any allocator-owned catalog storage and reset the instance.
    pub fn deinit(self: *Catalog, allocator: std.mem.Allocator) void {
        self.model_families.deinit(allocator);
        self.exporters.deinit(allocator);
        self.* = .{};
    }

    /// Purpose:
    ///   Report whether the catalog contains the named model family.
    pub fn supportsModelFamily(self: *const Catalog, name: []const u8) bool {
        for (self.model_families.items) |family| {
            if (std.mem.eql(u8, family.name, name)) {
                return true;
            }
        }
        return false;
    }
};
