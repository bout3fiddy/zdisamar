const std = @import("std");

pub const Error = error{
    InvalidRange,
    InvalidValue,
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: start_nm=8 B, end_nm=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const WavelengthRange = struct {
    // UNITS:
    //   Both bounds are stored in nanometers because the public scene model expresses
    //   spectral coverage on that grid before any wavenumber-space transforms.
    start_nm: f64 = 270.0,
    end_nm: f64 = 2400.0,

    pub fn validate(self: WavelengthRange) Error!void {
        if (!std.math.isFinite(self.start_nm) or !std.math.isFinite(self.end_nm)) {
            return Error.InvalidValue;
        }
        if (self.end_nm <= self.start_nm) {
            return Error.InvalidRange;
        }
    }
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: bottom_km=8 B, top_km=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const AltitudeRangeKm = struct {
    bottom_km: f64 = 0.0,
    top_km: f64 = 0.0,

    pub fn validate(self: AltitudeRangeKm) Error!void {
        if (!std.math.isFinite(self.bottom_km) or !std.math.isFinite(self.top_km)) {
            return Error.InvalidValue;
        }
        if (self.bottom_km < 0.0 or self.top_km < self.bottom_km) {
            return Error.InvalidRange;
        }
    }
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: top_hpa=8 B, bottom_hpa=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const PressureRangeHpa = struct {
    top_hpa: f64 = 0.0,
    bottom_hpa: f64 = 0.0,

    pub fn validate(self: PressureRangeHpa) Error!void {
        if (!std.math.isFinite(self.top_hpa) or !std.math.isFinite(self.bottom_hpa)) {
            return Error.InvalidValue;
        }
        if (self.top_hpa <= 0.0 or self.bottom_hpa <= 0.0 or self.bottom_hpa < self.top_hpa) {
            return Error.InvalidRange;
        }
    }
};

// layout(64-bit):
//   size: 8 B, align: 8 B
//   field storage: value=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 8 B (0.008 KiB); total = per instance * live instance count
pub const AngleDeg = struct {
    // UNITS:
    //   Stored in degrees to match the geometry parameters used by the canonical scene
    //   model and vendor-facing adapter layers.
    value: f64 = 0.0,

    pub fn validate(self: AngleDeg) Error!void {
        if (!std.math.isFinite(self.value)) {
            return Error.InvalidValue;
        }
    }
};

// layout(64-bit):
//   size: 8 B, align: 8 B
//   field storage: value=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 8 B (0.008 KiB); total = per instance * live instance count
pub const ZenithAngleDeg = struct {
    value: f64 = 0.0,

    pub fn validate(self: ZenithAngleDeg) Error!void {
        try (AngleDeg{ .value = self.value }).validate();
        if (self.value < 0.0 or self.value > 180.0) {
            return Error.InvalidRange;
        }
    }
};

// layout(64-bit):
//   size: 8 B, align: 8 B
//   field storage: value=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 8 B (0.008 KiB); total = per instance * live instance count
pub const AzimuthAngleDeg = struct {
    value: f64 = 0.0,

    pub fn validate(self: AzimuthAngleDeg) Error!void {
        try (AngleDeg{ .value = self.value }).validate();
        if (self.value < 0.0 or self.value > 360.0) {
            return Error.InvalidRange;
        }
    }
};
