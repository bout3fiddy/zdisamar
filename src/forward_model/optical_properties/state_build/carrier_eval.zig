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

const phase_coefficient_count = PhaseFunctions.phase_coefficient_count;
const centimeters_per_kilometer = 1.0e5;

// layout(64-bit):
//   size: 56 B, align: 8 B
//   field storage: 56 B across 7 fields; largest: gas_absorption_optical_depth_per_km=8 B, gas_scattering_optical_depth_per_km=8 B, cia_optical_depth_per_km=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 56 B (0.055 KiB); total = per instance * live instance count
pub const SharedOpticalScalars = struct {
    gas_absorption_optical_depth_per_km: f64 = 0.0,
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    cia_optical_depth_per_km: f64 = 0.0,
    aerosol_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,
    cloud_optical_depth_per_km: f64 = 0.0,
    cloud_scattering_optical_depth_per_km: f64 = 0.0,

    pub fn totalScatteringOpticalDepthPerKm(self: SharedOpticalScalars) f64 {
        return self.gas_scattering_optical_depth_per_km +
            self.aerosol_scattering_optical_depth_per_km +
            self.cloud_scattering_optical_depth_per_km;
    }

    pub fn totalOpticalDepthPerKm(self: SharedOpticalScalars) f64 {
        return self.gas_absorption_optical_depth_per_km +
            self.gas_scattering_optical_depth_per_km +
            self.cia_optical_depth_per_km +
            self.aerosol_optical_depth_per_km +
            self.cloud_optical_depth_per_km;
    }
};

// layout(64-bit):
//   size: 56 B, align: 8 B
//   field storage: 56 B across 7 fields; largest: gas_absorption_optical_depth_per_km=8 B, gas_scattering_optical_depth_per_km=8 B, cia_optical_depth_per_km=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 56 B (0.055 KiB); total = per instance * live instance count
pub const SharedOpticalCarrier = struct {
    gas_absorption_optical_depth_per_km: f64 = 0.0,
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    cia_optical_depth_per_km: f64 = 0.0,
    aerosol_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,
    cloud_optical_depth_per_km: f64 = 0.0,
    cloud_scattering_optical_depth_per_km: f64 = 0.0,

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
            .cloud_optical_depth_per_km = self.cloud_optical_depth_per_km,
            .cloud_scattering_optical_depth_per_km = self.cloud_scattering_optical_depth_per_km,
        };
    }
};

