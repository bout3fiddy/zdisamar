const std = @import("std");
const errors = @import("../../common/errors.zig");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

pub const FractionTarget = types.FractionTarget;
pub const FractionKind = types.FractionKind;

// fraction_control.zig ---------------------------------------------------------------------------------------|
// Wavelength-dependent aerosol fraction controls shared by scene validation and prepared optical state.       |
//                                                                                                             |
// called by                                                                                                   |
//   Atmosphere.zig re-exports FractionControl; Aerosol.zig validates that active controls target aerosol      |
//   optical-depth splitting rather than an unrelated quantity.                                                |
//   optical_properties/state_build/context.zig clones the scene control into setup-owned storage before       |
//   Finalize.assemble moves it into PreparedOpticalState.                                                     |
//   layer_accumulation.zig samples scene-time controls while building support rows. state_scalar.zig,         |
//   forward_layers.zig, phase_functions.zig, and atmospheric_budget.zig read the prepared copy during         |
//   wavelength evaluation and diagnostics.                                                                    |
//                                                                                                             |
// main paths                                                                                                  |
//   validate rejects inert-but-populated controls, missing targets/kinds, bad lengths, unsorted wavelengths,  |
//   and non-finite or out-of-range fraction values.                                                           |
//   valueAtWavelength returns the disabled zero, the constant fraction, or a clamped linear interpolation.    |
//   clone/deinitOwned are the ownership handoff from borrowed scene slices into PreparedOpticalState.         |
//                                                                                                             |
// runtime shape                                                                                               |
//   FractionControl is a compact header over up to four out-of-line f64 arrays. Parser/input rows usually     |
//   borrow those arrays; prepared state owns duplicated arrays when owns_arrays is true.                      |
//                                                                                                             |
// hot path                                                                                                    |
//   Fraction controls are optional, but enabled aerosol routes sample valueAtWavelength for layer/support     |
//   preparation and prepared optical-depth evaluation. The sampler allocates nothing and only scans the       |
//   wavelength breakpoints needed to find the enclosing interval.                                             |
// ------------------------------------------------------------------------------------------------------------|

