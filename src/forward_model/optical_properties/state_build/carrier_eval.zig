const std = @import("std");
const ReferenceData = @import("../../../input/ReferenceData.zig");
const Rayleigh = @import("../../../input/reference/rayleigh.zig");
const ParticleProfiles = @import("../shared/particle_profiles.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const State = @import("state.zig");
const Scalar = @import("state_scalar.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");
const transport_common = @import("../../radiative_transfer/root.zig");

const PreparedSublayer = State.PreparedSublayer;
const SharedRtmLevelGeometry = State.SharedRtmLevelGeometry;

const centimeters_per_kilometer = 1.0e5;

// carrier_eval.zig ------------------------------------------------------------------------------------------- |
// Wavelength-local carrier evaluation for prepared optical rows.                                               |
//                                                                                                              |
// called by                                                                                                    |
//   forward_input.zig through forward_layers, shared_carrier, source_interfaces, rtm_quadrature,               |
//   pseudo_spherical, and direct optical-depth helpers.                                                        |
//                                                                                                              |
// main paths                                                                                                   |
//   support row       -> gas absorption/scattering, CIA, aerosol depth, and cached scalar carrier rows         |
//   shared RTM level  -> boundary/active carriers with above/below particle scattering and phase rows          |
//   arbitrary altitude -> interpolated thermodynamic/particle state for pseudo-spherical and source routes     |
//   carrier-cache path -> reuse per-wavelength scalar rows after WavelengthCarrierCache.init                   |
//   direct path        -> evaluate the same rows with only a profile spectroscopy cache                        |
//                                                                                                              |
// hot path                                                                                                     |
//   Runs for each high-resolution wavelength sample. WavelengthCarrierCache precomputes continuum sigma, CIA   |
//   coefficients, Rayleigh cross section/P2, and aerosol wavelength scales, then tags support-row scalar rows  |
//   with an epoch so forward-layer, boundary, source-interface, and quadrature passes do not recompute the     |
//   same gas/CIA/Rayleigh/aerosol scalars.                                                                     |
//                                                                                                              |
// math                                                                                                         |
//   k_abs_gas = sigma_cont*n_cont*1e5 + sigma_line*n_line*1e5 + sigma_xs*n_xs*1e5                              |
//   k_sca_gas = sigma_R*n_air*1e5                                                                              |
//   k_cia     = sigma_cia*n_pair*1e5                                                                           |
//   aerosol optical depth is Angstrom-scaled at wavelength time, after layer_accumulation has placed the       |
//   reference-wavelength particle depth on the support grid.                                                   |
//                                                                                                              |
// memory                                                                                                       |
//   SharedOpticalScalars and SharedOpticalCarrier are compact 40 B value rows. SupportRowScalarCache owns one  |
//   epoch byte and one scalar row per support row in worker scratch. WavelengthCarrierCache borrows those      |
//   arrays plus the profile spectroscopy cache for one wavelength and owns no out-of-line storage.             |
// ------------------------------------------------------------------------------------------------------------ |

// SharedOpticalScalars --------------------------------------------------------------------------------------- |
// Per-kilometer optical-depth scalar row used by support-row caches and scalar-only callers.                   |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 40 B (0.039 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] gas_absorption_optical_depth_per_km        : f64                                                    |
// [ 8..15] gas_scattering_optical_depth_per_km        : f64                                                    |
// [16..23] cia_optical_depth_per_km                   : f64                                                    |
// [24..31] aerosol_optical_depth_per_km               : f64                                                    |
// [32..39] aerosol_scattering_optical_depth_per_km    : f64                                                    |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// cache span: 1 cache line at 64 B per line                                                                    |
// footprint: per instance = 40 B; total = per instance * live row count                                        |
pub const SharedOpticalScalars = struct {
    gas_absorption_optical_depth_per_km: f64 = 0.0,
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    cia_optical_depth_per_km: f64 = 0.0,
    aerosol_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,

    pub fn totalScatteringOpticalDepthPerKm(self: SharedOpticalScalars) f64 {
        return self.gas_scattering_optical_depth_per_km +
            self.aerosol_scattering_optical_depth_per_km;
    }

    pub fn totalOpticalDepthPerKm(self: SharedOpticalScalars) f64 {
        return self.gas_absorption_optical_depth_per_km +
            self.gas_scattering_optical_depth_per_km +
            self.cia_optical_depth_per_km +
            self.aerosol_optical_depth_per_km;
    }
};
// ------------------------------------------------------------------------------------------------------------ |

// SharedOpticalCarrier --------------------------------------------------------------------------------------- |
// Public carrier row for gas, CIA, and aerosol optical-depth terms at one support or altitude sample.          |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 40 B (0.039 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] gas_absorption_optical_depth_per_km        : f64                                                    |
// [ 8..15] gas_scattering_optical_depth_per_km        : f64                                                    |
// [16..23] cia_optical_depth_per_km                   : f64                                                    |
// [24..31] aerosol_optical_depth_per_km               : f64                                                    |
// [32..39] aerosol_scattering_optical_depth_per_km    : f64                                                    |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// cache span: 1 cache line at 64 B per line                                                                    |
// footprint: per instance = 40 B; total = per instance * live row count                                        |
pub const SharedOpticalCarrier = struct {
    gas_absorption_optical_depth_per_km: f64 = 0.0,
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    cia_optical_depth_per_km: f64 = 0.0,
    aerosol_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,

    pub fn totalScatteringOpticalDepthPerKm(self: SharedOpticalCarrier) f64 {
        return self.scalars().totalScatteringOpticalDepthPerKm();
    }

    pub fn totalOpticalDepthPerKm(self: SharedOpticalCarrier) f64 {
        return self.scalars().totalOpticalDepthPerKm();
    }

    pub fn scalars(self: SharedOpticalCarrier) SharedOpticalScalars {
        return .{
            .gas_absorption_optical_depth_per_km = self.gas_absorption_optical_depth_per_km,
            .gas_scattering_optical_depth_per_km = self.gas_scattering_optical_depth_per_km,
            .cia_optical_depth_per_km = self.cia_optical_depth_per_km,
            .aerosol_optical_depth_per_km = self.aerosol_optical_depth_per_km,
            .aerosol_scattering_optical_depth_per_km = self.aerosol_scattering_optical_depth_per_km,
        };
    }
};
// ------------------------------------------------------------------------------------------------------------ |

// SupportRowScalarCache -------------------------------------------------------------------------------------- |
// Owns dense support-row cache storage for one worker scratch.                                                 |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 40 B (0.039 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0..15] epochs  : []u8                                                                                      |
// [16..31] scalars : []SharedOpticalScalars                                                                    |
// [32..32] epoch   : u8                                                                                        |
// [33..39] padding : 7 B                                                                                       |
//                                                                                                              |
// out-of-line                                                                                                  |
//   epochs  : owned, one epoch byte per support row                                                            |
//   scalars : owned, one 40 B scalar row per support row                                                       |
//                                                                                                              |
// hot path                                                                                                     |
//   nextEpoch advances the wavelength tag without clearing the arrays. Only wraparound clears epochs.          |
//                                                                                                              |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                     |
// cache span: 1 cache line at 64 B per line                                                                    |
// footprint: per instance = 40 B plus owned row storage                                                        |
pub const SupportRowScalarCache = struct {
    epochs: []u8,
    scalars: []SharedOpticalScalars,
    epoch: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, row_count: usize) !SupportRowScalarCache {
        const epochs = try allocator.alloc(u8, row_count);
        errdefer allocator.free(epochs);
        @memset(epochs, 0);
        const scalars = try allocator.alloc(SharedOpticalScalars, row_count);
        errdefer allocator.free(scalars);
        return .{
            .epochs = epochs,
            .scalars = scalars,
        };
    }

    pub fn deinit(self: *SupportRowScalarCache, allocator: std.mem.Allocator) void {
        allocator.free(self.epochs);
        allocator.free(self.scalars);
        self.* = undefined;
    }

    fn nextEpoch(self: *SupportRowScalarCache) u8 {
        if (self.epoch == std.math.maxInt(u8)) {
            @memset(self.epochs, 0);
            self.epoch = 1;
            return self.epoch;
        }
        self.epoch += 1;
        return self.epoch;
    }
};
// ------------------------------------------------------------------------------------------------------------ |

