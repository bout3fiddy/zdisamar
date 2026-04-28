const std = @import("std");
const errors = @import("../common/errors.zig");
const LutControls = @import("../common/lut_controls.zig");
const Allocator = std.mem.Allocator;

pub const Atmosphere = @import("Atmosphere.zig").Atmosphere;
pub const Binding = @import("Binding.zig").Binding;
pub const BindingKind = @import("Binding.zig").BindingKind;
pub const Geometry = @import("Geometry.zig").Geometry;
pub const GeometryModel = @import("Geometry.zig").Model;
pub const SpectralGrid = @import("Spectrum.zig").SpectralGrid;
pub const SpectralWindow = @import("Bands.zig").SpectralWindow;
pub const SpectralBand = @import("Bands.zig").SpectralBand;
pub const SpectralBandSet = @import("Bands.zig").SpectralBandSet;
pub const Absorber = @import("Absorber.zig").Absorber;
pub const AbsorberSet = @import("Absorber.zig").AbsorberSet;
pub const Spectroscopy = @import("Absorber.zig").Spectroscopy;
pub const SpectroscopyMode = @import("Absorber.zig").SpectroscopyMode;
pub const Surface = @import("Surface.zig").Surface;
pub const Cloud = @import("Cloud.zig").Cloud;
pub const Aerosol = @import("Aerosol.zig").Aerosol;
pub const Instrument = @import("Instrument.zig").Instrument;
pub const ObservationModel = @import("ObservationModel.zig").ObservationModel;
pub const ObservationRegime = @import("ObservationModel.zig").ObservationRegime;
pub const StateVector = @import("StateVector.zig").StateVector;
pub const StateParameter = @import("StateVector.zig").Parameter;
pub const StateTarget = @import("StateVector.zig").Target;
pub const StateBounds = @import("StateVector.zig").Bounds;
pub const StatePrior = @import("StateVector.zig").Prior;
pub const StateTransform = @import("StateVector.zig").Transform;
pub const Measurement = @import("Measurement.zig").Measurement;
pub const MeasurementVector = @import("Measurement.zig").MeasurementVector;
pub const MeasurementMask = @import("Measurement.zig").SpectralMask;
pub const MeasurementErrorModel = @import("Measurement.zig").ErrorModel;
pub const InverseProblem = @import("InverseProblem.zig").InverseProblem;
pub const CovarianceBlock = @import("InverseProblem.zig").CovarianceBlock;
pub const FitControls = @import("InverseProblem.zig").FitControls;
pub const Convergence = @import("InverseProblem.zig").Convergence;
pub const DerivativeMode = @import("InverseProblem.zig").DerivativeMode;

pub const Scene = struct {
    id: []const u8 = "scene-0",
    atmosphere: Atmosphere = .{},
    geometry: Geometry = .{},
    spectral_grid: SpectralGrid = .{},
    bands: SpectralBandSet = .{},
    absorbers: AbsorberSet = .{},
    surface: Surface = .{},
    cloud: Cloud = .{},
    aerosol: Aerosol = .{},
    observation_model: ObservationModel = .{},
    lut_controls: LutControls.Controls = .{},

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
        try self.cloud.validate();
        try self.aerosol.validate();
        try self.observation_model.validate();
        try self.lut_controls.validate();
        try self.observation_model.cross_section_fit.validateForBandCount(self.bands.items.len);
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
            // INVARIANT:
            //   Explicit measured channels and the scene spectral grid must describe the same
            //   sample count once the scene is ready for execution.
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

    pub fn deinitOwned(self: *Scene, allocator: Allocator) void {
        self.atmosphere.deinitOwned(allocator);
        self.surface.deinitOwned(allocator);
        self.cloud.deinitOwned(allocator);
        self.aerosol.deinitOwned(allocator);
        self.bands.deinitOwned(allocator);
        self.absorbers.deinitOwned(allocator);
        self.observation_model.deinitOwned(allocator);
    }
};