// hot path:
//   when: once per high-resolution wavelength and reused across layer/source passes
//   work: memoizes support-row optical-depth scalars for the current wavelength
//   data: valid-bit slice, scalar carrier slice, prepared state, profile spectroscopy cache
//   follow: cachedSupportRowScalarsRef; full carriers are rebuilt only for callers that need phase rows
// layout(64-bit):
//   size: 120 B, align: 8 B
//   field storage: 120 B across 8 fields; largest: cia_coefficients=40 B, support_row_valid=16 B, support_row_scalars=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: profile_cache, support_row_valid, support_row_scalars carry references/descriptors; referenced storage is not included in size
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 120 B (0.117 KiB); total also includes referenced storage above
pub const WavelengthCarrierCache = struct {
    profile_cache: *const SpectroscopyState.ProfileNodeSpectroscopyCache,
    support_row_valid: []bool,
    support_row_scalars: []SharedOpticalScalars,
    continuum_sigma: f64,
    cia_coefficients: ?CiaWavelengthCoefficients,
    rayleigh_cross_section_cm2: f64,
    rayleigh_phase_coefficient2: f64,
    particle_scales: ParticleWavelengthScales,

    pub fn init(
        prepared: *const State.PreparedOpticalState,
        wavelength_nm: f64,
        support_row_valid: []bool,
        support_row_scalars: []SharedOpticalScalars,
        profile_cache: *const SpectroscopyState.ProfileNodeSpectroscopyCache,
    ) WavelengthCarrierCache {
        @memset(support_row_valid, false);
        const continuum_table: ReferenceData.CrossSectionTable = .{ .points = prepared.continuum_points };
        return .{
            .profile_cache = profile_cache,
            .support_row_valid = support_row_valid,
            .support_row_scalars = support_row_scalars,
            .continuum_sigma = if (prepared.cross_section_absorbers.len == 0)
                continuum_table.interpolateSigma(wavelength_nm)
            else
                0.0,
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
        if (global_sublayer_index >= self.support_row_valid.len or
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
        if (!self.support_row_valid[global_sublayer_index]) {
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
            self.support_row_valid[global_sublayer_index] = true;
        }
        return &self.support_row_scalars[global_sublayer_index];
    }
};

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: scale_factor_cm5_per_molecule2=8 B, a0=8 B, a1=8 B, a2=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count
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

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: ksca=8 B, gas_scattering_optical_depth_per_km=8 B, aerosol_scattering_optical_depth_per_km=8 B, cloud_scattering_optical_depth_per_km=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count
pub const PreparedQuadratureCarrier = struct {
    ksca: f64,
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,
    cloud_scattering_optical_depth_per_km: f64 = 0.0,
};

// layout(64-bit):
//   size: 112 B, align: 8 B
//   field storage: 112 B across 10 fields; largest: phase_above=40 B, gas_scattering_optical_depth_per_km=8 B, particle_scattering_optical_depth_above_per_km=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   encoded fields: phase_above stores gas/aerosol/cloud phase weights plus shared phase-row references; phase_max_index_above and phase_max_index_below store Fourier bounds
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 112 B (0.109 KiB); total also includes referenced phase storage above
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

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: 32 B across 4 fields; largest: aerosol_optical_depth_per_km=8 B, aerosol_scattering_optical_depth_per_km=8 B, cloud_optical_depth_per_km=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count
const ParticleBoundaryCarrier = struct {
    aerosol_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,
    cloud_optical_depth_per_km: f64 = 0.0,
    cloud_scattering_optical_depth_per_km: f64 = 0.0,

    fn totalScatteringOpticalDepthPerKm(self: ParticleBoundaryCarrier) f64 {
        return self.aerosol_scattering_optical_depth_per_km + self.cloud_scattering_optical_depth_per_km;
    }
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: aerosol=8 B, cloud=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
const ParticleWavelengthScales = struct {
    aerosol: f64,
    cloud: f64,

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
            .cloud = particleWavelengthScale(
                prepared.cloud_reference_wavelength_nm,
                prepared.cloud_angstrom_exponent,
                wavelength_nm,
            ),
        };
    }
};

// layout(64-bit):
//   size: 80 B, align: 8 B
//   field storage: 80 B across 10 fields; largest: pressure_hpa=8 B, temperature_k=8 B, number_density_cm3=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 80 B (0.078 KiB); total = per instance * live instance count
pub const InterpolatedQuadratureState = struct {
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    cia_pair_density_cm6: f64 = 0.0,
    absorber_number_density_cm3: f64,
    aerosol_optical_depth_per_km: f64,
    cloud_optical_depth_per_km: f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,

    fn ciaPairDensityCm6(self: InterpolatedQuadratureState) f64 {
        return if (self.cia_pair_density_cm6 > 0.0)
            self.cia_pair_density_cm6
        else
            self.oxygen_number_density_cm3 * self.oxygen_number_density_cm3;
    }
};

fn opticalDepthPerKilometer(optical_depth: f64, path_length_cm: f64) f64 {
    const span_km = @max(path_length_cm / centimeters_per_kilometer, 0.0);
    return if (span_km > 0.0) optical_depth / span_km else 0.0;
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
    const aerosol_optical_depth_per_km = scaleParticleDepth(
        opticalDepthPerKilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
        scales.aerosol,
    );
    const cloud_optical_depth_per_km = scaleParticleDepth(
        opticalDepthPerKilometer(sublayer.cloud_optical_depth, sublayer.path_length_cm),
        scales.cloud,
    );
    return .{
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_optical_depth_per_km * sublayer.aerosol_single_scatter_albedo,
        .cloud_optical_depth_per_km = cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = cloud_optical_depth_per_km * sublayer.cloud_single_scatter_albedo,
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

// hot path:
//   when: RTM levels or source interfaces need boundary carriers without a wavelength carrier cache
//   work: evaluates boundary gas and particle carriers from support-row and level geometry
//   data: support sublayers, strong-line states, shared RTM level geometry, profile spectroscopy cache
//   follow: source_interfaces and rtm_quadrature spectroscopy-cache paths
pub fn sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedBoundaryCarrier {
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) return .{};
    const strong_line_state = if (strong_line_states) |states|
        if (boundary_row_index < states.len) &states[boundary_row_index] else null
    else
        null;
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
        particle_above.cloud_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
        &self.cloud_phase_coefficients,
    );
    const phase_below = PhaseFunctions.PhaseMixture.fromScatteringMix(
        rayleigh_phase_coefficient2,
        gas_scattering_optical_depth_per_km,
        particle_below.aerosol_scattering_optical_depth_per_km,
        particle_below.cloud_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
        &self.cloud_phase_coefficients,
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

// hot path:
//   when: RTM levels or source interfaces need boundary carriers for a cached wavelength solve
//   work: reads gas carrier through WavelengthCarrierCache and composes boundary particle fields
//   data: support sublayers, strong-line states, shared RTM level geometry, carrier cache
//   follow: source_interfaces and rtm_quadrature carrier-cache paths
pub fn sharedBoundaryCarrierAtLevelWithCarrierCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    wavelength_cache: *WavelengthCarrierCache,
) SharedBoundaryCarrier {
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) return .{};
    const strong_line_state = if (strong_line_states) |states|
        if (boundary_row_index < states.len) &states[boundary_row_index] else null
    else
        null;
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
        particle_above.cloud_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
        &self.cloud_phase_coefficients,
    );
    const phase_below = PhaseFunctions.PhaseMixture.fromScatteringMix(
        wavelength_cache.rayleigh_phase_coefficient2,
        gas_scattering_optical_depth_per_km,
        particle_below.aerosol_scattering_optical_depth_per_km,
        particle_below.cloud_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
        &self.cloud_phase_coefficients,
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

// hot path:
//   when: shared-grid source interfaces are filled for one wavelength solve
//   work: composes boundary scattering scalars and writes final interface rows
//   data: support-row gas cache, particle boundary rows, prepared phase rows
//   follow: source_interfaces carrier-cache and spectroscopy-cache shared-grid paths
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
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) {
        source_interface.* = .{ .rtm_weight = rtm_weight };
        return;
    }
    const strong_line_state = if (strong_line_states) |states|
        if (boundary_row_index < states.len) &states[boundary_row_index] else null
    else
        null;
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
    const strong_line_state = if (strong_line_states) |states|
        if (boundary_row_index < states.len) &states[boundary_row_index] else null
    else
        null;
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
    const particle_below_total = particle_below.totalScatteringOpticalDepthPerKm();
    const rayleigh_coef2 = rayleigh_phase_coefficient2 orelse
        PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm);
    const phase_above = PhaseFunctions.PhaseMixture.fromScatteringMix(
        rayleigh_coef2,
        gas_scattering_optical_depth_per_km,
        particle_above.aerosol_scattering_optical_depth_per_km,
        particle_above.cloud_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
        &self.cloud_phase_coefficients,
    );
    const phase_below = PhaseFunctions.PhaseMixture.fromScatteringMix(
        rayleigh_coef2,
        gas_scattering_optical_depth_per_km,
        particle_below.aerosol_scattering_optical_depth_per_km,
        particle_below.cloud_scattering_optical_depth_per_km,
        &self.aerosol_phase_coefficients,
        &self.cloud_phase_coefficients,
    );
    source_interface.* = .{
        .source_weight = 0.0,
        .rtm_weight = rtm_weight,
        .gas_ksca = gas_scattering_optical_depth_per_km,
        .particle_ksca_above = particle_above_total,
        .particle_ksca_below = particle_below_total,
        .ksca_above = gas_scattering_optical_depth_per_km + particle_above_total,
        .ksca_below = gas_scattering_optical_depth_per_km + particle_below_total,
        .phase_above = phase_above,
        .phase_max_index_above = phase_above.maxIndex(),
        .phase_max_index_below = phase_below.maxIndex(),
    };
}

