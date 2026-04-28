const ReferenceData = @import("../../../input/ReferenceData.zig");
const Context = @import("context.zig").PreparationContext;
const Absorbers = @import("absorbers.zig");
const Spectroscopy = @import("spectroscopy.zig");
const State = @import("state.zig");

const Allocator = @import("std").mem.Allocator;
const oxygen_volume_mixing_ratio = Spectroscopy.default_o2_volume_mixing_ratio;

pub fn continuumCarrierDensity(
    absorbers: *Absorbers.AbsorberBuildState,
    context: *Context,
    write_index: usize,
    absorber_density_cm3: f64,
    o2_density_cm3: f64,
) f64 {
    if (absorbers.owned_cross_section_absorbers.len != 0) return 0.0;
    if (absorbers.owned_line_absorbers.len == 0) return absorber_density_cm3;

    const owner_species = absorbers.continuum_owner_species orelse return absorber_density_cm3;
    if (context.operational_o2_lut.enabled() and owner_species == .o2) return o2_density_cm3;
    for (absorbers.owned_line_absorbers) |line_absorber| {
        if (line_absorber.species != owner_species) continue;
        return line_absorber.number_densities_cm3[write_index];
    }
    return absorber_density_cm3;
}

pub fn resolveSpectroscopyEvaluation(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    write_index: usize,
    density: f64,
    pressure: f64,
    temperature: f64,
    oxygen_mixing_ratio: f64,
    sublayer_path_length_cm: f64,
    absorber_density_cm3: *f64,
) !ReferenceData.SpectroscopyEvaluation {
    if (absorbers.owned_line_absorbers.len != 0) {
        return resolvePreparedLineEvaluation(
            allocator,
            context,
            absorbers,
            write_index,
            density,
            pressure,
            temperature,
            oxygen_mixing_ratio,
            sublayer_path_length_cm,
            absorber_density_cm3,
        );
    }
    return resolveSingleLineEvaluation(
        allocator,
        context,
        absorbers,
        write_index,
        density,
        pressure,
        temperature,
        absorber_density_cm3,
    );
}

fn resolvePreparedLineEvaluation(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    write_index: usize,
    density: f64,
    pressure: f64,
    temperature: f64,
    oxygen_mixing_ratio: f64,
    sublayer_path_length_cm: f64,
    absorber_density_cm3: *f64,
) !ReferenceData.SpectroscopyEvaluation {
    var spectroscopy_weight: f64 = 0.0;
    var weighted: ReferenceData.SpectroscopyEvaluation = .{
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };

    if (context.operational_o2_lut.enabled()) {
        const o2_density_cm3 = density * oxygen_mixing_ratio;
        absorber_density_cm3.* += o2_density_cm3;
        if (o2_density_cm3 > 0.0) {
            const o2_eval = Spectroscopy.operationalO2EvaluationAtWavelength(
                context.operational_o2_lut,
                context.midpoint_nm,
                temperature,
                pressure,
            );
            spectroscopy_weight += o2_density_cm3;
            weighted.weak_line_sigma_cm2_per_molecule += o2_eval.weak_line_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.strong_line_sigma_cm2_per_molecule += o2_eval.strong_line_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.line_sigma_cm2_per_molecule += o2_eval.line_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.line_mixing_sigma_cm2_per_molecule += o2_eval.line_mixing_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.total_sigma_cm2_per_molecule += o2_eval.total_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                o2_eval.d_sigma_d_temperature_cm2_per_molecule_per_k * o2_density_cm3;
        }
    }

    for (absorbers.owned_line_absorbers, absorbers.active_line_absorbers) |*line_absorber, active_absorber| {
        if (context.operational_o2_lut.enabled() and line_absorber.species == .o2) {
            line_absorber.number_densities_cm3[write_index] = 0.0;
            continue;
        }
        const absorber_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
            context.scene,
            line_absorber.species,
            active_absorber.volume_mixing_ratio_profile_ppmv,
            pressure,
            if (line_absorber.species == .o2) oxygen_volume_mixing_ratio else null,
        ) orelse return error.InvalidRequest;
        const density_cm3 = density * absorber_mixing_ratio;
        line_absorber.number_densities_cm3[write_index] = density_cm3;
        absorber_density_cm3.* += density_cm3;
        if (density_cm3 <= 0.0) continue;

        const evaluation = try evaluatePreparedLineAbsorber(
            allocator,
            line_absorber,
            write_index,
            context.midpoint_nm,
            temperature,
            pressure,
        );
        spectroscopy_weight += density_cm3;
        weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * density_cm3;
        weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * density_cm3;
        weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * density_cm3;
        weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * density_cm3;
        weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * density_cm3;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
            evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * density_cm3;
        line_absorber.column_density_factor += density_cm3 * sublayer_path_length_cm;
    }

    if (spectroscopy_weight <= 0.0) {
        return .{
            .line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 0.0,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
    }

    weighted.weak_line_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.strong_line_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.line_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.line_mixing_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.total_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= spectroscopy_weight;
    return weighted;
}