// FractionControl --------------------------------------------------------------------------------------------|
// One wavelength-dependent fraction-control bundle.                                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] threshold_variance : f64                                                                           |
// [ 8..23] wavelengths_nm      : []const f64                                                                  |
// [24..39] values              : []const f64                                                                  |
// [40..55] apriori_values      : []const f64                                                                  |
// [56..71] variance_values     : []const f64                                                                  |
// [72..75] enabled, target, kind, owns_arrays : bool + two enum tags + bool                                   |
// [76..79] trailing padding    : 4 B                                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   arrays are out-of-line. They are borrowed unless owns_arrays is true.                                     |
//                                                                                                             |
// unused bits: 32 padding + 13 enum-storage slack + 14 bool-storage slack = 59 bits                           |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 80 B (0.078 KiB); total also includes owned arrays                                |
pub const FractionControl = struct {
    enabled: bool = false,
    target: FractionTarget = .none,
    kind: FractionKind = .none,
    threshold_variance: f64 = 0.0,
    wavelengths_nm: []const f64 = &.{},
    values: []const f64 = &.{},
    apriori_values: []const f64 = &.{},
    variance_values: []const f64 = &.{},
    owns_arrays: bool = false,

    pub fn validate(self: FractionControl) errors.Error!void {
        if (!self.enabled) {
            if (self.target != .none or
                self.kind != .none or
                self.values.len != 0 or
                self.apriori_values.len != 0 or
                self.variance_values.len != 0)
            {
                return errors.Error.InvalidRequest;
            }
            return;
        }

        if (self.target == .none or self.kind == .none) return errors.Error.InvalidRequest;
        if (self.values.len == 0) return errors.Error.InvalidRequest;
        if (self.kind == .wavel_independent and self.values.len != 1) return errors.Error.InvalidRequest;

        if (self.kind == .wavel_dependent and self.wavelengths_nm.len != self.values.len) {
            return errors.Error.InvalidRequest;
        }

        if (self.apriori_values.len != 0 and self.apriori_values.len != self.values.len) {
            return errors.Error.InvalidRequest;
        }

        if (self.variance_values.len != 0 and self.variance_values.len != self.values.len) {
            return errors.Error.InvalidRequest;
        }

        for (self.values) |value| {
            if (!std.math.isFinite(value) or value < 0.0 or value > 1.0) return errors.Error.InvalidRequest;
        }

        for (self.apriori_values) |value| {
            if (!std.math.isFinite(value) or value < 0.0 or value > 1.0) return errors.Error.InvalidRequest;
        }

        for (self.variance_values) |value| {
            if (!std.math.isFinite(value) or value < 0.0) return errors.Error.InvalidRequest;
        }

        for (self.wavelengths_nm) |wavelength_nm| {
            if (!std.math.isFinite(wavelength_nm) or wavelength_nm <= 0.0) return errors.Error.InvalidRequest;
        }

        if (self.kind == .wavel_dependent and self.wavelengths_nm.len > 1) {
            var previous_wavelength_nm = self.wavelengths_nm[0];
            for (self.wavelengths_nm[1..]) |wavelength_nm| {
                if (wavelength_nm <= previous_wavelength_nm) return errors.Error.InvalidRequest;
                previous_wavelength_nm = wavelength_nm;
            }
        }
        if (self.threshold_variance < 0.0) return errors.Error.InvalidRequest;
    }

    pub fn valueAtWavelength(self: FractionControl, wavelength_nm: f64) f64 {
        // FractionControl.valueAtWavelength ------------------------------------------------------------------|
        // Sample or clamp the fraction value for one wavelength.                                              |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : aerosol optical-depth evaluation when fraction controls are enabled                    |
        //   work     : constant control returns one value; wavelength-dependent control brackets and blends   |
        //   memory   : reads wavelengths_nm and values slice headers, then scans adjacent support samples     |
        // ----------------------------------------------------------------------------------------------------|

        if (!self.enabled or self.values.len == 0) return 0.0;
        if (self.kind != .wavel_dependent or self.wavelengths_nm.len == 0) {
            return std.math.clamp(self.values[0], 0.0, 1.0);
        }

        if (wavelength_nm <= self.wavelengths_nm[0]) return std.math.clamp(self.values[0], 0.0, 1.0);
        for (
            self.wavelengths_nm[0 .. self.wavelengths_nm.len - 1],
            self.wavelengths_nm[1..],
            0..,
        ) |left, right, index| {
            if (wavelength_nm > right) continue;

            const span = right - left;
            if (span <= 0.0) return std.math.clamp(self.values[index + 1], 0.0, 1.0);

            const weight = std.math.clamp((wavelength_nm - left) / span, 0.0, 1.0);
            return std.math.clamp(
                self.values[index] + weight * (self.values[index + 1] - self.values[index]),
                0.0,
                1.0,
            );
        }

        return std.math.clamp(self.values[self.values.len - 1], 0.0, 1.0);
    }

    pub fn clone(self: FractionControl, allocator: Allocator) !FractionControl {
        const wavelengths_nm = if (self.wavelengths_nm.len != 0)
            try allocator.dupe(f64, self.wavelengths_nm)
        else
            &.{};
        errdefer if (self.wavelengths_nm.len != 0) allocator.free(wavelengths_nm);

        const values = if (self.values.len != 0)
            try allocator.dupe(f64, self.values)
        else
            &.{};
        errdefer if (self.values.len != 0) allocator.free(values);

        const apriori_values = if (self.apriori_values.len != 0)
            try allocator.dupe(f64, self.apriori_values)
        else
            &.{};
        errdefer if (self.apriori_values.len != 0) allocator.free(apriori_values);

        const variance_values = if (self.variance_values.len != 0)
            try allocator.dupe(f64, self.variance_values)
        else
            &.{};
        errdefer if (self.variance_values.len != 0) allocator.free(variance_values);

        return .{
            .enabled = self.enabled,
            .target = self.target,
            .kind = self.kind,
            .threshold_variance = self.threshold_variance,
            .wavelengths_nm = wavelengths_nm,
            .values = values,
            .apriori_values = apriori_values,
            .variance_values = variance_values,
            .owns_arrays = wavelengths_nm.len != 0 or
                values.len != 0 or
                apriori_values.len != 0 or
                variance_values.len != 0,
        };
    }

    pub fn deinitOwned(self: *FractionControl, allocator: Allocator) void {
        if (!self.owns_arrays) {
            self.* = .{};
            return;
        }
        if (self.wavelengths_nm.len != 0) allocator.free(self.wavelengths_nm);
        if (self.values.len != 0) allocator.free(self.values);
        if (self.apriori_values.len != 0) allocator.free(self.apriori_values);
        if (self.variance_values.len != 0) allocator.free(self.variance_values);
        self.* = .{};
    }
};