// hot path:
//   when: integrated source-function routes fill RTM quadrature levels
//   work: composes boundary scattering scalars and writes final quadrature rows
//   data: support-row gas cache, particle boundary rows, prepared phase rows
//   follow: rtm_quadrature carrier-cache and spectroscopy-cache shared-grid paths
pub fn fillRtmQuadratureLevelAtLevelWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    rtm_level: *transport_common.RtmQuadratureLevel,
) void {
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) {
        fillZeroRtmQuadratureLevel(level_geometry, rtm_level);
        return;
    }
    const strong_line_state = if (strong_line_states) |states|
        if (boundary_row_index < states.len) &states[boundary_row_index] else null
    else
        null;
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
) void {
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) {
        fillZeroRtmQuadratureLevel(level_geometry, rtm_level);
        return;
    }
    const strong_line_state = if (strong_line_states) |states|
        if (boundary_row_index < states.len) &states[boundary_row_index] else null
    else
        null;
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
) void {
    const aerosol_ksca = particle_above.aerosol_scattering_optical_depth_per_km;
    const cloud_ksca = particle_above.cloud_scattering_optical_depth_per_km;
    rtm_level.* = .{
        .altitude_km = level_geometry.altitude_km,
        .weight = level_geometry.weight_km,
        .ksca = gas_scattering_optical_depth_per_km + particle_above.totalScatteringOpticalDepthPerKm(),
        .aerosol_ksca_above_per_km = aerosol_ksca,
        .aerosol_ksca_below_per_km = particle_below.aerosol_scattering_optical_depth_per_km,
    };
    rtm_level.setPhaseMixture(
        rayleigh_phase_coefficient2 orelse PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm),
        gas_scattering_optical_depth_per_km,
        aerosol_ksca,
        cloud_ksca,
    );
}

