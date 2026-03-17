const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");
const Binding = @import("Binding.zig").Binding;
const ReferenceData = @import("ReferenceData.zig");

pub const SpectroscopyMode = enum {
    none,
    line_by_line,
    cia,
    cross_sections,
};

pub const Spectroscopy = struct {
    mode: SpectroscopyMode = .none,
    provider: []const u8 = "",
    line_list: Binding = .{},
    line_mixing: Binding = .{},
    strong_lines: Binding = .{},
    cia_table: Binding = .{},
    operational_lut: Binding = .{},
    resolved_line_list: ?ReferenceData.SpectroscopyLineList = null,
    resolved_cia_table: ?ReferenceData.CollisionInducedAbsorptionTable = null,

    pub fn validate(self: Spectroscopy) errors.Error!void {
        try self.line_list.validate();
        try self.line_mixing.validate();
        try self.strong_lines.validate();
        try self.cia_table.validate();
        try self.operational_lut.validate();

        if (self.mode == .none and
            (self.provider.len != 0 or
                self.line_list.enabled() or
                self.line_mixing.enabled() or
                self.strong_lines.enabled() or
                self.cia_table.enabled() or
                self.operational_lut.enabled() or
                self.resolved_line_list != null or
                self.resolved_cia_table != null))
        {
            return errors.Error.InvalidRequest;
        }
        if (self.resolved_line_list != null and self.mode != .line_by_line) return errors.Error.InvalidRequest;
        if (self.resolved_cia_table != null and self.mode != .cia) return errors.Error.InvalidRequest;
    }

    pub fn clone(self: Spectroscopy, allocator: Allocator) !Spectroscopy {
        const provider = if (self.provider.len != 0) try allocator.dupe(u8, self.provider) else "";
        errdefer if (provider.len != 0) allocator.free(provider);

        const line_list = try cloneBinding(allocator, self.line_list);
        errdefer freeBindingName(allocator, line_list);
        const line_mixing = try cloneBinding(allocator, self.line_mixing);
        errdefer freeBindingName(allocator, line_mixing);
        const strong_lines = try cloneBinding(allocator, self.strong_lines);
        errdefer freeBindingName(allocator, strong_lines);
        const cia_table = try cloneBinding(allocator, self.cia_table);
        errdefer freeBindingName(allocator, cia_table);
        const operational_lut = try cloneBinding(allocator, self.operational_lut);
        errdefer freeBindingName(allocator, operational_lut);

        const resolved_line_list = if (self.resolved_line_list) |line_list_data|
            try line_list_data.clone(allocator)
        else
            null;
        errdefer if (resolved_line_list) |*line_list_data| {
            var owned = line_list_data.*;
            owned.deinit(allocator);
        };

        const resolved_cia_table = if (self.resolved_cia_table) |cia_table_data|
            try cia_table_data.clone(allocator)
        else
            null;
        errdefer if (resolved_cia_table) |*cia_table_data| {
            var owned = cia_table_data.*;
            owned.deinit(allocator);
        };

        return .{
            .mode = self.mode,
            .provider = provider,
            .line_list = line_list,
            .line_mixing = line_mixing,
            .strong_lines = strong_lines,
            .cia_table = cia_table,
            .operational_lut = operational_lut,
            .resolved_line_list = resolved_line_list,
            .resolved_cia_table = resolved_cia_table,
        };
    }

    pub fn deinitOwned(self: *Spectroscopy, allocator: Allocator) void {
        if (self.provider.len != 0) allocator.free(self.provider);
        freeBindingName(allocator, self.line_list);
        freeBindingName(allocator, self.line_mixing);
        freeBindingName(allocator, self.strong_lines);
        freeBindingName(allocator, self.cia_table);
        freeBindingName(allocator, self.operational_lut);
        if (self.resolved_line_list) |*line_list_data| {
            var owned = line_list_data.*;
            owned.deinit(allocator);
        }
        if (self.resolved_cia_table) |*cia_table_data| {
            var owned = cia_table_data.*;
            owned.deinit(allocator);
        }
        self.* = .{};
    }
};

pub const Absorber = struct {
    id: []const u8 = "",
    species: []const u8 = "",
    profile_source: Binding = .{},
    spectroscopy: Spectroscopy = .{},

    pub fn validate(self: Absorber) errors.Error!void {
        if (self.id.len == 0 or self.species.len == 0) {
            return errors.Error.InvalidRequest;
        }
        try self.profile_source.validate();
        try self.spectroscopy.validate();
    }

    pub fn clone(self: Absorber, allocator: Allocator) !Absorber {
        return .{
            .id = try allocator.dupe(u8, self.id),
            .species = try allocator.dupe(u8, self.species),
            .profile_source = try cloneBinding(allocator, self.profile_source),
            .spectroscopy = try self.spectroscopy.clone(allocator),
        };
    }

    pub fn deinitOwned(self: *Absorber, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.species);
        freeBindingName(allocator, self.profile_source);
        self.spectroscopy.deinitOwned(allocator);
        self.* = undefined;
    }
};

pub const AbsorberSet = struct {
    items: []const Absorber = &[_]Absorber{},

    pub fn validate(self: AbsorberSet) errors.Error!void {
        for (self.items, 0..) |absorber, index| {
            try absorber.validate();
            for (self.items[index + 1 ..]) |other| {
                if (std.mem.eql(u8, absorber.id, other.id)) {
                    return errors.Error.InvalidRequest;
                }
            }
        }
    }

    pub fn clone(self: AbsorberSet, allocator: Allocator) !AbsorberSet {
        const items = try allocator.alloc(Absorber, self.items.len);
        errdefer allocator.free(items);
        var initialized: usize = 0;
        errdefer {
            for (items[0..initialized]) |*item| item.deinitOwned(allocator);
        }
        for (self.items, 0..) |absorber, index| {
            items[index] = try absorber.clone(allocator);
            initialized += 1;
        }
        return .{ .items = items };
    }

    pub fn deinitOwned(self: *AbsorberSet, allocator: Allocator) void {
        for (0..self.items.len) |index| @constCast(&self.items[index]).deinitOwned(allocator);
        if (self.items.len != 0) allocator.free(self.items);
        self.* = .{};
    }
};

fn cloneBinding(allocator: Allocator, binding: Binding) !Binding {
    return .{
        .kind = binding.kind,
        .name = if (binding.name.len != 0) try allocator.dupe(u8, binding.name) else "",
    };
}

fn freeBindingName(allocator: Allocator, binding: Binding) void {
    if (binding.name.len != 0) allocator.free(binding.name);
}

test "absorber set validates explicit spectroscopy bindings" {
    const valid: AbsorberSet = .{
        .items = &[_]Absorber{
            .{
                .id = "o2",
                .species = "o2",
                .profile_source = .{ .kind = .atmosphere },
                .spectroscopy = .{
                    .mode = .line_by_line,
                    .provider = "builtin.cross_sections",
                    .line_list = .{ .kind = .asset, .name = "o2_hitran" },
                },
            },
            .{
                .id = "o2o2",
                .species = "o2o2",
                .profile_source = .{ .kind = .atmosphere },
                .spectroscopy = .{
                    .mode = .cia,
                    .cia_table = .{ .kind = .asset, .name = "o2o2_cia" },
                },
            },
        },
    };
    try valid.validate();

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (AbsorberSet{
            .items = &[_]Absorber{
                .{
                    .id = "o2",
                    .species = "o2",
                    .spectroscopy = .{
                        .mode = .none,
                        .line_list = .{ .kind = .asset, .name = "unexpected" },
                    },
                },
            },
        }).validate(),
    );
}