fn evaluatePreparedLineAbsorber(
    allocator: Allocator,
    line_absorber: *State.PreparedLineAbsorber,
    write_index: usize,
    midpoint_nm: f64,
    temperature: f64,
    pressure: f64,
) !ReferenceData.SpectroscopyEvaluation {
    var evaluation = if (line_absorber.strong_line_states) |states| blk: {
        states[write_index] = (try line_absorber.line_list.prepareStrongLineState(
            allocator,
            temperature,
            pressure,
        )).?;
        line_absorber.strong_line_state_initialized.?[write_index] = true;
        line_absorber.strong_line_state_count += 1;
        break :blk line_absorber.line_list.evaluateAtPrepared(
            midpoint_nm,
            temperature,
            pressure,
            &states[write_index],
        );
    } else line_absorber.line_list.evaluateAt(midpoint_nm, temperature, pressure);

    const upper = line_absorber.line_list.evaluateAt(midpoint_nm, temperature + 0.5, pressure);
    const lower = line_absorber.line_list.evaluateAt(midpoint_nm, @max(temperature - 0.5, 150.0), pressure);
    evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k =
        (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / 1.0;
    return evaluation;
}

fn resolveSingleLineEvaluation(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    write_index: usize,
    density: f64,
    pressure: f64,
    temperature: f64,
    absorber_density_cm3: *f64,
) !ReferenceData.SpectroscopyEvaluation {
    const species = absorbers.active_line_species;
    const absorber_mixing_ratio = if (species) |active_species|
        Spectroscopy.speciesMixingRatioAtPressure(
            context.scene,
            active_species,
            if (absorbers.single_active_line_absorber) |line_absorber|
                line_absorber.volume_mixing_ratio_profile_ppmv
            else
                &.{},
            pressure,
            if (active_species == .o2) oxygen_volume_mixing_ratio else null,
        ) orelse oxygen_volume_mixing_ratio
    else
        oxygen_volume_mixing_ratio;
    absorber_density_cm3.* = density * absorber_mixing_ratio;

    if (context.operational_o2_lut.enabled()) {
        const sigma = context.operational_o2_lut.sigmaAt(context.midpoint_nm, temperature, pressure);
        return .{
            .weak_line_sigma_cm2_per_molecule = sigma,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = sigma,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = sigma,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = context.operational_o2_lut.dSigmaDTemperatureAt(
                context.midpoint_nm,
                temperature,
                pressure,
            ),
        };
    }
    if (absorbers.owned_lines) |*line_list| {
        if (absorbers.strong_line_states) |states| {
            states[write_index] = (try line_list.prepareStrongLineState(allocator, temperature, pressure)).?;
            absorbers.strong_line_state_count += 1;
            var evaluation = line_list.evaluateAtPrepared(
                context.midpoint_nm,
                temperature,
                pressure,
                &states[write_index],
            );
            const upper = line_list.evaluateAt(context.midpoint_nm, temperature + 0.5, pressure);
            const lower = line_list.evaluateAt(context.midpoint_nm, @max(temperature - 0.5, 150.0), pressure);
            evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k =
                (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / 1.0;
            return evaluation;
        }
        return line_list.evaluateAt(context.midpoint_nm, temperature, pressure);
    }
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}