fn fillZeroRtmQuadratureLevel(
    level_geometry: SharedRtmLevelGeometry,
    rtm_level: *transport_common.RtmQuadratureLevel,
) void {
    rtm_level.* = .{
        .altitude_km = level_geometry.altitude_km,
        .weight = level_geometry.weight_km,
        .ksca = 0.0,
    };
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

// hot path:
//   when: arbitrary RTM or pseudo-spherical levels require interpolated active carriers
//   work: blends below/above support-row carriers with particle interpolation for one altitude
//   data: support sublayers, strong-line states, level geometry, profile spectroscopy cache
//   follow: composeSharedActiveCarrier and altitude-level consumers
pub fn sharedActiveCarrierAtLevelWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalCarrier {
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) return .{};

    const strong_line_state = if (strong_line_states) |states|
        if (boundary_row_index < states.len) &states[boundary_row_index] else null
    else
        null;
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

// hot path:
//   when: shared active carriers interpolate particle state across a support interval
//   work: blends gas, aerosol, cloud, Rayleigh, and phase coefficient fields
//   data: gas carrier, below/above particle carriers, interpolation fraction, wavelength
//   follow: sharedActiveCarrierAtLevelWithSpectroscopyCache and phase coefficient layout
fn composeSharedActiveCarrier(
    gas_carrier: SharedOpticalCarrier,
    particle_below: ParticleBoundaryCarrier,
    particle_above: ParticleBoundaryCarrier,
    fraction: f64,
) SharedOpticalCarrier {
    const clamped_fraction = std.math.clamp(fraction, 0.0, 1.0);
    const left_weight = 1.0 - clamped_fraction;
    const right_weight = clamped_fraction;
    const aerosol_optical_depth_per_km =
        left_weight * particle_below.aerosol_optical_depth_per_km +
        right_weight * particle_above.aerosol_optical_depth_per_km;
    const aerosol_scattering_optical_depth_per_km =
        left_weight * particle_below.aerosol_scattering_optical_depth_per_km +
        right_weight * particle_above.aerosol_scattering_optical_depth_per_km;
    const cloud_optical_depth_per_km =
        left_weight * particle_below.cloud_optical_depth_per_km +
        right_weight * particle_above.cloud_optical_depth_per_km;
    const cloud_scattering_optical_depth_per_km =
        left_weight * particle_below.cloud_scattering_optical_depth_per_km +
        right_weight * particle_above.cloud_scattering_optical_depth_per_km;
    return .{
        .gas_absorption_optical_depth_per_km = gas_carrier.gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_carrier.gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = gas_carrier.cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
        .cloud_optical_depth_per_km = cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = cloud_scattering_optical_depth_per_km,
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
    const left_cloud_per_km = opticalDepthPerKilometer(left.cloud_optical_depth, left.path_length_cm);
    const right_cloud_per_km = opticalDepthPerKilometer(right.cloud_optical_depth, right.path_length_cm);

    return .{
        .pressure_hpa = @max(left_weight * left.pressure_hpa + right_weight * right.pressure_hpa, 0.0),
        .temperature_k = @max(left_weight * left.temperature_k + right_weight * right.temperature_k, 0.0),
        .number_density_cm3 = @max(left_weight * left.number_density_cm3 + right_weight * right.number_density_cm3, 0.0),
        .oxygen_number_density_cm3 = @max(left_weight * left.oxygen_number_density_cm3 + right_weight * right.oxygen_number_density_cm3, 0.0),
        .cia_pair_density_cm6 = @max(left_weight * left.ciaPairDensityCm6() + right_weight * right.ciaPairDensityCm6(), 0.0),
        .absorber_number_density_cm3 = @max(left_weight * left.absorber_number_density_cm3 + right_weight * right.absorber_number_density_cm3, 0.0),
        .aerosol_optical_depth_per_km = @max(left_weight * left_aerosol_per_km + right_weight * right_aerosol_per_km, 0.0),
        .cloud_optical_depth_per_km = @max(left_weight * left_cloud_per_km + right_weight * right_cloud_per_km, 0.0),
        .aerosol_single_scatter_albedo = std.math.clamp(
            left_weight * left.aerosol_single_scatter_albedo + right_weight * right.aerosol_single_scatter_albedo,
            0.0,
            1.0,
        ),
        .cloud_single_scatter_albedo = std.math.clamp(
            left_weight * left.cloud_single_scatter_albedo + right_weight * right.cloud_single_scatter_albedo,
            0.0,
            1.0,
        ),
    };
}

// PUB FOR TEST: kept `pub` so `internal.zig` can re-export this helper for
// tests. Extracting the body would also require lifting
// `interpolateQuadratureStateBetweenSublayers` and `opticalDepthPerKilometer`
// — both consumed elsewhere in this file.
pub fn interpolateQuadratureStateAtAltitude(
    sublayers: []const PreparedSublayer,
    altitude_km: f64,
) ?InterpolatedQuadratureState {
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
            .aerosol_optical_depth_per_km = opticalDepthPerKilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
            .cloud_optical_depth_per_km = opticalDepthPerKilometer(sublayer.cloud_optical_depth, sublayer.path_length_cm),
            .aerosol_single_scatter_albedo = sublayer.aerosol_single_scatter_albedo,
            .cloud_single_scatter_albedo = sublayer.cloud_single_scatter_albedo,
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
        .cloud_scattering_optical_depth_per_km = carrier.cloud_scattering_optical_depth_per_km,
    };
}

// hot path:
//   when: while filling a support-row carrier for an active wavelength
//   work: evaluates and weights active line absorbers into shared carrier spectroscopy fields
//   data: line absorber array, density weighting, profile spectroscopy cache, wavelength
//   follow: layer_spectroscopy.resolveSpectroscopyEvaluation and absorber field layout
fn weightedSpectroscopyEvaluationAtSupportRow(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) ReferenceData.SpectroscopyEvaluation {
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
        weighted.weak_line_sigma_cm2_per_molecule +=
            o2_evaluation.weak_line_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.strong_line_sigma_cm2_per_molecule +=
            o2_evaluation.strong_line_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.line_sigma_cm2_per_molecule +=
            o2_evaluation.line_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.line_mixing_sigma_cm2_per_molecule +=
            o2_evaluation.line_mixing_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.total_sigma_cm2_per_molecule +=
            o2_evaluation.total_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
            o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * sublayer.oxygen_number_density_cm3;
    }

    for (self.line_absorbers) |line_absorber| {
        if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
        if (global_sublayer_index >= line_absorber.number_densities_cm3.len) continue;
        const weight = line_absorber.number_densities_cm3[global_sublayer_index];
        if (weight <= 0.0) continue;
        const prepared_state = if (line_absorber.strong_line_states) |states|
            if (global_sublayer_index < states.len) &states[global_sublayer_index] else null
        else
            null;
        const evaluation = line_absorber.line_list.evaluateAtPrepared(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
            prepared_state,
        );
        total_weight += weight;
        weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * weight;
        weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * weight;
        weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * weight;
        weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * weight;
        weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * weight;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
            evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * weight;
    }

    if (total_weight <= 0.0) return weighted;
    weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
    weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
    weighted.total_sigma_cm2_per_molecule /= total_weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
    return weighted;
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

// hot path:
//   when: support-row carrier evaluation runs without WavelengthCarrierCache
//   work: fills one shared optical carrier from sublayer scalar fields and spectroscopy cache
//   data: support sublayer, strong-line state, wavelength, profile spectroscopy cache
//   follow: fillSharedOpticalScalarsAtSupportRowWithScalarCache
pub fn sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalCarrier {
    const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };
    const continuum_sigma = if (self.cross_section_absorbers.len == 0)
        continuum_table.interpolateSigma(wavelength_nm)
    else
        0.0;
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
    const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };
    const continuum_sigma = if (self.cross_section_absorbers.len == 0)
        continuum_table.interpolateSigma(wavelength_nm)
    else
        0.0;
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

