const std = @import("std");
const errors = @import("../common/errors.zig");
const LutControls = @import("../common/lut_controls.zig");
const Allocator = std.mem.Allocator;
const AbsorberModel = @import("Absorber.zig");

// Scene.zig --------------------------------------------------------------------------------------------------|
// Public typed request boundary for one forward-model run and the stable zdisamar.Input type.                 |
//                                                                                                             |
// used by                                                                                                     |
//   root.zig exposes Scene as the public Input API                                                            |
//   o2a_reference/run.zig builds owned O2 A scenes from parsed vendor/control data                            |
//   optical_properties/state_build/context.zig validates Scene before optical preparation                     |
//   instrument_grid/grid_calculation/simulate.zig reads Scene as the product-grid request                     |
//   bundled reference-data workflows derive LUT selection and generated-asset compatibility from it           |
//                                                                                                             |
// main paths                                                                                                  |
//   validate -> nested row validation, band-support count checks, measured-wavelength/grid agreement          |
//   lutCompatibilityKey -> geometry + nominal grid + instrument support + active spectroscopy controls        |
//   lutNominalWavelengthBounds / lutLowResolutionSamplingIdentity -> effective nominal grid for LUT keys      |
//   deinitOwned -> release only nested storage with explicit ownership in child rows                          |
//                                                                                                             |
// boundary rules                                                                                              |
//   Scene carries typed inputs only. Forward-model code may read it, but parsing, file I/O, and generated     |
//   asset loading stay in input/reference-data layers. No nested control should be silently ignored: validate |
//   accepts it, rejects it, or key-building includes the controls that affect generated LUT compatibility.    |
//                                                                                                             |
// layout                                                                                                      |
//   Scene is a 672 B value row with nested owner/view headers. The row itself does not own referenced storage |
//   by default; ownership flags live in child structs such as bands, absorbers, aerosol, observation_model,   |
//   interval grids, and operational support rows.                                                             |
//                                                                                                             |
// hot path                                                                                                    |
//   Scene is passed by pointer through preparation and product simulation. Cache-key hashing scans absorber   |
//   controls during setup; wavelength-time RTM and instrument loops should consume prepared state instead of  |
//   repeatedly interpreting this public input row.                                                            |
// ------------------------------------------------------------------------------------------------------------|

pub const Atmosphere = @import("Atmosphere.zig").Atmosphere;
pub const Binding = @import("Binding.zig").Binding;
pub const BindingKind = @import("Binding.zig").BindingKind;
pub const Geometry = @import("Geometry.zig").Geometry;
pub const GeometryModel = @import("Geometry.zig").Model;
pub const SpectralGrid = @import("Spectrum.zig").SpectralGrid;
pub const SpectralWindow = @import("Bands.zig").SpectralWindow;
pub const SpectralBand = @import("Bands.zig").SpectralBand;
pub const SpectralBandSet = @import("Bands.zig").SpectralBandSet;
pub const Absorber = AbsorberModel.Absorber;
pub const AbsorberSet = AbsorberModel.AbsorberSet;
pub const Spectroscopy = AbsorberModel.Spectroscopy;
pub const SpectroscopyMode = AbsorberModel.SpectroscopyMode;
pub const Surface = @import("Surface.zig").Surface;
pub const Aerosol = @import("Aerosol.zig").Aerosol;
pub const Instrument = @import("Instrument.zig").Instrument;
pub const ObservationModel = @import("ObservationModel.zig").ObservationModel;
pub const ObservationRegime = @import("ObservationModel.zig").ObservationRegime;
pub const Measurement = @import("Measurement.zig").Measurement;
pub const MeasurementVector = @import("Measurement.zig").MeasurementVector;
pub const MeasurementMask = @import("Measurement.zig").SpectralMask;
pub const MeasurementErrorModel = @import("Measurement.zig").ErrorModel;

pub const DerivativeMode = enum {
    none,
    semi_analytical,
};

