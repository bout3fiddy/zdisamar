const OperationalO2 = @import("operational_o2.zig");
const ReferenceData = @import("../../../input/ReferenceData.zig");
const LineListEval = @import("../../../input/reference/spectroscopy/line_list_eval.zig");
const spline = @import("../../../common/math/interpolation/spline.zig");
const PreparedState = @import("prepared_state.zig");
const Scalar = @import("state_scalar.zig");
const Types = @import("state_types.zig");

const PreparedOpticalState = PreparedState.PreparedOpticalState;
const PreparedSublayer = Types.PreparedSublayer;
const max_spectroscopy_profile_nodes: usize = 256;

// hot path:
//   when: a high-resolution wavelength needs profile-node O2 spectroscopy reuse
//   work: evaluates sigma at profile nodes and builds spline second derivatives for altitude sampling
//   data: spectroscopy profile arrays, prepared weak/strong states, total sigma cache
//   follow: spectroscopyEvaluationAtAltitudeWithCache and support-row carrier evaluation
pub const ProfileNodeSpectroscopyCache = struct {
    node_count: usize = 0,
    total_values: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    total_second: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,

    pub fn init(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
    ) ProfileNodeSpectroscopyCache {
        const line_list = self.spectroscopy_lines orelse return .{};
        if (self.line_absorbers.len != 0 or self.operational_o2_lut.enabled()) return .{};
        const node_count = self.spectroscopy_profile_altitudes_km.len;
        if (node_count < 3 or node_count > max_spectroscopy_profile_nodes) return .{};
        if (self.spectroscopy_profile_pressures_hpa.len != node_count or
            self.spectroscopy_profile_temperatures_k.len != node_count) return .{};
        const prepared_states = if (self.spectroscopy_profile_strong_line_states) |states|
            if (states.len == node_count) states else null
        else
            null;
        const prepared_weak_states = if (self.spectroscopy_profile_weak_line_states) |states|
            if (states.len == node_count) states else null
        else
            null;

        var cache = ProfileNodeSpectroscopyCache{
            .node_count = node_count,
            .total_values = undefined,
            .total_second = undefined,
        };
        const wavelength_window = if (prepared_states != null)
            LineListEval.prepareStrongLineWavelengthWindow(line_list, wavelength_nm)
        else
            null;
        for (0..node_count) |index| {
            const evaluation = if (prepared_states) |states|
                LineListEval.totalSigmaWithPreparedStrongLineStateAndWindow(
                    line_list,
                    wavelength_nm,
                    self.spectroscopy_profile_temperatures_k[index],
                    self.spectroscopy_profile_pressures_hpa[index],
                    &states[index],
                    if (prepared_weak_states) |weak_states| &weak_states[index] else null,
                    &wavelength_window.?,
                )
            else
                LineListEval.totalSigmaAt(
                    line_list,
                    wavelength_nm,
                    self.spectroscopy_profile_temperatures_k[index],
                    self.spectroscopy_profile_pressures_hpa[index],
                );
            cache.total_values[index] = evaluation.total_sigma_cm2_per_molecule;
        }
        spline.endpointSecantSecondDerivatives(
            self.spectroscopy_profile_altitudes_km,
            cache.total_values[0..node_count],
            cache.total_second[0..node_count],
        ) catch return .{};
        return cache;
    }

    // hot path:
    //   when: support-row carrier evaluation samples cached profile spectroscopy at altitude
    //   work: brackets altitude and samples cached endpoint-secant spline sigma
    //   data: altitude grid, cached total sigma values, cached second derivatives
    //   follow: spectroscopyEvaluationAtAltitudeWithCache and carrier_eval support-row fills
    pub fn totalSigmaAtAltitude(
        self: *const ProfileNodeSpectroscopyCache,
        altitudes_km: []const f64,
        altitude_km: f64,
    ) ?f64 {
        if (self.node_count < 3 or altitudes_km.len != self.node_count) return null;
        if (altitude_km < altitudes_km[0] or
            altitude_km > altitudes_km[self.node_count - 1]) return null;

        var klo: usize = 0;
        var khi: usize = self.node_count - 1;
        while (khi - klo > 1) {
            const mid = (khi + klo) / 2;
            if (altitudes_km[mid] > altitude_km) {
                khi = mid;
            } else {
                klo = mid;
            }
        }
        return @max(
            sampleCachedEndpointSecant(
                altitudes_km,
                self.total_values[0..self.node_count],
                self.total_second[0..self.node_count],
                altitude_km,
                klo,
                khi,
            ),
            0.0,
        );
    }

    pub fn evaluationAtAltitude(
        self: *const ProfileNodeSpectroscopyCache,
        altitudes_km: []const f64,
        altitude_km: f64,
    ) ?ReferenceData.SpectroscopyEvaluation {
        const sigma = self.totalSigmaAtAltitude(altitudes_km, altitude_km) orelse return null;
        return spectroscopyEvaluationWithTotalSigma(sigma);
    }
};