// hot path:
//   when: on a support-row carrier cache miss for the current wavelength
//   work: combines cross-section LUTs, line spectroscopy, CIA/Rayleigh, and particles into scalar depth terms
//   data: scalar support row, active absorbers, cross-section LUTs, scalar carrier output fields
//   follow: weightedSpectroscopyEvaluationAtSupportRow and layer/source scalar consumers
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
    const spectroscopy_sigma = if (self.line_absorbers.len != 0)
        weightedSpectroscopyEvaluationAtSupportRow(
            self,
            wavelength_nm,
            sublayer,
            global_sublayer_index,
        ).total_sigma_cm2_per_molecule
    else
        self.spectroscopySigmaAtAltitudeWithCache(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
            sublayer.altitude_km,
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
    const continuum_density_cm3 = if (self.cross_section_absorbers.len == 0)
        Scalar.continuumCarrierDensityAtSublayer(
            self,
            sublayer,
            global_sublayer_index,
        )
    else
        0.0;
    const gas_absorption_optical_depth_per_km =
        continuum_sigma * continuum_density_cm3 * centimeters_per_kilometer +
        cross_section_absorption_optical_depth_per_km +
        spectroscopy_sigma * line_absorber_density_cm3 * centimeters_per_kilometer;
    const gas_scattering_optical_depth_per_km =
        rayleigh_cross_section_cm2 *
        sublayer.number_density_cm3 *
        centimeters_per_kilometer;
    const cia_sigma_cm5_per_molecule2 = if (cia_coefficients) |coefficients|
        coefficients.sigmaAtTemperature(sublayer.temperature_k)
    else
        self.ciaSigmaAtWavelength(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        );
    const cia_optical_depth_per_km =
        cia_sigma_cm5_per_molecule2 *
        sublayer.ciaPairDensityCm6() *
        centimeters_per_kilometer;
    const aerosol_optical_depth_per_km = scaleParticleDepth(
        opticalDepthPerKilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
        particle_scales.aerosol,
    );
    const cloud_optical_depth_per_km = scaleParticleDepth(
        opticalDepthPerKilometer(sublayer.cloud_optical_depth, sublayer.path_length_cm),
        particle_scales.cloud,
    );
    const aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * sublayer.aerosol_single_scatter_albedo;
    const cloud_scattering_optical_depth_per_km =
        cloud_optical_depth_per_km * sublayer.cloud_single_scatter_albedo;
    out.* = .{
        .gas_absorption_optical_depth_per_km = gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
        .cloud_optical_depth_per_km = cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = cloud_scattering_optical_depth_per_km,
    };
}

