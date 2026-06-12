const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

// solar_irradiance_memory.zig ------------------------------------------------------------------------------- |
// Exact-wavelength solar irradiance memory for spectrum irradiance integration.                               |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/instrument_grid/grid_calculation/cache.zig` `SpectralEvaluationCache`.      |
//   The old cache deliberately stored only solar irradiance values keyed by exact high-resolution wavelength  |
//   bits during one product simulation.                                                                       |
//                                                                                                             |
// key contract                                                                                                |
//   `keyFor` uses the exact f64 bit pattern, not rounded wavelength bins. Adaptive support wavelengths can be |
//   close while still physically distinct.                                                                    |
//                                                                                                             |
// ownership boundary                                                                                          |
//   This memory object stores only computed irradiance values. It stores no solar table, scene, instrument    |
//   response, or wavelength sampling controls.                                                                |
// ------------------------------------------------------------------------------------------------------------|

// SolarIrradianceMemory ------------------------------------------------------------------------------------- |
// Exact-wavelength solar irradiance hash map retained across product runs.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB) Debug, 32 B (0.031 KiB) optimized, align: 8 B                                        |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..39] values : std.AutoHashMap(u64, f64) in Debug                                                        |
// [ 0..31] values : std.AutoHashMap(u64, f64) in optimized builds                                             |
//                                                                                                             |
// owned storage                                                                                               |
//   values owns hash-map backing storage and is released by deinit.                                           |
pub const SolarIrradianceMemory = struct {
    values: std.AutoHashMap(u64, f64),

    pub fn init(allocator: Allocator) SolarIrradianceMemory {
        // SolarIrradianceMemory.init ------------------------------------------------------------------------ |
        // Create an empty exact-wavelength irradiance map; allocation is delayed until reserve or insert.     |
        // ----------------------------------------------------------------------------------------------------|
        return .{
            .values = std.AutoHashMap(u64, f64).init(allocator),
        };
    }

    pub fn reset(self: *SolarIrradianceMemory) void {
        // SolarIrradianceMemory.reset ----------------------------------------------------------------------- |
        // Clear values between product simulations while retaining hash-map capacity.                         |
        // ----------------------------------------------------------------------------------------------------|
        self.values.clearRetainingCapacity();
    }

    pub fn reserve(self: *SolarIrradianceMemory, count: usize) Allocator.Error!void {
        // SolarIrradianceMemory.reserve --------------------------------------------------------------------- |
        // Reserve expected irradiance support rows before hot integration inserts exact-wavelength values.    |
        // ----------------------------------------------------------------------------------------------------|
        try self.values.ensureTotalCapacity(@intCast(count));
    }

    pub fn get(self: *const SolarIrradianceMemory, wavelength_nm: f64) ?f64 {
        // SolarIrradianceMemory.get ------------------------------------------------------------------------- |
        // Read a cached irradiance value by exact wavelength bits.                                            |
        // ----------------------------------------------------------------------------------------------------|
        return self.values.get(keyFor(wavelength_nm));
    }

    pub fn put(self: *SolarIrradianceMemory, wavelength_nm: f64, irradiance: f64) Allocator.Error!void {
        // SolarIrradianceMemory.put ------------------------------------------------------------------------- |
        // Insert or replace one exact-wavelength irradiance value, growing the map when needed.               |
        // ----------------------------------------------------------------------------------------------------|
        try self.values.put(keyFor(wavelength_nm), irradiance);
    }

    pub fn putAssumeCapacity(self: *SolarIrradianceMemory, wavelength_nm: f64, irradiance: f64) void {
        // SolarIrradianceMemory.putAssumeCapacity ----------------------------------------------------------- |
        // Insert or replace one value after reserve has sized the map for the active irradiance workload.     |
        // ----------------------------------------------------------------------------------------------------|
        self.values.putAssumeCapacity(keyFor(wavelength_nm), irradiance);
    }

    pub fn deinit(self: *SolarIrradianceMemory) void {
        // SolarIrradianceMemory.deinit ---------------------------------------------------------------------- |
        // Release hash-map backing storage and mark this memory object unusable.                              |
        // ----------------------------------------------------------------------------------------------------|
        self.values.deinit();
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn keyFor(wavelength_nm: f64) u64 {
    // keyFor -------------------------------------------------------------------------------------------------|
    // Return the exact f64 bit pattern used as the solar irradiance memory key.                               |
    // --------------------------------------------------------------------------------------------------------|
    return @as(u64, @bitCast(wavelength_nm));
}

comptime {
    const expected_size: usize = if (builtin.mode == .Debug) 40 else 32;
    std.debug.assert(@sizeOf(SolarIrradianceMemory) == expected_size);
}