// WavelengthCarrierCache ------------------------------------------------------------------------------------- |
// Wavelength-local constants plus epoch-tagged support-row scalar cache descriptors.                           |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 136 B (0.133 KiB), align: 8 B                                                                          |
//                                                                                                              |
// memory                                                                                                       |
// [  0..  7] profile_cache                 : *const ProfileNodeSpectroscopyCache                               |
// [  8.. 23] support_row_epochs            : []u8                                                              |
// [ 24.. 39] support_row_scalars           : []SharedOpticalScalars                                            |
// [ 40.. 47] continuum_sigma               : f64                                                               |
// [ 48.. 87] cia_coefficients              : ?CiaWavelengthCoefficients                                        |
// [ 88.. 95] rayleigh_cross_section_cm2    : f64                                                               |
// [ 96..103] rayleigh_phase_coefficient2   : f64                                                               |
// [104..127] particle_scales               : ParticleWavelengthScales                                          |
// [128..128] support_row_epoch             : u8                                                                |
// [129..135] padding                       : 7 B                                                               |
//                                                                                                              |
// out-of-line                                                                                                  |
//   profile_cache       : borrowed from the wavelength caller                                                  |
//   support_row_epochs  : borrowed from SupportRowScalarCache                                                  |
//   support_row_scalars : borrowed from SupportRowScalarCache                                                  |
//                                                                                                              |
// hot path                                                                                                     |
//   cachedSupportRowScalarsRef returns a cached scalar row when the epoch matches. On a miss it fills one      |
//   scalar row and tags that row for the current wavelength.                                                   |
//                                                                                                              |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                     |
// cache span: 3 cache lines at 64 B per line                                                                   |
// footprint: per instance = 136 B plus borrowed row storage                                                    |
pub const WavelengthCarrierCache = struct {
    profile_cache: *const SpectroscopyState.ProfileNodeSpectroscopyCache,
    support_row_epochs: []u8,
    support_row_scalars: []SharedOpticalScalars,
    support_row_epoch: u8,
    continuum_sigma: f64,
    cia_coefficients: ?CiaWavelengthCoefficients,
    rayleigh_cross_section_cm2: f64,
    rayleigh_phase_coefficient2: f64,
    particle_scales: ParticleWavelengthScales,

    pub fn init(
        prepared: *const State.PreparedOpticalState,
        wavelength_nm: f64,
        support_row_cache: *SupportRowScalarCache,
        profile_cache: *const SpectroscopyState.ProfileNodeSpectroscopyCache,
    ) WavelengthCarrierCache {
        const epoch = support_row_cache.nextEpoch();
        return .{
            .profile_cache = profile_cache,
            .support_row_epochs = support_row_cache.epochs,
            .support_row_scalars = support_row_cache.scalars,
            .support_row_epoch = epoch,
            .continuum_sigma = continuumSigmaAtWavelength(prepared, wavelength_nm),
            .cia_coefficients = CiaWavelengthCoefficients.init(prepared, wavelength_nm),
            .rayleigh_cross_section_cm2 = Rayleigh.crossSectionCm2(wavelength_nm),
            .rayleigh_phase_coefficient2 = PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm),
            .particle_scales = ParticleWavelengthScales.init(prepared, wavelength_nm),
        };
    }

    fn cachedSupportRow(
        self: *WavelengthCarrierCache,
        prepared: *const State.PreparedOpticalState,
        wavelength_nm: f64,
        sublayer: PreparedSublayer,
        global_sublayer_index: usize,
        strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    ) SharedOpticalCarrier {
        var fallback: SharedOpticalScalars = undefined;
        const scalars = self.cachedSupportRowScalarsRef(
            prepared,
            wavelength_nm,
            sublayer,
            global_sublayer_index,
            strong_line_state,
            &fallback,
        );
        return sharedOpticalCarrierFromScalars(scalars.*);
    }

    pub fn cachedSupportRowScalarsRef(
        self: *WavelengthCarrierCache,
        prepared: *const State.PreparedOpticalState,
        wavelength_nm: f64,
        sublayer: PreparedSublayer,
        global_sublayer_index: usize,
        strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
        fallback: *SharedOpticalScalars,
    ) *const SharedOpticalScalars {
        if (global_sublayer_index >= self.support_row_epochs.len or
            global_sublayer_index >= self.support_row_scalars.len)
        {
            fallback.* = sharedOpticalScalarsAtSupportRowWithSpectroscopyCache(
                prepared,
                wavelength_nm,
                sublayer,
                global_sublayer_index,
                strong_line_state,
                self.profile_cache,
            );
            return fallback;
        }
        if (self.support_row_epochs[global_sublayer_index] != self.support_row_epoch) {
            fillSharedOpticalScalarsAtSupportRowWithScalarCache(
                &self.support_row_scalars[global_sublayer_index],
                prepared,
                wavelength_nm,
                sublayer,
                global_sublayer_index,
                strong_line_state,
                self.profile_cache,
                self.continuum_sigma,
                self.cia_coefficients,
                self.rayleigh_cross_section_cm2,
                self.particle_scales,
            );
            self.support_row_epochs[global_sublayer_index] = self.support_row_epoch;
        }
        return &self.support_row_scalars[global_sublayer_index];
    }
};
// ------------------------------------------------------------------------------------------------------------ |

// CiaWavelengthCoefficients ---------------------------------------------------------------------------------- |
// Interpolated O2-O2 CIA polynomial coefficients for one wavelength.                                           |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 32 B (0.031 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] scale_factor_cm5_per_molecule2 : f64                                                                |
// [ 8..15] a0                              : f64                                                               |
// [16..23] a1                              : f64                                                               |
// [24..31] a2                              : f64                                                               |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// footprint: per instance = 32 B; embedded in WavelengthCarrierCache when CIA is available                     |
const CiaWavelengthCoefficients = struct {
    scale_factor_cm5_per_molecule2: f64,
    a0: f64,
    a1: f64,
    a2: f64,

    fn init(
        prepared: *const State.PreparedOpticalState,
        wavelength_nm: f64,
    ) ?CiaWavelengthCoefficients {
        if (prepared.operational_o2o2_lut.enabled()) return null;
        const table = prepared.collision_induced_absorption orelse return null;
        const coefficients = table.interpolateCoefficients(wavelength_nm);
        return .{
            .scale_factor_cm5_per_molecule2 = table.scale_factor_cm5_per_molecule2,
            .a0 = coefficients.a0,
            .a1 = coefficients.a1,
            .a2 = coefficients.a2,
        };
    }

    fn sigmaAtTemperature(self: CiaWavelengthCoefficients, temperature_k: f64) f64 {
        const temperature_c = temperature_k - 273.15;
        const raw_sigma = self.a0 +
            self.a1 * temperature_c +
            self.a2 * temperature_c * temperature_c;
        return self.scale_factor_cm5_per_molecule2 * @max(raw_sigma, 0.0);
    }
};
// ------------------------------------------------------------------------------------------------------------ |

