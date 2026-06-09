const std = @import("std");
const errors = @import("../common/errors.zig");
const Binding = @import("Binding.zig").Binding;
const Allocator = std.mem.Allocator;

pub const IntervalSemantics = @import("atmosphere/types.zig").IntervalSemantics;
pub const ParticlePlacementSemantics = @import("atmosphere/types.zig").ParticlePlacementSemantics;
pub const FractionTarget = @import("atmosphere/types.zig").FractionTarget;
pub const FractionKind = @import("atmosphere/types.zig").FractionKind;
pub const VerticalInterval = @import("atmosphere/interval_grid.zig").VerticalInterval;
pub const IntervalGrid = @import("atmosphere/interval_grid.zig").IntervalGrid;
pub const IntervalPlacement = @import("atmosphere/interval_grid.zig").IntervalPlacement;
pub const FractionControl = @import("atmosphere/fraction_control.zig").FractionControl;

// Atmosphere.zig ---------------------------------------------------------------------------------------------|
// Public atmosphere setup row and re-export point for interval and fraction controls.                         |
//                                                                                                             |
// called from                                                                                                 |
//   Scene.validate checks this row before optical preparation.                                                |
//   vertical_grid.zig calls preparedLayerCount and interval_grid to choose legacy evenly divided layers or    |
//   explicit pressure/altitude intervals.                                                                     |
//   layer_accumulation.zig and Context consume the prepared interval/fraction controls after vertical-grid    |
//   construction, especially for particle and aerosol support placement.                                      |
//   input/o2a_reference/root.zig fills these fields for the O2 A reference cases.                             |
//                                                                                                             |
// main paths                                                                                                  |
//   preparedLayerCount returns the explicit interval count when interval_grid is enabled, otherwise the       |
//   legacy layer_count. That count controls vertical-grid allocation and later prepared layer storage.        |
//   validate rejects inert-looking partial configurations: enabled aerosol/profile/surface-pressure controls  |
//   require at least one prepared layer, interval grids must agree with layer_count when both are present,    |
//   and sublayer_divisions must be non-zero.                                                                  |
//                                                                                                             |
// exported support rows                                                                                       |
//   IntervalSemantics, VerticalInterval, IntervalGrid, IntervalPlacement, and FractionControl live in the     |
//   atmosphere/ submodule files where their payload and layout comments are kept with the concrete structs.   |
//                                                                                                             |
// ownership                                                                                                   |
//   deinitOwned delegates to IntervalGrid. The profile source binding is validated here; binding name storage |
//   is managed by the caller or loader that created the Atmosphere row.                                       |
// ------------------------------------------------------------------------------------------------------------|

// Atmosphere -------------------------------------------------------------------------------------------------|
// Public atmosphere control header.                                                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..55] profile_source       : Binding                                                                     |
// [56..63] surface_pressure_hpa : f64                                                                         |
// [64..87] interval_grid        : IntervalGrid                                                                |
// [88..91] layer_count          : u32                                                                         |
// [92..92] sublayer_divisions   : u8                                                                          |
// [93..93] has_aerosols         : bool                                                                        |
// [94..95] trailing padding     : 2 B                                                                         |
//                                                                                                             |
// referenced storage                                                                                          |
//   profile_source can point at out-of-line binding names. interval_grid may own interval rows.               |
//                                                                                                             |
// unused bits: 16 padding + 7 bool-storage slack = 23 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 96 B (0.094 KiB); total also includes referenced binding/interval storage         |
pub const Atmosphere = struct {
    layer_count: u32 = 0,
    sublayer_divisions: u8 = 3,
    has_aerosols: bool = false,
    profile_source: Binding = .none,
    surface_pressure_hpa: f64 = 0.0,
    interval_grid: IntervalGrid = .{},

    pub fn preparedLayerCount(self: Atmosphere) u32 {
        if (self.interval_grid.enabled()) return self.interval_grid.intervalCount();
        return self.layer_count;
    }

    pub fn validate(self: Atmosphere) errors.Error!void {
        try self.profile_source.validate();
        try self.interval_grid.validate(self.sublayer_divisions);

        if (self.preparedLayerCount() == 0 and
            (self.has_aerosols or self.profile_source.enabled() or self.surface_pressure_hpa != 0.0))
        {
            return errors.Error.InvalidRequest;
        }

        if (self.sublayer_divisions == 0) {
            return errors.Error.InvalidRequest;
        }
        if (self.surface_pressure_hpa != 0.0 and
            (!std.math.isFinite(self.surface_pressure_hpa) or self.surface_pressure_hpa <= 0.0))
        {
            return errors.Error.InvalidRequest;
        }

        if (self.interval_grid.enabled() and
            self.layer_count != 0 and
            self.layer_count != self.interval_grid.intervalCount())
        {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn deinitOwned(self: *Atmosphere, allocator: Allocator) void {
        self.interval_grid.deinitOwned(allocator);
    }
};
// ------------------------------------------------------------------------------------------------------------|
