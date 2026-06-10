const std = @import("std");
const errors = @import("../common/errors.zig");
const Allocator = std.mem.Allocator;

// Binding.zig ------------------------------------------------------------------------------------------------|
// Typed unresolved-reference rows for public input fields. A Binding says where a requested profile,          |
// spectroscopy table, measurement vector, or instrument support should come from; it does not carry the       |
// resolved payload and it never opens files.                                                                  |
//                                                                                                             |
// route                                                                                                       |
//   Atmosphere, Absorber, Measurement, and ObservationModel store Binding values inside the Scene input row.  |
//   Scene.validate calls Binding.validate through those parent rows before any loader or forward-model code   |
//   runs. reference-data workflows and bundled-asset selection later interpret the active kind and attach     |
//   concrete resolved payloads to the owning input rows or prepared optical state.                            |
//                                                                                                             |
// binding kinds                                                                                               |
//   none          : no external source requested                                                              |
//   atmosphere    : use the current Scene atmosphere/profile as the source                                    |
//   bundle_default: ask bundled reference-data selection to choose the default asset                          |
//   asset         : name a concrete loaded asset                                                              |
//   ingest        : name an ingest output as "ingest.output"                                                  |
//   stage_product : name an earlier stage product                                                             |
//                                                                                                             |
// validation and lookup boundary                                                                              |
//   validate checks only the syntactic payload carried by the active tag: non-empty names for NamedRef and    |
//   a split ingest/output pair for IngestRef. It does not prove the asset exists. Loader and workflow code    |
//   must still consume the binding, reject it with a typed error, or document it as inert with coverage.      |
//                                                                                                             |
// cache-key boundary                                                                                          |
//   Scene.lutCompatibilityKey hashes binding kind plus binding.name() for spectroscopy bindings.              |
//   Marker kinds intentionally return an empty name; `.none`, `.atmosphere`, and `.bundle_default` stay       |
//   distinct through the tag even though their name bytes are empty.                                          |
//                                                                                                             |
// memory and ownership                                                                                        |
//   NamedRef.name points at out-of-line bytes. IngestRef.ingest_name and output_name borrow from full_name.   |
//   deinit frees only full_name for ingest payloads. clone duplicates the owning string and rebuilds the      |
//   borrowed slices from the clone.                                                                           |
// ------------------------------------------------------------------------------------------------------------|

pub const BindingKind = enum {
    none,
    atmosphere,
    bundle_default,
    asset,
    ingest,
    stage_product,
};

// NamedRef ---------------------------------------------------------------------------------------------------|
// One named external reference.                                                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] name : []const u8                                                                                   |
//                                                                                                             |
// referenced storage                                                                                          |
//   name points at out-of-line string bytes. clone creates the owned copy released by deinitOwned.            |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes referenced name bytes                       |
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
// ------------------------------------------------------------------------------------------------------------|

// IngestRef --------------------------------------------------------------------------------------------------|
// Parsed ingest.output reference.                                                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] full_name   : []const u8                                                                           |
// [16..31] ingest_name : []const u8                                                                           |
// [32..47] output_name : []const u8                                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   ingest_name and output_name are slices into full_name. deinitOwned frees only full_name.                  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 48 B (0.047 KiB); total also includes referenced name bytes                       |
pub const IngestRef = struct {
    full_name: []const u8,
    ingest_name: []const u8,
    output_name: []const u8,

    pub fn fromFullName(full_name: []const u8) IngestRef {
        // IngestRef.fromFullName -----------------------------------------------------------------------------|
        // Split one "ingest.output" name into borrowed slices. Missing "." keeps full_name but returns empty  |
        // ingest/output slices so validate can reject the malformed reference without reparsing.              |
        // ----------------------------------------------------------------------------------------------------|

        const dot_index = std.mem.indexOfScalar(u8, full_name, '.');
        if (dot_index) |index| {
            return .{
                .full_name = full_name,
                .ingest_name = full_name[0..index],
                .output_name = full_name[index + 1 ..],
            };
        }

        return .{
            .full_name = full_name,
            .ingest_name = "",
            .output_name = "",
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
// ------------------------------------------------------------------------------------------------------------|

// Binding ----------------------------------------------------------------------------------------------------|
// Tagged reference union used by public input models.                                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// active payload storage : up to IngestRef, 48 B                                                              |
// active tag/padding     : remaining storage for BindingKind tag and alignment                                |
//                                                                                                             |
// referenced storage                                                                                          |
//   asset and stage_product carry NamedRef names. ingest carries one IngestRef full_name allocation.          |
//                                                                                                             |
// footprint: per instance = 56 B (0.055 KiB); total also includes active referenced name bytes                |
pub const Binding = union(BindingKind) {
    none,
    atmosphere,
    bundle_default,
    asset: NamedRef,
    ingest: IngestRef,
    stage_product: NamedRef,

    pub fn enabled(self: Binding) bool {
        return self.kind() != .none;
    }

    pub fn kind(self: Binding) BindingKind {
        return std.meta.activeTag(self);
    }

    pub fn name(self: Binding) []const u8 {
        // Binding.name ---------------------------------------------------------------------------------------|
        // Return the cache-key name bytes for payload-bearing bindings. Marker bindings carry their meaning   |
        // in the tag, so they intentionally return an empty name.                                             |
        // ----------------------------------------------------------------------------------------------------|

        return switch (self) {
            .asset => |value| value.name,
            .ingest => |value| value.full_name,
            .stage_product => |value| value.name,
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
        // Binding.validate -----------------------------------------------------------------------------------|
        // Check the active tag's local naming shape. This does not resolve the binding or check loader state. |
        // ----------------------------------------------------------------------------------------------------|

        switch (self) {
            .none, .atmosphere, .bundle_default => {},
            .asset => |value| try value.validate(),
            .ingest => |value| try value.validate(),
            .stage_product => |value| try value.validate(),
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
        };
    }

    pub fn deinitOwned(self: *Binding, allocator: Allocator) void {
        switch (self.*) {
            .asset => |value| value.deinitOwned(allocator),
            .ingest => |value| value.deinitOwned(allocator),
            .stage_product => |value| value.deinitOwned(allocator),
            .none, .atmosphere, .bundle_default => {},
        }
        self.* = .none;
    }
};
// ------------------------------------------------------------------------------------------------------------|