// PreparedQuadratureCarrier ---------------------------------------------------------------------------------- |
// Scattering-only carrier row used when RTM quadrature does not need absorption fields.                        |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 24 B (0.023 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] ksca                                      : f64                                                     |
// [ 8..15] gas_scattering_optical_depth_per_km       : f64                                                     |
// [16..23] aerosol_scattering_optical_depth_per_km   : f64                                                     |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// cache span: 1 cache line at 64 B per line                                                                    |
// footprint: per instance = 24 B; total = per instance * live row count                                        |
pub const PreparedQuadratureCarrier = struct {
    ksca: f64,
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------ |

// SharedBoundaryCarrier -------------------------------------------------------------------------------------- |
// Boundary-level scattering and phase-row carrier for shared RTM interfaces.                                   |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 96 B (0.094 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] gas_scattering_optical_depth_per_km                : f64                                            |
// [ 8..15] particle_scattering_optical_depth_above_per_km     : f64                                            |
// [16..23] particle_scattering_optical_depth_below_per_km     : f64                                            |
// [24..31] aerosol_scattering_optical_depth_above_per_km      : f64                                            |
// [32..39] aerosol_scattering_optical_depth_below_per_km      : f64                                            |
// [40..47] ksca_above                                        : f64                                             |
// [48..55] ksca_below                                        : f64                                             |
// [56..79] phase_above                                       : PhaseMixture                                    |
// [80..87] phase_max_index_above                             : usize                                           |
// [88..95] phase_max_index_below                             : usize                                           |
//                                                                                                              |
// out-of-line                                                                                                  |
//   phase_above may reference shared aerosol phase coefficient rows; referenced storage is not included.       |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// cache span: 2 cache lines at 64 B per line                                                                   |
// footprint: per instance = 96 B plus referenced phase storage                                                 |
pub const SharedBoundaryCarrier = struct {
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    particle_scattering_optical_depth_above_per_km: f64 = 0.0,
    particle_scattering_optical_depth_below_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_above_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_below_per_km: f64 = 0.0,
    ksca_above: f64 = 0.0,
    ksca_below: f64 = 0.0,
    phase_above: PhaseFunctions.PhaseMixture = .{},
    phase_max_index_above: usize = 0,
    phase_max_index_below: usize = 0,
};
// ------------------------------------------------------------------------------------------------------------ |

// ParticleBoundaryCarrier ------------------------------------------------------------------------------------ |
// Aerosol-only boundary carrier used before gas and particle scattering are mixed.                             |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 16 B (0.016 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] aerosol_optical_depth_per_km             : f64                                                      |
// [ 8..15] aerosol_scattering_optical_depth_per_km  : f64                                                      |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// cache span: 1 cache line at 64 B per line                                                                    |
// footprint: per instance = 16 B; total = per instance * live row count                                        |
const ParticleBoundaryCarrier = struct {
    aerosol_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,

    fn totalScatteringOpticalDepthPerKm(self: ParticleBoundaryCarrier) f64 {
        return self.aerosol_scattering_optical_depth_per_km;
    }
};
// ------------------------------------------------------------------------------------------------------------ |

// ParticleWavelengthScales ----------------------------------------------------------------------------------- |
// Wavelength and aerosol Angstrom-scale controls reused while filling rows for one wavelength.                 |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 24 B (0.023 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] aerosol                     : f64                                                                   |
// [ 8..15] wavelength_nm               : f64                                                                   |
// [16..16] profile_sublayer_properties : bool                                                                  |
// [17..23] padding                     : 7 B                                                                   |
//                                                                                                              |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                     |
// cache span: 1 cache line at 64 B per line                                                                    |
// footprint: per instance = 24 B; embedded in WavelengthCarrierCache and stack values                          |
const ParticleWavelengthScales = struct {
    aerosol: f64,
    wavelength_nm: f64,
    profile_sublayer_properties: bool,

    fn init(
        prepared: *const State.PreparedOpticalState,
        wavelength_nm: f64,
    ) ParticleWavelengthScales {
        return .{
            .aerosol = particleWavelengthScale(
                prepared.aerosol_reference_wavelength_nm,
                prepared.aerosol_angstrom_exponent,
                wavelength_nm,
            ),
            .wavelength_nm = wavelength_nm,
            .profile_sublayer_properties = prepared.has_aerosol_profile_properties,
        };
    }

    fn aerosolScale(self: ParticleWavelengthScales, sublayer: PreparedSublayer) f64 {
        if (!self.profile_sublayer_properties) return self.aerosol;
        return particleWavelengthScale(
            sublayer.aerosol_reference_wavelength_nm,
            sublayer.aerosol_angstrom_exponent,
            self.wavelength_nm,
        );
    }
};
// ------------------------------------------------------------------------------------------------------------ |

// InterpolatedQuadratureState -------------------------------------------------------------------------------- |
// Thermodynamic and particle state at an arbitrary altitude between prepared support rows.                     |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 80 B (0.078 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] pressure_hpa                    : f64                                                               |
// [ 8..15] temperature_k                   : f64                                                               |
// [16..23] number_density_cm3              : f64                                                               |
// [24..31] oxygen_number_density_cm3       : f64                                                               |
// [32..39] cia_pair_density_cm6            : f64                                                               |
// [40..47] absorber_number_density_cm3     : f64                                                               |
// [48..55] aerosol_optical_depth_per_km    : f64                                                               |
// [56..63] aerosol_single_scatter_albedo   : f64                                                               |
// [64..71] aerosol_reference_wavelength_nm : f64                                                               |
// [72..79] aerosol_angstrom_exponent       : f64                                                               |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// cache span: 2 cache lines at 64 B per line                                                                   |
// footprint: per instance = 80 B; stack value during altitude interpolation                                    |
pub const InterpolatedQuadratureState = struct {
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    cia_pair_density_cm6: f64 = 0.0,
    absorber_number_density_cm3: f64,
    aerosol_optical_depth_per_km: f64,
    aerosol_single_scatter_albedo: f64,
    aerosol_reference_wavelength_nm: f64 = 550.0,
    aerosol_angstrom_exponent: f64 = 0.0,

    fn ciaPairDensityCm6(self: InterpolatedQuadratureState) f64 {
        if (self.cia_pair_density_cm6 > 0.0) return self.cia_pair_density_cm6;

        return self.oxygen_number_density_cm3 * self.oxygen_number_density_cm3;
    }
};
// ------------------------------------------------------------------------------------------------------------ |

fn opticalDepthPerKilometer(optical_depth: f64, path_length_cm: f64) f64 {
    const span_km = @max(path_length_cm / centimeters_per_kilometer, 0.0);
    return if (span_km > 0.0) optical_depth / span_km else 0.0;
}

fn continuumSigmaAtWavelength(
    prepared: *const State.PreparedOpticalState,
    wavelength_nm: f64,
) f64 {
    if (prepared.cross_section_absorbers.len != 0) return 0.0;

    const continuum_table: ReferenceData.CrossSectionTable = .{ .points = prepared.continuum_points };
    return continuum_table.interpolateSigma(wavelength_nm);
}

fn strongLineStateAt(
    states: ?[]const ReferenceData.StrongLinePreparedState,
    local_index: usize,
) ?*const ReferenceData.StrongLinePreparedState {
    const owned_states = states orelse return null;
    if (local_index >= owned_states.len) return null;
    return &owned_states[local_index];
}

fn particleWavelengthScale(
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    wavelength_nm: f64,
) f64 {
    if (angstrom_exponent == 0.0 or reference_wavelength_nm == wavelength_nm) return 1.0;

    const safe_wavelength = @max(wavelength_nm, 1.0);
    const safe_reference = @max(reference_wavelength_nm, 1.0);

    return std.math.pow(f64, safe_reference / safe_wavelength, angstrom_exponent);
}

fn scaleParticleDepth(optical_depth: f64, scale: f64) f64 {
    return if (optical_depth == 0.0) 0.0 else optical_depth * scale;
}

fn interpolateValue(left_weight: f64, left_value: f64, right_weight: f64, right_value: f64) f64 {
    return left_weight * left_value + right_weight * right_value;
}

fn interpolateNonNegative(left_weight: f64, left_value: f64, right_weight: f64, right_value: f64) f64 {
    return @max(interpolateValue(left_weight, left_value, right_weight, right_value), 0.0);
}

fn particleBoundaryCarrierAtSupportRow(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
) ParticleBoundaryCarrier {
    return particleBoundaryCarrierAtSupportRowWithScales(
        sublayer,
        ParticleWavelengthScales.init(self, wavelength_nm),
    );
}

fn particleBoundaryCarrierAtSupportRowWithScales(
    sublayer: PreparedSublayer,
    scales: ParticleWavelengthScales,
) ParticleBoundaryCarrier {
    const aerosol_scale = scales.aerosolScale(sublayer);
    const aerosol_optical_depth_per_km = scaleParticleDepth(
        opticalDepthPerKilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
        aerosol_scale,
    );
    const aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * sublayer.aerosol_single_scatter_albedo;

    return .{
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
    };
}

fn particleBoundaryCarrierFromIndexWithScales(
    sublayers: []const PreparedSublayer,
    support_row_index: u32,
    scales: ParticleWavelengthScales,
) ParticleBoundaryCarrier {
    if (support_row_index == @import("shared_geometry.zig").invalid_support_row_index) return .{};

    const row_index: usize = @intCast(support_row_index);
    if (row_index >= sublayers.len) return .{};

    return particleBoundaryCarrierAtSupportRowWithScales(sublayers[row_index], scales);
}

fn particleBoundaryCarrierFromIndex(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    support_row_index: u32,
) ParticleBoundaryCarrier {
    if (support_row_index == @import("shared_geometry.zig").invalid_support_row_index) return .{};

    const row_index: usize = @intCast(support_row_index);
    if (row_index >= sublayers.len) return .{};

    return particleBoundaryCarrierAtSupportRow(self, wavelength_nm, sublayers[row_index]);
}

pub fn sharedBoundaryCarrierAtLevel(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
) SharedBoundaryCarrier {
    return sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        level_geometry,
        null,
    );
}