fn sampleCachedEndpointSecant(
    x: []const f64,
    y: []const f64,
    second: []const f64,
    target_x: f64,
    klo: usize,
    khi: usize,
) f64 {
    const h = x[khi] - x[klo];
    if (h == 0.0) return y[klo];
    const a = (x[khi] - target_x) / h;
    const b = (target_x - x[klo]) / h;
    return a * y[klo] + b * y[khi] +
        ((a * a * a - a) * second[klo] + (b * b * b - b) * second[khi]) * (h * h) / 6.0;
}

pub fn totalCrossSectionAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
    const continuum = if (self.cross_section_absorbers.len == 0)
        (ReferenceData.CrossSectionTable{
            .points = self.continuum_points,
        }).interpolateSigma(wavelength_nm)
    else
        weightedCrossSectionSigmaAtWavelength(
            self,
            wavelength_nm,
            self.effective_temperature_k,
            self.effective_pressure_hpa,
        );
    const line_sigma = if (self.line_absorbers.len != 0)
        weightedSpectroscopyEvaluationAtWavelength(
            self,
            wavelength_nm,
            self.effective_temperature_k,
            self.effective_pressure_hpa,
        ).total_sigma_cm2_per_molecule
    else if (self.operational_o2_lut.enabled())
        self.operational_o2_lut.sigmaAt(
            wavelength_nm,
            self.effective_temperature_k,
            self.effective_pressure_hpa,
        )
    else if (self.spectroscopy_lines) |line_list|
        line_list.evaluateAt(
            wavelength_nm,
            self.effective_temperature_k,
            self.effective_pressure_hpa,
        ).total_sigma_cm2_per_molecule
    else
        0.0;
    return continuum + line_sigma;
}

pub fn effectiveSpectroscopyEvaluationAtWavelength(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
) ReferenceData.SpectroscopyEvaluation {
    return weightedSpectroscopyEvaluationAtWavelength(
        self,
        wavelength_nm,
        self.effective_temperature_k,
        self.effective_pressure_hpa,
    );
}

pub fn collisionInducedSigmaAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
    if (self.operational_o2o2_lut.enabled()) {
        return self.operational_o2o2_lut.sigmaAt(
            wavelength_nm,
            self.effective_temperature_k,
            self.effective_pressure_hpa,
        );
    }
    if (self.collision_induced_absorption) |cia_table| {
        return cia_table.sigmaAt(wavelength_nm, self.effective_temperature_k);
    }
    return 0.0;
}

fn weightedCrossSectionSigmaAtWavelength(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) f64 {
    if (self.cross_section_absorbers.len == 0) return 0.0;

    var total_weight: f64 = 0.0;
    var weighted_sigma: f64 = 0.0;
    for (self.cross_section_absorbers) |cross_section_absorber| {
        const weight = if (cross_section_absorber.column_density_factor > 0.0)
            cross_section_absorber.column_density_factor
        else
            1.0;
        total_weight += weight;
        weighted_sigma += cross_section_absorber.sigmaAt(
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        ) * weight;
    }
    if (total_weight <= 0.0) return 0.0;
    return weighted_sigma / total_weight;
}

fn spectroscopyEvaluationAtWavelength(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_state: ?*const ReferenceData.StrongLinePreparedState,
) ReferenceData.SpectroscopyEvaluation {
    if (self.line_absorbers.len != 0) {
        return weightedSpectroscopyEvaluationAtWavelength(self, wavelength_nm, temperature_k, pressure_hpa);
    }
    if (self.operational_o2_lut.enabled()) {
        return OperationalO2.operationalO2EvaluationAtWavelength(
            self.operational_o2_lut,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        );
    }
    if (self.spectroscopy_lines) |line_list| {
        return line_list.evaluateAtPrepared(wavelength_nm, temperature_k, pressure_hpa, prepared_state);
    }
    return zeroSpectroscopyEvaluation();
}