// Scene ------------------------------------------------------------------------------------------------------|
// Complete user-facing forward-model request.                                                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 672 B (0.656 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] id                                  : []const u8                                                 |
// [ 16..111] atmosphere                          : Atmosphere                                                 |
// [112..151] geometry                            : Geometry                                                   |
// [152..175] spectral_grid                       : SpectralGrid                                               |
// [176..191] bands                               : SpectralBandSet                                            |
// [192..207] absorbers                           : AbsorberSet                                                |
// [208..223] surface                             : Surface                                                    |
// [224..391] aerosol                             : Aerosol                                                    |
// [392..607] observation_model                   : ObservationModel                                           |
// [608..663] lut_controls                        : LutControls.Controls                                       |
// [664..671] phase_function_truncation_threshold : f64                                                        |
//                                                                                                             |
// referenced storage                                                                                          |
//   id and nested slice headers point at caller-owned or prepared data.                                       |
//   Referenced storage is not in this row.                                                                    |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 11 cache lines at 64 B per line                                                                 |
// footprint: per instance = 672 B (0.656 KiB); total also includes referenced nested storage                  |
pub const Scene = struct {
    id: []const u8 = "scene-0",
    atmosphere: Atmosphere = .{},
    geometry: Geometry = .{},
    spectral_grid: SpectralGrid = .{},
    bands: SpectralBandSet = .{},
    absorbers: AbsorberSet = .{},
    surface: Surface = .{},
    aerosol: Aerosol = .{},
    observation_model: ObservationModel = .{},
    lut_controls: LutControls.Controls = .{},
    phase_function_truncation_threshold: f64 = 1.0e-8,

    pub fn validate(self: *const Scene) errors.Error!void {
        if (self.id.len == 0) {
            return errors.Error.MissingScene;
        }

        try self.atmosphere.validate();
        try self.geometry.validate();
        try self.spectral_grid.validate();
        try self.bands.validate();
        try self.absorbers.validate();
        try self.surface.validate();
        try self.aerosol.validate();
        try self.observation_model.validate();
        try self.lut_controls.validate();
        if (!std.math.isFinite(self.phase_function_truncation_threshold) or
            self.phase_function_truncation_threshold <= 0.0)
        {
            return errors.Error.InvalidRequest;
        }
        const explicit_operational_band_count = self.observation_model.operational_band_support.len;
        if (self.bands.items.len != 0 and
            explicit_operational_band_count != 0 and
            explicit_operational_band_count != self.bands.items.len)
        {
            return errors.Error.InvalidRequest;
        }
        if (self.observation_model.measured_wavelengths_nm.len != 0 and
            self.observation_model.measured_wavelengths_nm.len != @as(usize, self.spectral_grid.sample_count))
        {

            // Explicit measured channels and the scene spectral grid must describe the same sample count before
            // instrument-grid execution.
            return errors.Error.InvalidRequest;
        }
    }

    pub fn lutCompatibilityKey(self: *const Scene) LutControls.CompatibilityKey {
        const support = self.observation_model.primaryOperationalBandSupport();
        const nominal_bounds = self.lutNominalWavelengthBounds();
        const low_resolution_sampling = self.lutLowResolutionSamplingIdentity();
        return .{
            .controls = self.lut_controls,
            .spectral_start_nm = nominal_bounds.start_nm,
            .spectral_end_nm = nominal_bounds.end_nm,
            .nominal_sample_count = low_resolution_sampling.sample_count,
            .nominal_wavelength_hash = low_resolution_sampling.wavelength_hash,
            .solar_zenith_deg = self.geometry.solar_zenith_deg,
            .viewing_zenith_deg = self.geometry.viewing_zenith_deg,
            .relative_azimuth_deg = self.geometry.relative_azimuth_deg,
            .surface_albedo = self.surface.albedo,
            .instrument_line_fwhm_nm = self.observation_model.instrument_line_fwhm_nm,
            .high_resolution_step_nm = support.high_resolution_step_nm,
            .high_resolution_half_span_nm = support.high_resolution_half_span_nm,
            .lut_sampling_half_span_nm = self.observation_model.lutSamplingHalfSpanNm(),
            .spectroscopy_source_hash = self.lutSpectroscopySourceHash(),
        };
    }

    pub fn lutNominalWavelengthBounds(self: *const Scene) struct { start_nm: f64, end_nm: f64 } {
        const nominal_wavelengths = self.observation_model.measured_wavelengths_nm;
        if (nominal_wavelengths.len != 0) {
            return .{
                .start_nm = nominal_wavelengths[0],
                .end_nm = nominal_wavelengths[nominal_wavelengths.len - 1],
            };
        }
        return .{
            .start_nm = self.spectral_grid.start_nm,
            .end_nm = self.spectral_grid.end_nm,
        };
    }

    pub fn usesHighResolutionLutSampling(self: *const Scene) bool {
        const support = self.observation_model.primaryOperationalBandSupport();
        return support.high_resolution_step_nm > 0.0 and
            self.observation_model.lutSamplingHalfSpanNm() > 0.0;
    }

    fn lutLowResolutionSamplingIdentity(self: *const Scene) struct {
        sample_count: u32,
        wavelength_hash: u64,
    } {
        if (self.usesHighResolutionLutSampling()) {
            return .{
                .sample_count = 0,
                .wavelength_hash = 0,
            };
        }

        const nominal_wavelengths = self.observation_model.measured_wavelengths_nm;
        if (nominal_wavelengths.len != 0) {
            return .{
                .sample_count = @intCast(nominal_wavelengths.len),
                .wavelength_hash = hashWavelengths(nominal_wavelengths),
            };
        }

        return .{
            .sample_count = self.spectral_grid.sample_count,
            .wavelength_hash = 0,
        };
    }

    fn hashWavelengths(wavelengths_nm: []const f64) u64 {
        var hasher = std.hash.Wyhash.init(0);
        for (wavelengths_nm) |wavelength_nm| {
            hasher.update(std.mem.asBytes(&wavelength_nm));
        }
        return hasher.final();
    }

    fn lutSpectroscopySourceHash(self: *const Scene) u64 {
        var hasher = std.hash.Wyhash.init(0x6c75_742d_7370_6563);
        for (self.absorbers.items) |absorber| {
            hashBytes(&hasher, absorber.id);
            hashBytes(&hasher, absorber.species);
            hashEnum(&hasher, absorber.spectroscopy.mode);
            hashBinding(&hasher, absorber.spectroscopy.line_list);
            hashBinding(&hasher, absorber.spectroscopy.line_mixing);
            hashBinding(&hasher, absorber.spectroscopy.strong_lines);
            hashBinding(&hasher, absorber.spectroscopy.cia_table);
            hashBinding(&hasher, absorber.spectroscopy.cross_section_table);
            hashBinding(&hasher, absorber.spectroscopy.operational_lut);
            if (absorber.spectroscopy.mode == .line_by_line) {
                hashActiveLineControls(&hasher, absorber.spectroscopy.line_gas_controls);
            }
        }
        return hasher.final();
    }

    fn hashBinding(hasher: *std.hash.Wyhash, binding: Binding) void {
        hashEnum(hasher, binding.kind());
        hashBytes(hasher, binding.name());
    }

    fn hashActiveLineControls(
        hasher: *std.hash.Wyhash,
        controls: AbsorberModel.LineGasControls,
    ) void {
        const active_controls = controls.active();
        hashEnum(hasher, controls.active_stage);
        hashBytes(hasher, active_controls.isotopes);
        hashFloat(hasher, active_controls.line_mixing_factor);
        hashOptionalFloat(hasher, active_controls.threshold_line);
        hashOptionalFloat(hasher, active_controls.cutoff_cm1);
    }

    fn hashEnum(hasher: *std.hash.Wyhash, value: anytype) void {
        const tag_value: u16 = @intFromEnum(value);
        hasher.update(std.mem.asBytes(&tag_value));
    }

    fn hashBytes(hasher: *std.hash.Wyhash, value: []const u8) void {
        const length: u64 = value.len;
        hasher.update(std.mem.asBytes(&length));
        hasher.update(value);
    }

    fn hashFloat(hasher: *std.hash.Wyhash, value: f64) void {
        hasher.update(std.mem.asBytes(&value));
    }

    fn hashOptionalFloat(hasher: *std.hash.Wyhash, value: ?f64) void {
        const has_value = value != null;
        hasher.update(std.mem.asBytes(&has_value));
        if (value) |resolved| hashFloat(hasher, resolved);
    }

    pub fn deinitOwned(self: *Scene, allocator: Allocator) void {
        self.atmosphere.deinitOwned(allocator);
        self.aerosol.deinitOwned(allocator);
        self.bands.deinitOwned(allocator);
        self.absorbers.deinitOwned(allocator);
        self.observation_model.deinitOwned(allocator);
    }
};
// ------------------------------------------------------------------------------------------------------------|