pub fn sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedBoundaryCarrier {
    // sharedBoundaryCarrierAtLevelWithSpectroscopyCache ------------------------------------------------------ |
    // Evaluates one boundary carrier without the wavelength carrier cache.                                     |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Called by RTM level and source-interface routes that have a spectroscopy cache but no scalar row       |
    //   cache. The boundary gas row is evaluated once, then particle rows above and below the interface are    |
    //   mixed into scattering and phase fields.                                                                |
    //                                                                                                          |
    // math                                                                                                     |
    //   k_sca_above = k_sca_gas + k_sca_particle_above                                                         |
    //   k_sca_below = k_sca_gas + k_sca_particle_below                                                         |
    // -------------------------------------------------------------------------------------------------------  |

    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) return .{};

    const strong_line_state = strongLineStateAt(strong_line_states, boundary_row_index);
    const gas_carrier = sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers[boundary_row_index],
        boundary_row_index,
        strong_line_state,
        profile_cache,
    );
    const particle_above = particleBoundaryCarrierFromIndex(
        self,
        wavelength_nm,
        sublayers,
        level_geometry.particle_above_support_row_index,
    );
    const particle_below = particleBoundaryCarrierFromIndex(
        self,
        wavelength_nm,
        sublayers,
        level_geometry.particle_below_support_row_index,
    );
    const gas_scattering_optical_depth_per_km = gas_carrier.gas_scattering_optical_depth_per_km;
    const rayleigh_phase_coefficient2 = PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm);
    const phase_above = PhaseFunctions.PhaseMixture.fromScatteringMix(
        rayleigh_phase_coefficient2,
        gas_scattering_optical_depth_per_km,
        particle_above.aerosol_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
    );
    const phase_below = PhaseFunctions.PhaseMixture.fromScatteringMix(
        rayleigh_phase_coefficient2,
        gas_scattering_optical_depth_per_km,
        particle_below.aerosol_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
    );
    return .{
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .particle_scattering_optical_depth_above_per_km = particle_above.totalScatteringOpticalDepthPerKm(),
        .particle_scattering_optical_depth_below_per_km = particle_below.totalScatteringOpticalDepthPerKm(),
        .aerosol_scattering_optical_depth_above_per_km = particle_above.aerosol_scattering_optical_depth_per_km,
        .aerosol_scattering_optical_depth_below_per_km = particle_below.aerosol_scattering_optical_depth_per_km,
        .ksca_above = gas_scattering_optical_depth_per_km + particle_above.totalScatteringOpticalDepthPerKm(),
        .ksca_below = gas_scattering_optical_depth_per_km + particle_below.totalScatteringOpticalDepthPerKm(),
        .phase_above = phase_above,
        .phase_max_index_above = phase_above.maxIndex(),
        .phase_max_index_below = phase_below.maxIndex(),
    };
}

pub fn sharedBoundaryCarrierAtLevelWithCarrierCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    wavelength_cache: *WavelengthCarrierCache,
) SharedBoundaryCarrier {
    // sharedBoundaryCarrierAtLevelWithCarrierCache ----------------------------------------------------------  |
    // Reads gas fields through WavelengthCarrierCache and composes one boundary carrier.                       |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Reuses cached support-row scalars and precomputed Rayleigh P2(lambda). Only particle boundary rows     |
    //   are rebuilt here because they depend on above/below interface placement.                               |
    //                                                                                                          |
    // math                                                                                                     |
    //   k_sca = k_sca_gas + k_sca_particle                                                                     |
    // -------------------------------------------------------------------------------------------------------  |

    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) return .{};

    const strong_line_state = strongLineStateAt(strong_line_states, boundary_row_index);
    var fallback_gas_carrier: SharedOpticalScalars = undefined;
    const gas_carrier = wavelength_cache.cachedSupportRowScalarsRef(
        self,
        wavelength_nm,
        sublayers[boundary_row_index],
        boundary_row_index,
        strong_line_state,
        &fallback_gas_carrier,
    );
    const particle_above = particleBoundaryCarrierFromIndexWithScales(
        sublayers,
        level_geometry.particle_above_support_row_index,
        wavelength_cache.particle_scales,
    );
    const particle_below = particleBoundaryCarrierFromIndexWithScales(
        sublayers,
        level_geometry.particle_below_support_row_index,
        wavelength_cache.particle_scales,
    );
    const gas_scattering_optical_depth_per_km = gas_carrier.gas_scattering_optical_depth_per_km;
    const phase_above = PhaseFunctions.PhaseMixture.fromScatteringMix(
        wavelength_cache.rayleigh_phase_coefficient2,
        gas_scattering_optical_depth_per_km,
        particle_above.aerosol_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
    );
    const phase_below = PhaseFunctions.PhaseMixture.fromScatteringMix(
        wavelength_cache.rayleigh_phase_coefficient2,
        gas_scattering_optical_depth_per_km,
        particle_below.aerosol_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
    );
    return .{
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .particle_scattering_optical_depth_above_per_km = particle_above.totalScatteringOpticalDepthPerKm(),
        .particle_scattering_optical_depth_below_per_km = particle_below.totalScatteringOpticalDepthPerKm(),
        .aerosol_scattering_optical_depth_above_per_km = particle_above.aerosol_scattering_optical_depth_per_km,
        .aerosol_scattering_optical_depth_below_per_km = particle_below.aerosol_scattering_optical_depth_per_km,
        .ksca_above = gas_scattering_optical_depth_per_km + particle_above.totalScatteringOpticalDepthPerKm(),
        .ksca_below = gas_scattering_optical_depth_per_km + particle_below.totalScatteringOpticalDepthPerKm(),
        .phase_above = phase_above,
        .phase_max_index_above = phase_above.maxIndex(),
        .phase_max_index_below = phase_below.maxIndex(),
    };
}

pub fn fillSourceInterfaceAtLevelWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    rtm_weight: f64,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    source_interface: *transport_common.SourceInterfaceInput,
) void {
    // fillSourceInterfaceAtLevelWithSpectroscopyCache -------------------------------------------------------  |
    // Writes one shared-grid source interface without a wavelength carrier cache.                              |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Composes support-row gas scattering, particle boundary rows, and prepared phase rows for one RTM       |
    //   interface. The carrier-cache twin below keeps the same output shape while reusing scalar rows.         |
    //                                                                                                          |
    // math                                                                                                     |
    //   k_sca_above = k_sca_gas + k_sca_particle_above                                                         |
    //   phase_above/below = mix(P_rayleigh, P_aerosol, k_sca)                                                  |
    // -------------------------------------------------------------------------------------------------------  |

    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) {
        source_interface.* = .{ .rtm_weight = rtm_weight };
        return;
    }

    const strong_line_state = strongLineStateAt(strong_line_states, boundary_row_index);
    const gas_carrier = sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers[boundary_row_index],
        boundary_row_index,
        strong_line_state,
        profile_cache,
    );
    const particle_above = particleBoundaryCarrierFromIndex(
        self,
        wavelength_nm,
        sublayers,
        level_geometry.particle_above_support_row_index,
    );
    const particle_below = particleBoundaryCarrierFromIndex(
        self,
        wavelength_nm,
        sublayers,
        level_geometry.particle_below_support_row_index,
    );
    fillSourceInterfaceFromBoundaryParts(
        self,
        wavelength_nm,
        gas_carrier.gas_scattering_optical_depth_per_km,
        particle_above,
        particle_below,
        rtm_weight,
        null,
        source_interface,
    );
}