pub fn spectroscopySigmaAtWavelength(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_state: ?*const ReferenceData.StrongLinePreparedState,
) f64 {
    if (self.line_absorbers.len != 0) {
        return weightedSpectroscopyEvaluationAtWavelength(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        ).total_sigma_cm2_per_molecule;
    }
    if (self.operational_o2_lut.enabled()) {
        return self.operational_o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
    }
    if (self.spectroscopy_lines) |line_list| {
        return line_list.sigmaAtPrepared(wavelength_nm, temperature_k, pressure_hpa, prepared_state);
    }
    return 0.0;
}

pub fn spectroscopyEvaluationAtAltitude(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    altitude_km: f64,
    prepared_state: ?*const ReferenceData.StrongLinePreparedState,
) ReferenceData.SpectroscopyEvaluation {
    return spectroscopyEvaluationAtAltitudeWithCache(
        self,
        wavelength_nm,
        temperature_k,
        pressure_hpa,
        altitude_km,
        prepared_state,
        null,
    );
}

// hot path:
//   when: support-row carrier evaluation needs spectroscopy at altitude
//   work: resolves cached profile sigma or falls back to profile/direct spectroscopy evaluation
//   data: wavelength, temperature, pressure, altitude, prepared strong-line state, profile cache
//   follow: ProfileNodeSpectroscopyCache.evaluationAtAltitude and spectroscopyEvaluationAtWavelength
pub fn spectroscopyEvaluationAtAltitudeWithCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    altitude_km: f64,
    prepared_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const ProfileNodeSpectroscopyCache,
) ReferenceData.SpectroscopyEvaluation {
    if (profile_cache) |cache| if (cache.evaluationAtAltitude(self.spectroscopy_profile_altitudes_km, altitude_km)) |evaluation| {
        return evaluation;
    };
    if (profileNodeSpectroscopyEvaluationAtAltitude(self, wavelength_nm, altitude_km)) |evaluation| return evaluation;
    return spectroscopyEvaluationAtWavelength(self, wavelength_nm, temperature_k, pressure_hpa, prepared_state);
}

pub fn spectroscopySigmaAtAltitude(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    altitude_km: f64,
    prepared_state: ?*const ReferenceData.StrongLinePreparedState,
) f64 {
    return spectroscopyEvaluationAtAltitudeWithCache(
        self,
        wavelength_nm,
        temperature_k,
        pressure_hpa,
        altitude_km,
        prepared_state,
        null,
    ).total_sigma_cm2_per_molecule;
}

// hot path:
//   when: pseudo-spherical or diagnostic paths need only sigma at altitude
//   work: samples cached profile sigma or delegates to full altitude spectroscopy evaluation
//   data: wavelength, thermodynamic state, altitude, prepared strong-line state, profile cache
//   follow: ProfileNodeSpectroscopyCache.totalSigmaAtAltitude and spectroscopyEvaluationAtAltitudeWithCache
pub fn spectroscopySigmaAtAltitudeWithCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    altitude_km: f64,
    prepared_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const ProfileNodeSpectroscopyCache,
) f64 {
    if (profile_cache) |cache| if (cache.totalSigmaAtAltitude(self.spectroscopy_profile_altitudes_km, altitude_km)) |sigma| {
        return sigma;
    };
    return spectroscopyEvaluationAtAltitudeWithCache(
        self,
        wavelength_nm,
        temperature_k,
        pressure_hpa,
        altitude_km,
        prepared_state,
        profile_cache,
    ).total_sigma_cm2_per_molecule;
}

pub fn preparedStrongLineStateAtAltitude(
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
) ?*const ReferenceData.StrongLinePreparedState {
    const states = strong_line_states orelse return null;
    if (states.len == 0 or states.len != sublayers.len) return null;
    if (states.len == 1) return &states[0];

    if (altitude_km <= sublayers[0].altitude_km) return &states[0];
    if (altitude_km >= sublayers[sublayers.len - 1].altitude_km) return &states[states.len - 1];

    for (sublayers[0 .. sublayers.len - 1], sublayers[1..], 0..) |left, right, index| {
        if (altitude_km > right.altitude_km) continue;
        const left_distance = @abs(altitude_km - left.altitude_km);
        const right_distance = @abs(right.altitude_km - altitude_km);
        return if (left_distance <= right_distance) &states[index] else &states[index + 1];
    }

    return &states[states.len - 1];
}

fn profileNodeSpectroscopyEvaluationAtAltitude(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    altitude_km: f64,
) ?ReferenceData.SpectroscopyEvaluation {
    var cache = ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    return cache.evaluationAtAltitude(self.spectroscopy_profile_altitudes_km, altitude_km);
}

