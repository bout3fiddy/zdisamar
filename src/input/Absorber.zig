const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");
const Binding = @import("Binding.zig").Binding;
const ReferenceData = @import("ReferenceData.zig");
const OperationalCrossSectionLut = @import("Instrument.zig").OperationalCrossSectionLut;

// Absorber.zig -----------------------------------------------------------------------------------------------|
// Public absorber, spectroscopy binding, and resolved absorption payload model.                               |
//                                                                                                             |
// used by                                                                                                     |
//   Scene stores AbsorberSet as the gas/continuum/line input surface                                          |
//   reference_data/bundled workflows attach concrete line, CIA, cross-section, and LUT payloads               |
//   optical_properties/state_build/absorbers.zig turns validated rows into prepared absorber state            |
//   Scene.lutCompatibilityKey hashes active line-gas controls and spectroscopy bindings                       |
//                                                                                                             |
// main paths                                                                                                  |
//   resolveAbsorberSpeciesName normalizes public and vendor O2/O2-O2 names                                    |
//   Spectroscopy.validate enforces mode-specific bindings, controls, and resolved payloads                    |
//   LineGasControls.active chooses simulation or retrieval stage controls for prepared spectroscopy           |
//   clone/deinitOwned duplicate and release binding names plus resolved reference payloads                    |
//                                                                                                             |
// boundary                                                                                                    |
//   This file stores typed references and optional resolved payloads. It does not load files or parse assets; |
//   loaders either attach a matching payload, reject invalid combinations, or leave inactive fields empty.    |
//                                                                                                             |
// memory                                                                                                      |
//   Absorber and Spectroscopy are public value headers over nested bindings and optional owned payloads.      |
//   Clone deep-copies names, isotope selections, and resolved tables so prepared scenes can own their inputs. |
// ------------------------------------------------------------------------------------------------------------|

pub const AbsorberSpecies = enum {
    o2_o2,
    o2,

    pub fn isLineAbsorbing(self: AbsorberSpecies) bool {
        return switch (self) {
            .o2 => true,
            else => false,
        };
    }

    pub fn isCrossSection(self: AbsorberSpecies) bool {
        return switch (self) {
            .o2_o2 => true,
            else => false,
        };
    }

    pub fn hitranIndex(self: AbsorberSpecies) ?u8 {
        return switch (self) {
            .o2 => 7,
            else => null,
        };
    }

    pub fn fromVendorName(name: []const u8) ?AbsorberSpecies {
        const map = .{
            .{ "O2-O2", .o2_o2 },
            .{ "O2", .o2 },
        };
        inline for (map) |entry| {
            if (std.mem.eql(u8, name, entry[0])) return entry[1];
        }
        return null;
    }
};

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

// ActiveLineGasControls --------------------------------------------------------------------------------------|
// Resolved line-gas controls for the selected simulation or retrieval stage.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] isotopes           : []const u8                                                                    |
// [16..31] threshold_line     : ?f64                                                                          |
// [32..47] cutoff_cm1         : ?f64                                                                          |
// [48..55] line_mixing_factor : f64                                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   isotopes points at the active isotope selection; it is borrowed from LineGasControls storage.             |
//                                                                                                             |
// unused bits: 0 top-level padding; optional-f64 tag slack stays inside ?f64 storage                          |
// footprint: per instance = 56 B (0.055 KiB); total also includes referenced isotope bytes                    |
pub const ActiveLineGasControls = struct {
    isotopes: []const u8 = &.{},
    threshold_line: ?f64 = null,
    cutoff_cm1: ?f64 = null,
    line_mixing_factor: f64 = 1.0,
};
// ------------------------------------------------------------------------------------------------------------|