pub fn fillSourceInterfaceAtLevelWithCarrierCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    rtm_weight: f64,
    wavelength_cache: *WavelengthCarrierCache,
    source_interface: *transport_common.SourceInterfaceInput,
) void {
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) {
        source_interface.* = .{ .rtm_weight = rtm_weight };
        return;
    }
    const strong_line_state = strongLineStateAt(strong_line_states, boundary_row_index);
    var fallback_gas_carrier: SharedOpticalScalars = undefined;
    const gas_carrier = wavelength_cache.cachedSupportRowScalarsRef(
        self,
        wavelength_nm,
        sublayers[boundary_row_index],
        boundary_row_index,
        strong_line_state,
        &fallback_gas_carrier,
    );
    const particle_above = particleBoundaryCarrierFromIndexWithScales(
        sublayers,
        level_geometry.particle_above_support_row_index,
        wavelength_cache.particle_scales,
    );
    const particle_below = particleBoundaryCarrierFromIndexWithScales(
        sublayers,
        level_geometry.particle_below_support_row_index,
        wavelength_cache.particle_scales,
    );
    fillSourceInterfaceFromBoundaryParts(
        self,
        wavelength_nm,
        gas_carrier.gas_scattering_optical_depth_per_km,
        particle_above,
        particle_below,
        rtm_weight,
        wavelength_cache.rayleigh_phase_coefficient2,
        source_interface,
    );
}

fn fillSourceInterfaceFromBoundaryParts(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    gas_scattering_optical_depth_per_km: f64,
    particle_above: ParticleBoundaryCarrier,
    particle_below: ParticleBoundaryCarrier,
    rtm_weight: f64,
    rayleigh_phase_coefficient2: ?f64,
    source_interface: *transport_common.SourceInterfaceInput,
) void {
    const particle_above_total = particle_above.totalScatteringOpticalDepthPerKm();
    const rayleigh_coef2 = rayleigh_phase_coefficient2 orelse
        PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm);
    const phase_above = PhaseFunctions.PhaseMixture.fromScatteringMix(
        rayleigh_coef2,
        gas_scattering_optical_depth_per_km,
        particle_above.aerosol_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
    );
    const phase_below = PhaseFunctions.PhaseMixture.fromScatteringMix(
        rayleigh_coef2,
        gas_scattering_optical_depth_per_km,
        particle_below.aerosol_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
    );
    source_interface.* = .{
        .source_weight = 0.0,
        .rtm_weight = rtm_weight,
        .ksca_above = gas_scattering_optical_depth_per_km + particle_above_total,
        .phase_above = phase_above,
        .phase_max_index_above = phase_above.maxIndex(),
        .phase_max_index_below = phase_below.maxIndex(),
    };
}

pub fn fillRtmQuadratureLevelAtLevelWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    rtm_level: *transport_common.RtmQuadratureLevel,
    compute_jacobian: bool,
) void {
    // fillRtmQuadratureLevelAtLevelWithSpectroscopyCache ----------------------------------------------------  |
    // Writes one shared-grid RTM quadrature level without a wavelength carrier cache.                          |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Integrated source-function routes use this when they need source fields on quadrature levels. The      |
    //   same gas, particle, and phase mixture equations are shared with source interfaces.                     |
    // -------------------------------------------------------------------------------------------------------  |

    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) {
        fillZeroRtmQuadratureLevel(level_geometry, rtm_level, compute_jacobian);
        return;
    }

    const strong_line_state = strongLineStateAt(strong_line_states, boundary_row_index);
    const gas_carrier = sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers[boundary_row_index],
        boundary_row_index,
        strong_line_state,
        profile_cache,
    );
    const particle_above = particleBoundaryCarrierFromIndex(
        self,
        wavelength_nm,
        sublayers,
        level_geometry.particle_above_support_row_index,
    );
    const particle_below = particleBoundaryCarrierFromIndex(
        self,
        wavelength_nm,
        sublayers,
        level_geometry.particle_below_support_row_index,
    );
    fillRtmQuadratureLevelFromBoundaryParts(
        wavelength_nm,
        level_geometry,
        gas_carrier.gas_scattering_optical_depth_per_km,
        particle_above,
        particle_below,
        null,
        rtm_level,
        compute_jacobian,
    );
}

pub fn fillRtmQuadratureLevelAtLevelWithCarrierCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    wavelength_cache: *WavelengthCarrierCache,
    rtm_level: *transport_common.RtmQuadratureLevel,
    compute_jacobian: bool,
) void {
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) {
        fillZeroRtmQuadratureLevel(level_geometry, rtm_level, compute_jacobian);
        return;
    }
    const strong_line_state = strongLineStateAt(strong_line_states, boundary_row_index);
    var fallback_gas_carrier: SharedOpticalScalars = undefined;
    const gas_carrier = wavelength_cache.cachedSupportRowScalarsRef(
        self,
        wavelength_nm,
        sublayers[boundary_row_index],
        boundary_row_index,
        strong_line_state,
        &fallback_gas_carrier,
    );
    const particle_above = particleBoundaryCarrierFromIndexWithScales(
        sublayers,
        level_geometry.particle_above_support_row_index,
        wavelength_cache.particle_scales,
    );
    const particle_below = particleBoundaryCarrierFromIndexWithScales(
        sublayers,
        level_geometry.particle_below_support_row_index,
        wavelength_cache.particle_scales,
    );
    fillRtmQuadratureLevelFromBoundaryParts(
        wavelength_nm,
        level_geometry,
        gas_carrier.gas_scattering_optical_depth_per_km,
        particle_above,
        particle_below,
        wavelength_cache.rayleigh_phase_coefficient2,
        rtm_level,
        compute_jacobian,
    );
}

fn fillRtmQuadratureLevelFromBoundaryParts(
    wavelength_nm: f64,
    level_geometry: SharedRtmLevelGeometry,
    gas_scattering_optical_depth_per_km: f64,
    particle_above: ParticleBoundaryCarrier,
    particle_below: ParticleBoundaryCarrier,
    rayleigh_phase_coefficient2: ?f64,
    rtm_level: *transport_common.RtmQuadratureLevel,
    compute_jacobian: bool,
) void {
    const aerosol_ksca = particle_above.aerosol_scattering_optical_depth_per_km;
    rtm_level.altitude_km = level_geometry.altitude_km;
    rtm_level.weight = level_geometry.weight_km;
    rtm_level.ksca = gas_scattering_optical_depth_per_km + particle_above.totalScatteringOpticalDepthPerKm();
    rtm_level.aerosol_ksca_above_per_km = aerosol_ksca;
    rtm_level.aerosol_ksca_below_per_km = particle_below.aerosol_scattering_optical_depth_per_km;
    if (compute_jacobian) rtm_level.aerosol_ksca_jacobian = 0.0;
    rtm_level.setPhaseMixture(
        rayleigh_phase_coefficient2 orelse PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm),
        gas_scattering_optical_depth_per_km,
        aerosol_ksca,
    );
}

fn fillZeroRtmQuadratureLevel(
    level_geometry: SharedRtmLevelGeometry,
    rtm_level: *transport_common.RtmQuadratureLevel,
    compute_jacobian: bool,
) void {
    rtm_level.altitude_km = level_geometry.altitude_km;
    rtm_level.weight = level_geometry.weight_km;
    rtm_level.ksca = 0.0;
    rtm_level.aerosol_ksca_above_per_km = 0.0;
    rtm_level.aerosol_ksca_below_per_km = 0.0;
    if (compute_jacobian) rtm_level.aerosol_ksca_jacobian = 0.0;
    rtm_level.phase_aerosol_weight = 0.0;
    rtm_level.phase_rayleigh2_weight = 0.0;
}

pub fn sharedActiveCarrierAtLevel(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
) SharedOpticalCarrier {
    return sharedActiveCarrierAtLevelWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        level_geometry,
        null,
    );
}

pub fn sharedActiveCarrierAtLevelWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalCarrier {
    // sharedActiveCarrierAtLevelWithSpectroscopyCache -------------------------------------------------------  |
    // Blends support-row particle carriers for an arbitrary RTM or pseudo-spherical level.                     |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Gas terms come from the boundary support row. Aerosol terms are copied from a single particle row      |
    //   when one side is missing, or linearly interpolated between below/above particle rows.                  |
    //                                                                                                          |
    // math                                                                                                     |
    //   fraction = clamp((z - z_below) / (z_above - z_below), 0, 1)                                            |
    // -------------------------------------------------------------------------------------------------------  |

    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) return .{};

    const strong_line_state = strongLineStateAt(strong_line_states, boundary_row_index);
    const gas_carrier = sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers[boundary_row_index],
        boundary_row_index,
        strong_line_state,
        profile_cache,
    );

    const below_index_u32 = level_geometry.particle_below_support_row_index;
    const above_index_u32 = level_geometry.particle_above_support_row_index;
    const invalid_index = @import("shared_geometry.zig").invalid_support_row_index;
    if (below_index_u32 == invalid_index and above_index_u32 == invalid_index) return gas_carrier;

    if (below_index_u32 == invalid_index) {
        const above_index: usize = @intCast(above_index_u32);
        if (above_index >= sublayers.len) return gas_carrier;

        const particle = particleBoundaryCarrierAtSupportRow(self, wavelength_nm, sublayers[above_index]);
        return composeSharedActiveCarrier(gas_carrier, particle, particle, 0.0);
    }

    if (above_index_u32 == invalid_index) {
        const below_index: usize = @intCast(below_index_u32);
        if (below_index >= sublayers.len) return gas_carrier;

        const particle = particleBoundaryCarrierAtSupportRow(self, wavelength_nm, sublayers[below_index]);
        return composeSharedActiveCarrier(gas_carrier, particle, particle, 0.0);
    }

    const below_index: usize = @intCast(below_index_u32);
    const above_index: usize = @intCast(above_index_u32);
    if (below_index >= sublayers.len or above_index >= sublayers.len) return gas_carrier;

    const below_row = sublayers[below_index];
    const above_row = sublayers[above_index];
    const altitude_span_km = above_row.altitude_km - below_row.altitude_km;
    const fraction = if (altitude_span_km > 0.0)
        std.math.clamp((level_geometry.altitude_km - below_row.altitude_km) / altitude_span_km, 0.0, 1.0)
    else
        0.5;
    const particle_below = particleBoundaryCarrierAtSupportRow(self, wavelength_nm, below_row);
    const particle_above = particleBoundaryCarrierAtSupportRow(self, wavelength_nm, above_row);
    return composeSharedActiveCarrier(gas_carrier, particle_below, particle_above, fraction);
}

fn composeSharedActiveCarrier(
    gas_carrier: SharedOpticalCarrier,
    particle_below: ParticleBoundaryCarrier,
    particle_above: ParticleBoundaryCarrier,
    fraction: f64,
) SharedOpticalCarrier {
    // composeSharedActiveCarrier ----------------------------------------------------------------------------- |
    // Copies gas terms and interpolates aerosol fields across one support interval.                            |
    //                                                                                                          |
    // math                                                                                                     |
    //   aerosol_k = (1 - f) * aerosol_k_below + f * aerosol_k_above                                            |
    // -------------------------------------------------------------------------------------------------------- |

    const clamped_fraction = std.math.clamp(fraction, 0.0, 1.0);
    const left_weight = 1.0 - clamped_fraction;
    const right_weight = clamped_fraction;
    const aerosol_optical_depth_per_km =
        left_weight * particle_below.aerosol_optical_depth_per_km +
        right_weight * particle_above.aerosol_optical_depth_per_km;
    const aerosol_scattering_optical_depth_per_km =
        left_weight * particle_below.aerosol_scattering_optical_depth_per_km +
        right_weight * particle_above.aerosol_scattering_optical_depth_per_km;
    return .{
        .gas_absorption_optical_depth_per_km = gas_carrier.gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_carrier.gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = gas_carrier.cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
    };
}

fn interpolateQuadratureStateBetweenSublayers(
    left: PreparedSublayer,
    right: PreparedSublayer,
    altitude_km: f64,
) InterpolatedQuadratureState {
    const interpolation_span_km = right.altitude_km - left.altitude_km;
    const fraction = if (interpolation_span_km > 0.0)
        (altitude_km - left.altitude_km) / interpolation_span_km
    else
        0.0;
    const clamped_fraction = std.math.clamp(fraction, 0.0, 1.0);
    const left_weight = 1.0 - clamped_fraction;
    const right_weight = clamped_fraction;

    const left_aerosol_per_km = opticalDepthPerKilometer(left.aerosol_optical_depth, left.path_length_cm);
    const right_aerosol_per_km = opticalDepthPerKilometer(right.aerosol_optical_depth, right.path_length_cm);

    return .{
        .pressure_hpa = interpolateNonNegative(left_weight, left.pressure_hpa, right_weight, right.pressure_hpa),
        .temperature_k = interpolateNonNegative(left_weight, left.temperature_k, right_weight, right.temperature_k),
        .number_density_cm3 = interpolateNonNegative(
            left_weight,
            left.number_density_cm3,
            right_weight,
            right.number_density_cm3,
        ),
        .oxygen_number_density_cm3 = interpolateNonNegative(
            left_weight,
            left.oxygen_number_density_cm3,
            right_weight,
            right.oxygen_number_density_cm3,
        ),
        .cia_pair_density_cm6 = interpolateNonNegative(
            left_weight,
            left.ciaPairDensityCm6(),
            right_weight,
            right.ciaPairDensityCm6(),
        ),
        .absorber_number_density_cm3 = interpolateNonNegative(
            left_weight,
            left.absorber_number_density_cm3,
            right_weight,
            right.absorber_number_density_cm3,
        ),
        .aerosol_optical_depth_per_km = interpolateNonNegative(
            left_weight,
            left_aerosol_per_km,
            right_weight,
            right_aerosol_per_km,
        ),
        .aerosol_single_scatter_albedo = std.math.clamp(
            interpolateValue(
                left_weight,
                left.aerosol_single_scatter_albedo,
                right_weight,
                right.aerosol_single_scatter_albedo,
            ),
            0.0,
            1.0,
        ),
        .aerosol_reference_wavelength_nm = @max(
            interpolateValue(
                left_weight,
                left.aerosol_reference_wavelength_nm,
                right_weight,
                right.aerosol_reference_wavelength_nm,
            ),
            1.0,
        ),
        .aerosol_angstrom_exponent = interpolateValue(
            left_weight,
            left.aerosol_angstrom_exponent,
            right_weight,
            right.aerosol_angstrom_exponent,
        ),
    };
}

pub fn interpolateQuadratureStateAtAltitude(
    sublayers: []const PreparedSublayer,
    altitude_km: f64,
) ?InterpolatedQuadratureState {
    // interpolateQuadratureStateAtAltitude ------------------------------------------------------------------- |
    // Finds the prepared support interval that brackets an arbitrary altitude.                                 |
    //                                                                                                          |
    // testing                                                                                                  |
    //   Kept pub so internal.zig can re-export this helper. Extracting the body would also require lifting     |
    //   interpolateQuadratureStateBetweenSublayers and opticalDepthPerKilometer, both used only here.          |
    // -------------------------------------------------------------------------------------------------------- |

    if (sublayers.len == 0) return null;

    if (sublayers.len == 1) {
        const sublayer = sublayers[0];
        return .{
            .pressure_hpa = sublayer.pressure_hpa,
            .temperature_k = sublayer.temperature_k,
            .number_density_cm3 = sublayer.number_density_cm3,
            .oxygen_number_density_cm3 = sublayer.oxygen_number_density_cm3,
            .cia_pair_density_cm6 = sublayer.ciaPairDensityCm6(),
            .absorber_number_density_cm3 = sublayer.absorber_number_density_cm3,
            .aerosol_optical_depth_per_km = opticalDepthPerKilometer(
                sublayer.aerosol_optical_depth,
                sublayer.path_length_cm,
            ),
            .aerosol_single_scatter_albedo = sublayer.aerosol_single_scatter_albedo,
            .aerosol_reference_wavelength_nm = sublayer.aerosol_reference_wavelength_nm,
            .aerosol_angstrom_exponent = sublayer.aerosol_angstrom_exponent,
        };
    }

    const first = sublayers[0];
    const last = sublayers[sublayers.len - 1];

    if (altitude_km <= first.altitude_km) {
        return interpolateQuadratureStateBetweenSublayers(first, sublayers[1], altitude_km);
    }

    if (altitude_km >= last.altitude_km) {
        return interpolateQuadratureStateBetweenSublayers(sublayers[sublayers.len - 2], last, altitude_km);
    }

    for (sublayers[0 .. sublayers.len - 1], sublayers[1..]) |left, right| {
        if (altitude_km > right.altitude_km) continue;
        return interpolateQuadratureStateBetweenSublayers(left, right, altitude_km);
    }

    return null;
}

