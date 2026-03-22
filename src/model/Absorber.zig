const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");
const Binding = @import("Binding.zig").Binding;
const ReferenceData = @import("ReferenceData.zig");
const document_fields = @import("../adapters/canonical_config/document_fields.zig");

pub const AbsorberSpecies = document_fields.AbsorberSpecies;

pub const SpectroscopyMode = enum {
    none,
    line_by_line,
    cia,
    cross_sections,
};

pub const SpectroscopyStage = enum {
    none,
    simulation,
    retrieval,
};

pub const LineGasControls = struct {
    factor_lm_sim: ?f64 = null,
    factor_lm_retr: ?f64 = null,
    isotopes_sim: []const u8 = &.{},
    isotopes_retr: []const u8 = &.{},
    threshold_line_sim: ?f64 = null,
    threshold_line_retr: ?f64 = null,
    cutoff_sim_cm1: ?f64 = null,
    cutoff_retr_cm1: ?f64 = null,
    active_stage: SpectroscopyStage = .none,

    pub fn validate(self: LineGasControls) errors.Error!void {
        if (self.factor_lm_sim) |value| {
            if (!std.math.isFinite(value)) return errors.Error.InvalidRequest;
        }
        if (self.factor_lm_retr) |value| {
            if (!std.math.isFinite(value)) return errors.Error.InvalidRequest;
        }
        if (self.threshold_line_sim) |value| {
            if (!std.math.isFinite(value) or value < 0.0) return errors.Error.InvalidRequest;
        }
        if (self.threshold_line_retr) |value| {
            if (!std.math.isFinite(value) or value < 0.0) return errors.Error.InvalidRequest;
        }
        if (self.cutoff_sim_cm1) |value| {
            if (!std.math.isFinite(value) or value <= 0.0) return errors.Error.InvalidRequest;
        }
        if (self.cutoff_retr_cm1) |value| {
            if (!std.math.isFinite(value) or value <= 0.0) return errors.Error.InvalidRequest;
        }
        try validateIsotopeSelection(self.isotopes_sim);
        try validateIsotopeSelection(self.isotopes_retr);
    }

    pub fn configured(self: LineGasControls) bool {
        return self.factor_lm_sim != null or
            self.factor_lm_retr != null or
            self.isotopes_sim.len != 0 or
            self.isotopes_retr.len != 0 or
            self.threshold_line_sim != null or
            self.threshold_line_retr != null or
            self.cutoff_sim_cm1 != null or
            self.cutoff_retr_cm1 != null;
    }

    pub fn activeLineMixingFactor(self: LineGasControls) f64 {
        return switch (self.active_stage) {
            .simulation => self.factor_lm_sim orelse 0.0,
            .retrieval => self.factor_lm_retr orelse 0.0,
            .none => 0.0,
        };
    }

    pub fn activeIsotopes(self: LineGasControls) []const u8 {
        return switch (self.active_stage) {
            .simulation => self.isotopes_sim,
            .retrieval => self.isotopes_retr,
            .none => &.{},
        };
    }

    pub fn activeThresholdLine(self: LineGasControls) ?f64 {
        return switch (self.active_stage) {
            .simulation => self.threshold_line_sim,
            .retrieval => self.threshold_line_retr,
            .none => null,
        };
    }

    pub fn activeCutoffCm1(self: LineGasControls) ?f64 {
        return switch (self.active_stage) {
            .simulation => self.cutoff_sim_cm1,
            .retrieval => self.cutoff_retr_cm1,
            .none => null,
        };
    }

    pub fn clone(self: LineGasControls, allocator: Allocator) !LineGasControls {
        return .{
            .factor_lm_sim = self.factor_lm_sim,
            .factor_lm_retr = self.factor_lm_retr,
            .isotopes_sim = if (self.isotopes_sim.len != 0) try allocator.dupe(u8, self.isotopes_sim) else &.{},
            .isotopes_retr = if (self.isotopes_retr.len != 0) try allocator.dupe(u8, self.isotopes_retr) else &.{},
            .threshold_line_sim = self.threshold_line_sim,
            .threshold_line_retr = self.threshold_line_retr,
            .cutoff_sim_cm1 = self.cutoff_sim_cm1,
            .cutoff_retr_cm1 = self.cutoff_retr_cm1,
            .active_stage = self.active_stage,
        };
    }

    pub fn deinitOwned(self: *LineGasControls, allocator: Allocator) void {
        if (self.isotopes_sim.len != 0) allocator.free(self.isotopes_sim);
        if (self.isotopes_retr.len != 0) allocator.free(self.isotopes_retr);
        self.* = .{};
    }
};