fn sharedOpticalCarrierFromScalars(scalars: SharedOpticalScalars) SharedOpticalCarrier {
    return .{
        .gas_absorption_optical_depth_per_km = scalars.gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = scalars.gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = scalars.cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = scalars.aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = scalars.aerosol_scattering_optical_depth_per_km,
        .cloud_optical_depth_per_km = scalars.cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = scalars.cloud_scattering_optical_depth_per_km,
    };
}

// hot path:
//   when: support-row carrier evaluation runs through WavelengthCarrierCache
//   work: returns one full shared carrier from the scalar support-row cache
//   data: support sublayer, global sublayer index, strong-line state, scalar carrier cache
//   follow: WavelengthCarrierCache.cachedSupportRow and sharedOpticalCarrierFromScalars
pub fn sharedOpticalCarrierAtSupportRowWithCarrierCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    wavelength_cache: *WavelengthCarrierCache,
) SharedOpticalCarrier {
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

// hot path:
//   when: source-interface or pseudo-spherical paths request carriers at arbitrary altitude
//   work: interpolates neighboring support rows and evaluates active absorbers at the target altitude
//   data: support-row slices, profile spectroscopy cache, active absorber state, interpolation weights
//   follow: sharedActiveCarrierAtLevelWithSpectroscopyCache and altitude bracket lookup
pub fn sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalCarrier {
    const state = interpolateQuadratureStateAtAltitude(sublayers, altitude_km) orelse return .{};
    const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };
    const continuum_sigma = if (self.cross_section_absorbers.len == 0)
        continuum_table.interpolateSigma(wavelength_nm)
    else
        0.0;
    const prepared_state = State.PreparedOpticalState.preparedStrongLineStateAtAltitude(
        sublayers,
        strong_line_states,
        altitude_km,
    );
    const spectroscopy_sigma = if (self.line_absorbers.len != 0)
        self.weightedSpectroscopyEvaluationAtAltitude(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
            sublayers,
            altitude_km,
            state.oxygen_number_density_cm3,
        ).total_sigma_cm2_per_molecule
    else
        self.spectroscopySigmaAtAltitudeWithCache(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
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
    const continuum_density_cm3 = if (self.cross_section_absorbers.len == 0)
        self.continuumCarrierDensityAtAltitude(
            sublayers,
            altitude_km,
            state.absorber_number_density_cm3,
            state.oxygen_number_density_cm3,
        )
    else
        0.0;
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
        self.aerosol_reference_wavelength_nm,
        self.aerosol_angstrom_exponent,
        wavelength_nm,
    );
    const cloud_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        state.cloud_optical_depth_per_km,
        self.cloud_reference_wavelength_nm,
        self.cloud_angstrom_exponent,
        wavelength_nm,
    );
    const aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * state.aerosol_single_scatter_albedo;
    const cloud_scattering_optical_depth_per_km =
        cloud_optical_depth_per_km * state.cloud_single_scatter_albedo;

    return .{
        .gas_absorption_optical_depth_per_km = gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
        .cloud_optical_depth_per_km = cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = cloud_scattering_optical_depth_per_km,
    };
}