pub fn quadratureCarrierAtAltitude(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
) PreparedQuadratureCarrier {
    return quadratureCarrierAtAltitudeWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        altitude_km,
        null,
    );
}

pub fn quadratureCarrierAtAltitudeWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) PreparedQuadratureCarrier {
    const carrier = sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        altitude_km,
        profile_cache,
    );
    return .{
        .ksca = carrier.totalScatteringOpticalDepthPerKm(),
        .gas_scattering_optical_depth_per_km = carrier.gas_scattering_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = carrier.aerosol_scattering_optical_depth_per_km,
    };
}

fn weightedSpectroscopyEvaluationAtSupportRow(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) ReferenceData.SpectroscopyEvaluation {
    // weightedSpectroscopyEvaluationAtSupportRow ------------------------------------------------------------- |
    // Density-weights active line absorbers into one spectroscopy evaluation for a support row.                |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Runs while filling support-row carriers for one wavelength. Operational O2 is evaluated once, then     |
    //   non-O2 line absorbers are folded in with their row-local number densities.                             |
    // -------------------------------------------------------------------------------------------------------- |

    var total_weight: f64 = 0.0;
    var weighted: ReferenceData.SpectroscopyEvaluation = .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };

    if (self.operational_o2_lut.enabled() and sublayer.oxygen_number_density_cm3 > 0.0) {
        const o2_evaluation = self.weightedSpectroscopyEvaluationAtWavelength(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        );
        total_weight += sublayer.oxygen_number_density_cm3;
        addWeightedSpectroscopyEvaluation(
            &weighted,
            o2_evaluation,
            sublayer.oxygen_number_density_cm3,
        );
    }

    for (self.line_absorbers) |line_absorber| {
        if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
        if (global_sublayer_index >= line_absorber.number_densities_cm3.len) continue;

        const weight = line_absorber.number_densities_cm3[global_sublayer_index];
        if (weight <= 0.0) continue;

        const prepared_state = strongLineStateAt(line_absorber.strong_line_states, global_sublayer_index);
        const evaluation = line_absorber.line_list.evaluateAtPrepared(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
            prepared_state,
        );
        total_weight += weight;
        addWeightedSpectroscopyEvaluation(&weighted, evaluation, weight);
    }

    if (total_weight <= 0.0) return weighted;
    normalizeSpectroscopyEvaluation(&weighted, total_weight);
    return weighted;
}

fn addWeightedSpectroscopyEvaluation(
    weighted: *ReferenceData.SpectroscopyEvaluation,
    evaluation: ReferenceData.SpectroscopyEvaluation,
    weight: f64,
) void {
    weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * weight;
    weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * weight;
    weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * weight;
    weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * weight;
    weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
        evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * weight;
}

fn normalizeSpectroscopyEvaluation(
    weighted: *ReferenceData.SpectroscopyEvaluation,
    total_weight: f64,
) void {
    weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
    weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
    weighted.total_sigma_cm2_per_molecule /= total_weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
}

pub fn sharedOpticalCarrierAtSupportRow(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
) SharedOpticalCarrier {
    return sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayer,
        global_sublayer_index,
        strong_line_state,
        null,
    );
}

pub fn sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalCarrier {
    // sharedOpticalCarrierAtSupportRowWithSpectroscopyCache -------------------------------------------------  |
    // Fills one full support-row carrier without WavelengthCarrierCache.                                       |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Used by routes that have a profile spectroscopy cache but are not reusing scalar support-row rows.     |
    //   Wavelength constants are prepared here and passed to the scalar filler below.                          |
    // -------------------------------------------------------------------------------------------------------  |

    const continuum_sigma = continuumSigmaAtWavelength(self, wavelength_nm);
    const scalars = sharedOpticalScalarsAtSupportRowWithScalarCache(
        self,
        wavelength_nm,
        sublayer,
        global_sublayer_index,
        strong_line_state,
        profile_cache,
        continuum_sigma,
        null,
        Rayleigh.crossSectionCm2(wavelength_nm),
        ParticleWavelengthScales.init(self, wavelength_nm),
    );
    return sharedOpticalCarrierFromScalars(scalars);
}

fn sharedOpticalScalarsAtSupportRowWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalScalars {
    const continuum_sigma = continuumSigmaAtWavelength(self, wavelength_nm);
    return sharedOpticalScalarsAtSupportRowWithScalarCache(
        self,
        wavelength_nm,
        sublayer,
        global_sublayer_index,
        strong_line_state,
        profile_cache,
        continuum_sigma,
        null,
        Rayleigh.crossSectionCm2(wavelength_nm),
        ParticleWavelengthScales.init(self, wavelength_nm),
    );
}

fn sharedOpticalScalarsAtSupportRowWithScalarCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    continuum_sigma: f64,
    cia_coefficients: ?CiaWavelengthCoefficients,
    rayleigh_cross_section_cm2: f64,
    particle_scales: ParticleWavelengthScales,
) SharedOpticalScalars {
    var scalars: SharedOpticalScalars = undefined;
    fillSharedOpticalScalarsAtSupportRowWithScalarCache(
        &scalars,
        self,
        wavelength_nm,
        sublayer,
        global_sublayer_index,
        strong_line_state,
        profile_cache,
        continuum_sigma,
        cia_coefficients,
        rayleigh_cross_section_cm2,
        particle_scales,
    );
    return scalars;
}

fn spectroscopySigmaAtSupportRow(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) f64 {
    if (self.line_absorbers.len != 0) {
        return weightedSpectroscopyEvaluationAtSupportRow(
            self,
            wavelength_nm,
            sublayer,
            global_sublayer_index,
        ).total_sigma_cm2_per_molecule;
    }

    return self.spectroscopySigmaAtAltitudeWithCache(
        wavelength_nm,
        sublayer.temperature_k,
        sublayer.pressure_hpa,
        sublayer.altitude_km,
        strong_line_state,
        profile_cache,
    );
}

fn continuumDensityAtSupportRow(
    self: *const State.PreparedOpticalState,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) f64 {
    if (self.cross_section_absorbers.len != 0) return 0.0;

    return Scalar.continuumCarrierDensityAtSublayer(
        self,
        sublayer,
        global_sublayer_index,
    );
}

fn ciaSigmaAtSupportRow(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    cia_coefficients: ?CiaWavelengthCoefficients,
) f64 {
    if (cia_coefficients) |coefficients| {
        return coefficients.sigmaAtTemperature(sublayer.temperature_k);
    }

    return self.ciaSigmaAtWavelength(
        wavelength_nm,
        sublayer.temperature_k,
        sublayer.pressure_hpa,
    );
}