pub const Spectroscopy = struct {
    mode: SpectroscopyMode = .none,
    provider: []const u8 = "",
    line_list: Binding = .none,
    line_mixing: Binding = .none,
    strong_lines: Binding = .none,
    cia_table: Binding = .none,
    operational_lut: Binding = .none,
    line_gas_controls: LineGasControls = .{},
    resolved_line_list: ?ReferenceData.SpectroscopyLineList = null,
    resolved_cia_table: ?ReferenceData.CollisionInducedAbsorptionTable = null,

    pub fn validate(self: Spectroscopy) errors.Error!void {
        try self.line_list.validate();
        try self.line_mixing.validate();
        try self.strong_lines.validate();
        try self.cia_table.validate();
        try self.operational_lut.validate();
        try self.line_gas_controls.validate();

        if (self.mode == .none and
            (self.provider.len != 0 or
                self.line_list.enabled() or
                self.line_mixing.enabled() or
                self.strong_lines.enabled() or
                self.cia_table.enabled() or
                self.operational_lut.enabled() or
                self.line_gas_controls.configured() or
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

        const line_list = try self.line_list.clone(allocator);
        errdefer {
            var owned = line_list;
            owned.deinitOwned(allocator);
        }
        const line_mixing = try self.line_mixing.clone(allocator);
        errdefer {
            var owned = line_mixing;
            owned.deinitOwned(allocator);
        }
        const strong_lines = try self.strong_lines.clone(allocator);
        errdefer {
            var owned = strong_lines;
            owned.deinitOwned(allocator);
        }
        const cia_table = try self.cia_table.clone(allocator);
        errdefer {
            var owned = cia_table;
            owned.deinitOwned(allocator);
        }
        const operational_lut = try self.operational_lut.clone(allocator);
        errdefer {
            var owned = operational_lut;
            owned.deinitOwned(allocator);
        }
        const line_gas_controls = try self.line_gas_controls.clone(allocator);
        errdefer {
            var owned = line_gas_controls;
            owned.deinitOwned(allocator);
        }

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
            .line_gas_controls = line_gas_controls,
            .resolved_line_list = resolved_line_list,
            .resolved_cia_table = resolved_cia_table,
        };
    }

    pub fn deinitOwned(self: *Spectroscopy, allocator: Allocator) void {
        if (self.provider.len != 0) allocator.free(self.provider);
        self.line_list.deinitOwned(allocator);
        self.line_mixing.deinitOwned(allocator);
        self.strong_lines.deinitOwned(allocator);
        self.cia_table.deinitOwned(allocator);
        self.operational_lut.deinitOwned(allocator);
        self.line_gas_controls.deinitOwned(allocator);
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
    /// Typed species identity resolved from the string `species` field.
    /// Null when the species string has not been resolved against the
    /// vendor species catalogue.
    resolved_species: ?AbsorberSpecies = null,
    profile_source: Binding = .none,
    volume_mixing_ratio_profile_ppmv: []const [2]f64 = &.{},
    spectroscopy: Spectroscopy = .{},

    pub fn validate(self: Absorber) errors.Error!void {
        if (self.id.len == 0 or self.species.len == 0) {
            return errors.Error.InvalidRequest;
        }
        try self.profile_source.validate();
        try validateVolumeMixingRatioProfile(self.volume_mixing_ratio_profile_ppmv);
        try self.spectroscopy.validate();
    }

    pub fn clone(self: Absorber, allocator: Allocator) !Absorber {
        return .{
            .id = try allocator.dupe(u8, self.id),
            .species = try allocator.dupe(u8, self.species),
            .resolved_species = self.resolved_species,
            .profile_source = try self.profile_source.clone(allocator),
            .volume_mixing_ratio_profile_ppmv = if (self.volume_mixing_ratio_profile_ppmv.len != 0)
                try allocator.dupe([2]f64, self.volume_mixing_ratio_profile_ppmv)
            else
                &.{},
            .spectroscopy = try self.spectroscopy.clone(allocator),
        };
    }

    pub fn deinitOwned(self: *Absorber, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.species);
        self.profile_source.deinitOwned(allocator);
        if (self.volume_mixing_ratio_profile_ppmv.len != 0) allocator.free(self.volume_mixing_ratio_profile_ppmv);
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

test "absorber set validates explicit spectroscopy bindings" {
    const valid: AbsorberSet = .{
        .items = &[_]Absorber{
            .{
                .id = "o2",
                .species = "o2",
                .profile_source = .atmosphere,
                .spectroscopy = .{
                    .mode = .line_by_line,
                    .provider = "builtin.cross_sections",
                    .line_list = .{ .asset = .{ .name = "o2_hitran" } },
                },
            },
            .{
                .id = "o2o2",
                .species = "o2o2",
                .profile_source = .atmosphere,
                .spectroscopy = .{
                    .mode = .cia,
                    .cia_table = .{ .asset = .{ .name = "o2o2_cia" } },
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
                        .line_list = .{ .asset = .{ .name = "unexpected" } },
                    },
                },
            },
        }).validate(),
    );
}

fn validateIsotopeSelection(isotopes: []const u8) errors.Error!void {
    for (isotopes, 0..) |isotope, index| {
        if (isotope == 0) return errors.Error.InvalidRequest;
        for (isotopes[index + 1 ..]) |other| {
            if (isotope == other) return errors.Error.InvalidRequest;
        }
    }
}

fn validateVolumeMixingRatioProfile(profile_ppmv: []const [2]f64) errors.Error!void {
    for (profile_ppmv) |entry| {
        if (!std.math.isFinite(entry[0]) or !std.math.isFinite(entry[1])) {
            return errors.Error.InvalidRequest;
        }
        if (entry[0] <= 0.0 or entry[1] < 0.0) {
            return errors.Error.InvalidRequest;
        }
    }
}

test "line-gas controls validate stage-specific isotope and cutoff selections" {
    try (LineGasControls{
        .factor_lm_sim = 1.0,
        .isotopes_sim = &.{ 1, 2 },
        .threshold_line_sim = 0.05,
        .cutoff_sim_cm1 = 12.0,
        .active_stage = .simulation,
    }).validate();

    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        (LineGasControls{ .factor_lm_sim = 1.0, .active_stage = .simulation }).activeLineMixingFactor(),
        1.0e-12,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2 },
        (LineGasControls{ .isotopes_retr = &.{ 1, 2 }, .active_stage = .retrieval }).activeIsotopes(),
    );

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (LineGasControls{ .isotopes_sim = &.{ 1, 1 } }).validate(),
    );
    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (LineGasControls{ .cutoff_retr_cm1 = 0.0 }).validate(),
    );
}