// AbsorptionRepresentation -----------------------------------------------------------------------------------|
// Pointer-sized view of the resolved absorption implementation selected by Spectroscopy.                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// active payload : one pointer to line, cross-section table, or cross-section LUT storage                     |
// active tag     : union tag plus alignment padding                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   payload pointers are borrowed views into Spectroscopy resolved payload fields.                            |
//                                                                                                             |
// footprint: per instance = 16 B (0.016 KiB); total also includes referenced payload storage                  |
pub const AbsorptionRepresentation = union(enum) {
    none,
    line_abs: *const ReferenceData.SpectroscopyLineList,
    xsec_table: *const ReferenceData.CrossSectionTable,
    xsec_lut: *const OperationalCrossSectionLut,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn resolveAbsorberSpeciesName(species_name: []const u8) ?AbsorberSpecies {
    if (std.meta.stringToEnum(AbsorberSpecies, species_name)) |species| return species;
    if (std.ascii.eqlIgnoreCase(species_name, "o2_o2")) return .o2_o2;
    if (std.ascii.eqlIgnoreCase(species_name, "o2o2")) return .o2_o2;
    if (std.ascii.eqlIgnoreCase(species_name, "o2-o2")) return .o2_o2;
    return null;
}

pub fn resolvedAbsorberSpecies(absorber: anytype) ?AbsorberSpecies {
    if (absorber.resolved_species) |species| return species;
    return resolveAbsorberSpeciesName(absorber.species);
}

// LineGasControls --------------------------------------------------------------------------------------------|
// Stage-specific line-gas knobs parsed from input.                                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 136 B (0.133 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] factor_lm_sim        : ?f64                                                                      |
// [ 16.. 31] factor_lm_retr       : ?f64                                                                      |
// [ 32.. 47] isotopes_sim         : []const u8                                                                |
// [ 48.. 63] isotopes_retr        : []const u8                                                                |
// [ 64.. 79] threshold_line_sim   : ?f64                                                                      |
// [ 80.. 95] threshold_line_retr  : ?f64                                                                      |
// [ 96..111] cutoff_sim_cm1       : ?f64                                                                      |
// [112..127] cutoff_retr_cm1      : ?f64                                                                      |
// [128..128] active_stage         : SpectroscopyStage                                                         |
// [129..135] trailing padding     : 7 B                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   isotope slices point at out-of-line bytes and are owned by cloned LineGasControls.                        |
//                                                                                                             |
// unused bits: 56 padding + 6 enum-storage slack; optional-f64 tag slack stays inside ?f64 storage            |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 136 B (0.133 KiB); total also includes owned isotope bytes                        |
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

    pub fn active(self: LineGasControls) ActiveLineGasControls {
        switch (self.active_stage) {
            .simulation => return .{
                .isotopes = self.isotopes_sim,
                .threshold_line = self.threshold_line_sim,
                .cutoff_cm1 = self.cutoff_sim_cm1,
                .line_mixing_factor = self.factor_lm_sim orelse 1.0,
            },
            .retrieval => return .{
                .isotopes = self.isotopes_retr,
                .threshold_line = self.threshold_line_retr,
                .cutoff_cm1 = self.cutoff_retr_cm1,
                .line_mixing_factor = self.factor_lm_retr orelse 1.0,
            },
            .none => {},
        }

        var isotopes = self.isotopes_retr;
        if (self.isotopes_sim.len != 0) isotopes = self.isotopes_sim;

        return .{
            .isotopes = isotopes,
            .threshold_line = self.threshold_line_sim orelse self.threshold_line_retr,
            .cutoff_cm1 = self.cutoff_sim_cm1 orelse self.cutoff_retr_cm1,
            .line_mixing_factor = self.factor_lm_sim orelse self.factor_lm_retr orelse 1.0,
        };
    }

    pub fn clone(self: LineGasControls, allocator: Allocator) !LineGasControls {
        const isotopes_sim = try cloneIsotopeSelection(allocator, self.isotopes_sim);
        errdefer if (isotopes_sim.len != 0) allocator.free(isotopes_sim);

        const isotopes_retr = try cloneIsotopeSelection(allocator, self.isotopes_retr);
        errdefer if (isotopes_retr.len != 0) allocator.free(isotopes_retr);

        return .{
            .factor_lm_sim = self.factor_lm_sim,
            .factor_lm_retr = self.factor_lm_retr,
            .isotopes_sim = isotopes_sim,
            .isotopes_retr = isotopes_retr,
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
// ------------------------------------------------------------------------------------------------------------|

fn cloneIsotopeSelection(allocator: Allocator, isotopes: []const u8) ![]const u8 {
    if (isotopes.len == 0) return &.{};
    return try allocator.dupe(u8, isotopes);
}

// Spectroscopy -----------------------------------------------------------------------------------------------|
// Bindings and resolved payloads for one absorber's absorption model.                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 832 B (0.812 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 55] line_list                    : Binding                                                           |
// [ 56..111] line_mixing                  : Binding                                                           |
// [112..167] strong_lines                 : Binding                                                           |
// [168..223] cia_table                    : Binding                                                           |
// [224..279] cross_section_table          : Binding                                                           |
// [280..335] operational_lut              : Binding                                                           |
// [336..471] line_gas_controls            : LineGasControls                                                   |
// [472..687] resolved_line_list           : ?SpectroscopyLineList                                             |
// [688..719] resolved_cia_table           : ?CollisionInducedAbsorptionTable                                  |
// [720..743] resolved_cross_section_table : ?CrossSectionTable                                                |
// [744..823] resolved_cross_section_lut   : ?OperationalCrossSectionLut                                       |
// [824..824] mode                         : SpectroscopyMode                                                  |
// [825..831] trailing padding             : 7 B                                                               |
//                                                                                                             |
// referenced storage                                                                                          |
//   bindings point at input names. resolved payloads carry nested out-of-line spectroscopy/table/LUT storage. |
//                                                                                                             |
// unused bits: 56 padding + 6 enum-storage slack; optional payload tags are inside nested optional storage    |
// cache span: 13 cache lines at 64 B per line                                                                 |
// footprint: per instance = 832 B (0.812 KiB); total also includes referenced resolved payload storage        |
pub const Spectroscopy = struct {
    mode: SpectroscopyMode = .none,
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

        const disabled_mode_has_attached_state =
            self.mode == .none and
            (self.line_list.enabled() or
                self.line_mixing.enabled() or
                self.strong_lines.enabled() or
                self.cia_table.enabled() or
                self.cross_section_table.enabled() or
                self.operational_lut.enabled() or
                self.line_gas_controls.configured() or
                self.resolved_line_list != null or
                self.resolved_cia_table != null or
                self.resolved_cross_section_table != null or
                self.resolved_cross_section_lut != null);
        if (disabled_mode_has_attached_state) {

            // `.mode == .none` is a true disabled state. No implementation, binding, control, or
            // resolved reference payload may remain attached in that case.
            return errors.Error.InvalidRequest;
        }

        // Resolved payloads are only legal when their matching spectroscopy modes are active.
        // Carrying them across mode switches would silently desynchronize the scene.
        const has_line_list_payload = self.resolved_line_list != null;
        if (has_line_list_payload and self.mode != .line_by_line) return errors.Error.InvalidRequest;

        const has_cia_payload = self.resolved_cia_table != null;
        if (has_cia_payload and self.mode != .cia) return errors.Error.InvalidRequest;

        const has_cross_section_payload = self.resolved_cross_section_table != null;
        if (has_cross_section_payload and self.mode != .cross_sections) return errors.Error.InvalidRequest;

        const has_operational_lut_payload = self.resolved_cross_section_lut != null;
        if (has_operational_lut_payload and !self.operational_lut.enabled()) {
            return errors.Error.InvalidRequest;
        }

        const has_cross_section_table = self.cross_section_table.enabled() or self.resolved_cross_section_table != null;
        const has_cross_section_lut = self.operational_lut.enabled() or self.resolved_cross_section_lut != null;
        if (self.mode == .cross_sections) {
            if (has_cross_section_table and has_cross_section_lut) return errors.Error.InvalidRequest;
        }
    }

    pub fn clone(self: Spectroscopy, allocator: Allocator) !Spectroscopy {
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

        const resolved_cross_section_table = choose_resolved_cross_section_table: {
            break :choose_resolved_cross_section_table if (self.resolved_cross_section_table) |cross_section_table_data|
                ReferenceData.CrossSectionTable{
                    .points = try allocator.dupe(ReferenceData.CrossSectionPoint, cross_section_table_data.points),
                }
            else
                null;
        };
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
// ------------------------------------------------------------------------------------------------------------|

// Absorber ---------------------------------------------------------------------------------------------------|
// Public absorber header with species identity, profile binding, VMR profile, and spectroscopy state.         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 944 B (0.922 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] id                              : []const u8                                                     |
// [ 16.. 31] species                         : []const u8                                                     |
// [ 32.. 87] profile_source                  : Binding                                                        |
// [ 88..103] volume_mixing_ratio_profile_ppmv: []const [2]f64                                                 |
// [104..935] spectroscopy                    : Spectroscopy                                                   |
// [936..937] resolved_species                : ?AbsorberSpecies                                               |
// [938..943] trailing padding                : 6 B                                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   id/species strings, VMR profile rows, profile binding names, and nested spectroscopy payloads are         |
//   out-of-line. clone owns these copies; deinitOwned releases them.                                          |
//                                                                                                             |
// unused bits: 48 padding + optional enum-storage slack in resolved_species                                   |
// cache span: 15 cache lines at 64 B per line                                                                 |
// footprint: per instance = 944 B (0.922 KiB); total also includes referenced absorber storage                |
pub const Absorber = struct {
    id: []const u8 = "",
    species: []const u8 = "",

    resolved_species: ?AbsorberSpecies = null,
    profile_source: Binding = .none,
    volume_mixing_ratio_profile_ppmv: []const [2]f64 = &.{},
    spectroscopy: Spectroscopy = .{},

    pub fn validate(self: Absorber) errors.Error!void {
        if (self.id.len == 0 or self.species.len == 0) {
            return errors.Error.InvalidRequest;
        }
        _ = resolvedAbsorberSpecies(self) orelse return errors.Error.InvalidRequest;
        try self.profile_source.validate();
        try validateVolumeMixingRatioProfile(self.volume_mixing_ratio_profile_ppmv);
        try self.spectroscopy.validate();
    }

    pub fn clone(self: Absorber, allocator: Allocator) !Absorber {
        const volume_mixing_ratio_profile_ppmv = if (self.volume_mixing_ratio_profile_ppmv.len != 0)
            try allocator.dupe([2]f64, self.volume_mixing_ratio_profile_ppmv)
        else
            &.{};

        return .{
            .id = try allocator.dupe(u8, self.id),
            .species = try allocator.dupe(u8, self.species),
            .resolved_species = self.resolved_species,
            .profile_source = try self.profile_source.clone(allocator),
            .volume_mixing_ratio_profile_ppmv = volume_mixing_ratio_profile_ppmv,
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
// ------------------------------------------------------------------------------------------------------------|

// AbsorberSet ------------------------------------------------------------------------------------------------|
// Owner/view header for the scene absorber list.                                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] items : []const Absorber                                                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   items points at out-of-line Absorber rows owned by cloned sets.                                           |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes owned absorber rows                         |
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
// ------------------------------------------------------------------------------------------------------------|

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