fn fillSharedOpticalScalarsAtSupportRowWithScalarCache(
    out: *SharedOpticalScalars,
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    continuum_sigma: f64,
    cia_coefficients: ?CiaWavelengthCoefficients,
    rayleigh_cross_section_cm2: f64,
    particle_scales: ParticleWavelengthScales,
) void {
    // fillSharedOpticalScalarsAtSupportRowWithScalarCache ---------------------------------------------------  |
    // Combines gas, CIA, Rayleigh, and aerosol terms into one cached scalar row.                               |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Runs on a support-row cache miss for the current wavelength. The caller passes wavelength constants    |
    //   so the repeated boundary/source/quadrature paths do not redo those lookups.                            |
    //                                                                                                          |
    // math                                                                                                     |
    //   k_abs_gas = sigma_cont*n_cont*1e5 + sigma_xs*n_xs*1e5 + sigma_line*n_line*1e5                          |
    //   k_sca_gas = sigma_R*n_air*1e5                                                                          |
    //   k_cia     = sigma_cia*n_pair*1e5                                                                       |
    // -------------------------------------------------------------------------------------------------------  |

    const spectroscopy_sigma = spectroscopySigmaAtSupportRow(
        self,
        wavelength_nm,
        sublayer,
        global_sublayer_index,
        strong_line_state,
        profile_cache,
    );

    var cross_section_density_cm3: f64 = 0.0;
    var cross_section_absorption_optical_depth_per_km: f64 = 0.0;
    for (self.cross_section_absorbers) |cross_section_absorber| {
        if (global_sublayer_index >= cross_section_absorber.number_densities_cm3.len) continue;

        const absorber_density_cm3 = cross_section_absorber.number_densities_cm3[global_sublayer_index];
        if (absorber_density_cm3 <= 0.0) continue;

        cross_section_density_cm3 += absorber_density_cm3;
        cross_section_absorption_optical_depth_per_km +=
            cross_section_absorber.sigmaAt(
                wavelength_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
            ) *
            absorber_density_cm3 *
            centimeters_per_kilometer;
    }

    const line_absorber_density_cm3 = Scalar.lineSpectroscopyCarrierDensityAtSublayer(
        self,
        sublayer,
        global_sublayer_index,
    );
    const continuum_density_cm3 = continuumDensityAtSupportRow(
        self,
        sublayer,
        global_sublayer_index,
    );
    const gas_absorption_optical_depth_per_km =
        continuum_sigma * continuum_density_cm3 * centimeters_per_kilometer +
        cross_section_absorption_optical_depth_per_km +
        spectroscopy_sigma * line_absorber_density_cm3 * centimeters_per_kilometer;
    const gas_scattering_optical_depth_per_km =
        rayleigh_cross_section_cm2 *
        sublayer.number_density_cm3 *
        centimeters_per_kilometer;
    const cia_sigma_cm5_per_molecule2 = ciaSigmaAtSupportRow(
        self,
        wavelength_nm,
        sublayer,
        cia_coefficients,
    );
    const cia_optical_depth_per_km =
        cia_sigma_cm5_per_molecule2 *
        sublayer.ciaPairDensityCm6() *
        centimeters_per_kilometer;
    const aerosol_optical_depth_per_km = scaleParticleDepth(
        opticalDepthPerKilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
        particle_scales.aerosol,
    );
    const aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * sublayer.aerosol_single_scatter_albedo;
    out.* = .{
        .gas_absorption_optical_depth_per_km = gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
    };
}

fn sharedOpticalCarrierFromScalars(scalars: SharedOpticalScalars) SharedOpticalCarrier {
    return .{
        .gas_absorption_optical_depth_per_km = scalars.gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = scalars.gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = scalars.cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = scalars.aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = scalars.aerosol_scattering_optical_depth_per_km,
    };
}

pub fn sharedOpticalCarrierAtSupportRowWithCarrierCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    wavelength_cache: *WavelengthCarrierCache,
) SharedOpticalCarrier {
    // sharedOpticalCarrierAtSupportRowWithCarrierCache ------------------------------------------------------  |
    // Returns one full support-row carrier through WavelengthCarrierCache.                                     |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Reuses the scalar row cache and only rebuilds the public carrier value from cached scalar fields.      |
    // -------------------------------------------------------------------------------------------------------  |

    return wavelength_cache.cachedSupportRow(
        self,
        wavelength_nm,
        sublayer,
        global_sublayer_index,
        strong_line_state,
    );
}

pub fn sharedOpticalCarrierAtAltitude(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
) SharedOpticalCarrier {
    return sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        altitude_km,
        null,
    );
}

fn spectroscopySigmaAtCarrierAltitude(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    state: InterpolatedQuadratureState,
    sublayers: []const PreparedSublayer,
    altitude_km: f64,
    prepared_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) f64 {
    if (self.line_absorbers.len != 0) {
        return self.weightedSpectroscopyEvaluationAtAltitude(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
            sublayers,
            altitude_km,
            state.oxygen_number_density_cm3,
        ).total_sigma_cm2_per_molecule;
    }

    return self.spectroscopySigmaAtAltitudeWithCache(
        wavelength_nm,
        state.temperature_k,
        state.pressure_hpa,
        altitude_km,
        prepared_state,
        profile_cache,
    );
}

fn continuumDensityAtCarrierAltitude(
    self: *const State.PreparedOpticalState,
    sublayers: []const PreparedSublayer,
    altitude_km: f64,
    state: InterpolatedQuadratureState,
) f64 {
    if (self.cross_section_absorbers.len != 0) return 0.0;

    return self.continuumCarrierDensityAtAltitude(
        sublayers,
        altitude_km,
        state.absorber_number_density_cm3,
        state.oxygen_number_density_cm3,
    );
}

fn aerosolReferenceWavelengthAtCarrierAltitude(
    self: *const State.PreparedOpticalState,
    state: InterpolatedQuadratureState,
) f64 {
    if (self.has_aerosol_profile_properties) return state.aerosol_reference_wavelength_nm;
    return self.aerosol_reference_wavelength_nm;
}

fn aerosolAngstromExponentAtCarrierAltitude(
    self: *const State.PreparedOpticalState,
    state: InterpolatedQuadratureState,
) f64 {
    if (self.has_aerosol_profile_properties) return state.aerosol_angstrom_exponent;
    return self.aerosol_angstrom_exponent;
}

pub fn sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalCarrier {
    // sharedOpticalCarrierAtAltitudeWithSpectroscopyCache ---------------------------------------------------  |
    // Evaluates one carrier at an arbitrary altitude by interpolating prepared support rows.                   |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Source-interface and pseudo-spherical routes use this when they need a carrier away from the support   |
    //   grid. It reuses interpolated thermodynamic state and then applies the same sigma*n*1e5 equations as    |
    //   support-row carriers.                                                                                  |
    // -------------------------------------------------------------------------------------------------------  |

    const state = interpolateQuadratureStateAtAltitude(sublayers, altitude_km) orelse return .{};
    const continuum_sigma = continuumSigmaAtWavelength(self, wavelength_nm);
    const prepared_state = State.PreparedOpticalState.preparedStrongLineStateAtAltitude(
        sublayers,
        strong_line_states,
        altitude_km,
    );
    const spectroscopy_sigma = spectroscopySigmaAtCarrierAltitude(
        self,
        wavelength_nm,
        state,
        sublayers,
        altitude_km,
        prepared_state,
        profile_cache,
    );

    var cross_section_density_cm3: f64 = 0.0;
    var cross_section_absorption_optical_depth_per_km: f64 = 0.0;
    for (self.cross_section_absorbers) |cross_section_absorber| {
        const absorber_density_cm3 = State.PreparedOpticalState.interpolatePreparedScalarAtAltitude(
            sublayers,
            cross_section_absorber.number_densities_cm3,
            altitude_km,
        );
        if (absorber_density_cm3 <= 0.0) continue;

        cross_section_density_cm3 += absorber_density_cm3;
        cross_section_absorption_optical_depth_per_km +=
            cross_section_absorber.sigmaAt(
                wavelength_nm,
                state.temperature_k,
                state.pressure_hpa,
            ) *
            absorber_density_cm3 *
            centimeters_per_kilometer;
    }
    const line_absorber_density_cm3 = self.lineSpectroscopyCarrierDensity(
        state.absorber_number_density_cm3,
        state.oxygen_number_density_cm3,
        cross_section_density_cm3,
    );
    const continuum_density_cm3 = continuumDensityAtCarrierAltitude(
        self,
        sublayers,
        altitude_km,
        state,
    );
    const gas_absorption_optical_depth_per_km =
        continuum_sigma *
        continuum_density_cm3 *
        centimeters_per_kilometer +
        cross_section_absorption_optical_depth_per_km +
        spectroscopy_sigma *
            line_absorber_density_cm3 *
            centimeters_per_kilometer;
    const gas_scattering_optical_depth_per_km =
        Rayleigh.crossSectionCm2(wavelength_nm) *
        state.number_density_cm3 *
        centimeters_per_kilometer;
    const cia_optical_depth_per_km =
        self.ciaSigmaAtWavelength(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
        ) *
        state.ciaPairDensityCm6() *
        centimeters_per_kilometer;
    const aerosol_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        state.aerosol_optical_depth_per_km,
        aerosolReferenceWavelengthAtCarrierAltitude(self, state),
        aerosolAngstromExponentAtCarrierAltitude(self, state),
        wavelength_nm,
    );
    const aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * state.aerosol_single_scatter_albedo;

    return .{
        .gas_absorption_optical_depth_per_km = gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
    };
}
