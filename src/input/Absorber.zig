const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");
const Binding = @import("Binding.zig").Binding;
const ReferenceData = @import("ReferenceData.zig");
const OperationalCrossSectionLut = @import("Instrument.zig").OperationalCrossSectionLut;
const species_helpers = @import("absorber/species.zig");
pub const AbsorberSpecies = @import("atmospheric_types.zig").AbsorberSpecies;

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

pub const AbsorptionRepresentation = union(enum) {
    none,
    line_abs: *const ReferenceData.SpectroscopyLineList,
    xsec_table: *const ReferenceData.CrossSectionTable,
    xsec_lut: *const OperationalCrossSectionLut,
};

pub const resolveAbsorberSpeciesName = species_helpers.resolveAbsorberSpeciesName;

pub const resolvedAbsorberSpecies = species_helpers.resolvedAbsorberSpecies;

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
            .simulation => self.factor_lm_sim orelse 1.0,
            .retrieval => self.factor_lm_retr orelse 1.0,
            .none => self.factor_lm_sim orelse self.factor_lm_retr orelse 1.0,
        };
    }

    pub fn activeIsotopes(self: LineGasControls) []const u8 {
        return switch (self.active_stage) {
            .simulation => self.isotopes_sim,
            .retrieval => self.isotopes_retr,
            .none => if (self.isotopes_sim.len != 0) self.isotopes_sim else self.isotopes_retr,
        };
    }

    pub fn activeThresholdLine(self: LineGasControls) ?f64 {
        return switch (self.active_stage) {
            .simulation => self.threshold_line_sim,
            .retrieval => self.threshold_line_retr,
            .none => self.threshold_line_sim orelse self.threshold_line_retr,
        };
    }

    pub fn activeCutoffCm1(self: LineGasControls) ?f64 {
        return switch (self.active_stage) {
            .simulation => self.cutoff_sim_cm1,
            .retrieval => self.cutoff_retr_cm1,
            .none => self.cutoff_sim_cm1 orelse self.cutoff_retr_cm1,
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
    cross_section_table: Binding = .none,
    operational_lut: Binding = .none,
    line_gas_controls: LineGasControls = .{},
    resolved_line_list: ?ReferenceData.SpectroscopyLineList = null,
    resolved_cia_table: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    resolved_cross_section_table: ?ReferenceData.CrossSectionTable = null,
    resolved_cross_section_lut: ?OperationalCrossSectionLut = null,

    pub fn validate(self: Spectroscopy) errors.Error!void {
        try self.line_list.validate();
        try self.line_mixing.validate();
        try self.strong_lines.validate();
        try self.cia_table.validate();
        try self.cross_section_table.validate();
        try self.operational_lut.validate();
        try self.line_gas_controls.validate();

        if (self.mode == .none and
            (self.provider.len != 0 or
                self.line_list.enabled() or
                self.line_mixing.enabled() or
                self.strong_lines.enabled() or
                self.cia_table.enabled() or
                self.cross_section_table.enabled() or
                self.operational_lut.enabled() or
                self.line_gas_controls.configured() or
                self.resolved_line_list != null or
                self.resolved_cia_table != null or
                self.resolved_cross_section_table != null or
                self.resolved_cross_section_lut != null))
        {
            // INVARIANT:
            //   `.mode == .none` is a true disabled state. No implementation, binding, control, or
            //   resolved reference payload may remain attached in that case.
            return errors.Error.InvalidRequest;
        }
        // GOTCHA:
        //   Resolved line and CIA tables are only legal when their matching spectroscopy modes
        //   are active. Carrying them across mode switches would silently desynchronize the scene.
        if (self.resolved_line_list != null and self.mode != .line_by_line) return errors.Error.InvalidRequest;
        if (self.resolved_cia_table != null and self.mode != .cia) return errors.Error.InvalidRequest;
        if (self.resolved_cross_section_table != null and self.mode != .cross_sections) return errors.Error.InvalidRequest;
        if (self.resolved_cross_section_lut != null and !self.operational_lut.enabled()) return errors.Error.InvalidRequest;

        const has_cross_section_table = self.cross_section_table.enabled() or self.resolved_cross_section_table != null;
        const has_cross_section_lut = self.operational_lut.enabled() or self.resolved_cross_section_lut != null;
        if (self.mode == .cross_sections) {
            if (has_cross_section_table and has_cross_section_lut) return errors.Error.InvalidRequest;
        }
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
        const cross_section_table = try self.cross_section_table.clone(allocator);
        errdefer {
            var owned = cross_section_table;
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

        const resolved_cross_section_table = if (self.resolved_cross_section_table) |cross_section_table_data|
            ReferenceData.CrossSectionTable{
                .points = try allocator.dupe(ReferenceData.CrossSectionPoint, cross_section_table_data.points),
            }
        else
            null;
        errdefer if (resolved_cross_section_table) |*cross_section_table_data| {
            var owned = cross_section_table_data.*;
            owned.deinit(allocator);
        };

        const resolved_cross_section_lut = if (self.resolved_cross_section_lut) |lut|
            try lut.clone(allocator)
        else
            null;
        errdefer if (resolved_cross_section_lut) |*lut| {
            var owned = lut.*;
            owned.deinitOwned(allocator);
        };

        return .{
            .mode = self.mode,
            .provider = provider,
            .line_list = line_list,
            .line_mixing = line_mixing,
            .strong_lines = strong_lines,
            .cia_table = cia_table,
            .cross_section_table = cross_section_table,
            .operational_lut = operational_lut,
            .line_gas_controls = line_gas_controls,
            .resolved_line_list = resolved_line_list,
            .resolved_cia_table = resolved_cia_table,
            .resolved_cross_section_table = resolved_cross_section_table,
            .resolved_cross_section_lut = resolved_cross_section_lut,
        };
    }

    pub fn deinitOwned(self: *Spectroscopy, allocator: Allocator) void {
        if (self.provider.len != 0) allocator.free(self.provider);
        self.line_list.deinitOwned(allocator);
        self.line_mixing.deinitOwned(allocator);
        self.strong_lines.deinitOwned(allocator);
        self.cia_table.deinitOwned(allocator);
        self.cross_section_table.deinitOwned(allocator);
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
        if (self.resolved_cross_section_table) |*cross_section_table_data| {
            var owned = cross_section_table_data.*;
            owned.deinit(allocator);
        }
        if (self.resolved_cross_section_lut) |*lut| {
            var owned = lut.*;
            owned.deinitOwned(allocator);
        }
        self.* = .{};
    }

    pub fn resolvedAbsorptionRepresentation(self: *const Spectroscopy) AbsorptionRepresentation {
        if (self.resolved_cross_section_lut) |*lut| return .{ .xsec_lut = lut };
        if (self.resolved_cross_section_table) |*table| return .{ .xsec_table = table };
        if (self.resolved_line_list) |*line_list| return .{ .line_abs = line_list };
        return .none;
    }
};

pub const Absorber = struct {
    id: []const u8 = "",
    species: []const u8 = "",
    // Typed species identity resolved from the string `species` field.
    // Null when the species string has not been resolved against the
    // vendor species catalogue.
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

fn validateIsotopeSelection(isotopes: []const u8) errors.Error!void {
    for (isotopes, 0..) |isotope, index| {
        if (isotope == 0) return errors.Error.InvalidRequest;
        for (isotopes[index + 1 ..]) |other| {
            if (isotope == other) return errors.Error.InvalidRequest;
        }
    }
}

pub fn validateVolumeMixingRatioProfile(profile_ppmv: []const [2]f64) errors.Error!void {
    var previous_pressure_hpa: ?f64 = null;
    var descending: ?bool = null;
    for (profile_ppmv) |entry| {
        if (!std.math.isFinite(entry[0]) or !std.math.isFinite(entry[1])) {
            return errors.Error.InvalidRequest;
        }
        if (entry[0] <= 0.0 or entry[1] < 0.0) {
            return errors.Error.InvalidRequest;
        }
        if (previous_pressure_hpa) |previous| {
            if (entry[0] == previous) return errors.Error.InvalidRequest;
            const entry_descending = entry[0] < previous;
            if (descending) |expected_descending| {
                if (entry_descending != expected_descending) return errors.Error.InvalidRequest;
            } else {
                descending = entry_descending;
            }
        }
        previous_pressure_hpa = entry[0];
    }
}