fn zeroSpectroscopyEvaluation() ReferenceData.SpectroscopyEvaluation {
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

fn spectroscopyEvaluationWithTotalSigma(total_sigma_cm2_per_molecule: f64) ReferenceData.SpectroscopyEvaluation {
    var evaluation = zeroSpectroscopyEvaluation();
    evaluation.total_sigma_cm2_per_molecule = total_sigma_cm2_per_molecule;
    return evaluation;
}

pub fn weightedSpectroscopyEvaluationAtWavelength(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
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

    if (self.operational_o2_lut.enabled() and self.oxygen_column_density_factor > 0.0) {
        const o2_evaluation = OperationalO2.operationalO2EvaluationAtWavelength(
            self.operational_o2_lut,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        );
        total_weight += self.oxygen_column_density_factor;
        weighted.weak_line_sigma_cm2_per_molecule +=
            o2_evaluation.weak_line_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
        weighted.strong_line_sigma_cm2_per_molecule +=
            o2_evaluation.strong_line_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
        weighted.line_sigma_cm2_per_molecule +=
            o2_evaluation.line_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
        weighted.line_mixing_sigma_cm2_per_molecule +=
            o2_evaluation.line_mixing_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
        weighted.total_sigma_cm2_per_molecule +=
            o2_evaluation.total_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
            o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * self.oxygen_column_density_factor;
    }

    for (self.line_absorbers) |line_absorber| {
        if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
        const weight = if (line_absorber.column_density_factor > 0.0)
            line_absorber.column_density_factor
        else
            1.0;
        const evaluation = line_absorber.line_list.evaluateAt(wavelength_nm, temperature_k, pressure_hpa);
        total_weight += weight;
        weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * weight;
        weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * weight;
        weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * weight;
        weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * weight;
        weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * weight;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
            evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * weight;
    }

    if (total_weight <= 0.0) {
        return spectroscopyEvaluationAtWavelength(self, wavelength_nm, 0.0, 0.0, null);
    }

    weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
    weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
    weighted.total_sigma_cm2_per_molecule /= total_weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
    return weighted;
}

pub fn weightedSpectroscopyEvaluationAtAltitude(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    sublayers: []const PreparedSublayer,
    altitude_km: f64,
    oxygen_density_cm3: f64,
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

    if (self.operational_o2_lut.enabled() and oxygen_density_cm3 > 0.0) {
        const o2_evaluation = OperationalO2.operationalO2EvaluationAtWavelength(
            self.operational_o2_lut,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        );
        total_weight += oxygen_density_cm3;
        weighted.weak_line_sigma_cm2_per_molecule += o2_evaluation.weak_line_sigma_cm2_per_molecule * oxygen_density_cm3;
        weighted.strong_line_sigma_cm2_per_molecule += o2_evaluation.strong_line_sigma_cm2_per_molecule * oxygen_density_cm3;
        weighted.line_sigma_cm2_per_molecule += o2_evaluation.line_sigma_cm2_per_molecule * oxygen_density_cm3;
        weighted.line_mixing_sigma_cm2_per_molecule += o2_evaluation.line_mixing_sigma_cm2_per_molecule * oxygen_density_cm3;
        weighted.total_sigma_cm2_per_molecule += o2_evaluation.total_sigma_cm2_per_molecule * oxygen_density_cm3;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
            o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * oxygen_density_cm3;
    }

    for (self.line_absorbers) |line_absorber| {
        if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
        const weight = Scalar.interpolatePreparedScalarAtAltitude(
            sublayers,
            line_absorber.number_densities_cm3,
            altitude_km,
        );
        if (weight <= 0.0) continue;

        const evaluation = line_absorber.line_list.evaluateAtPrepared(
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            preparedStrongLineStateAtAltitude(
                sublayers,
                line_absorber.strong_line_states,
                altitude_km,
            ),
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

    if (total_weight <= 0.0) {
        return .{
            .weak_line_sigma_cm2_per_molecule = 0.0,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 0.0,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
    }

    weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
    weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
    weighted.total_sigma_cm2_per_molecule /= total_weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
    return weighted;
}

pub fn ciaSigmaAtWavelength(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) f64 {
    if (self.operational_o2o2_lut.enabled()) {
        return self.operational_o2o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
    }
    if (self.collision_induced_absorption) |cia_table| {
        return cia_table.sigmaAt(wavelength_nm, temperature_k);
    }
    return 0.0;
}
