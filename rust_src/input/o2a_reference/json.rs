use serde_json::{Map, Number, Value, json};

use crate::{
    forward_model::radiative_transfer::common_types::{
        RadiativeTransferControls, RadiativeTransferPerformanceThresholds, ScatteringMode,
    },
    input::{
        atmosphere::{IntervalPlacement, ParticlePlacementSemantics, VerticalInterval},
        geometry,
        instrument::{AdaptiveReferenceGrid, BuiltinLineShapeKind, NoiseModelKind, SamplingMode},
        observation_model::ObservationRegime,
        spectrum::SpectralGrid,
    },
};

use super::types::{
    AerosolSpec, CiaSpec, ExternalAsset, GeometrySpec, InputsSpec, LineGasSpec, Metadata,
    ObservationSpec, OutputKind, OutputRequest, PlanSpec, ResolvedVendorO2ACase, ValidationPolicy,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JsonError {
    Parse,
    Shape,
    UnsupportedValue,
}

type JsonMap = Map<String, Value>;

pub fn parse_input_json(bytes: &[u8]) -> Result<ResolvedVendorO2ACase, JsonError> {
    let value: Value = serde_json::from_slice(bytes).map_err(|_| JsonError::Parse)?;
    parse_input(&value)
}

pub fn render_default_input_json() -> Result<String, JsonError> {
    render_input_json(&super::default_input())
}

pub fn render_input_json(input: &ResolvedVendorO2ACase) -> Result<String, JsonError> {
    let mut rendered =
        serde_json::to_string_pretty(&input_value(input)).map_err(|_| JsonError::Parse)?;
    rendered.push('\n');
    Ok(rendered)
}

fn parse_input(value: &Value) -> Result<ResolvedVendorO2ACase, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "metadata",
            "plan",
            "inputs",
            "scene_id",
            "spectral_grid",
            "layer_count",
            "sublayer_divisions",
            "surface_pressure_hpa",
            "fit_interval_index_1based",
            "intervals",
            "surface_albedo",
            "geometry",
            "aerosol",
            "observation",
            "o2",
            "o2o2",
            "rtm_controls",
            "outputs",
            "validation",
        ],
    )?;
    Ok(ResolvedVendorO2ACase {
        metadata: parse_metadata(required(object, "metadata")?)?,
        plan: parse_plan(required(object, "plan")?)?,
        inputs: parse_inputs(required(object, "inputs")?)?,
        scene_id: string(required(object, "scene_id")?)?.to_string(),
        spectral_grid: parse_spectral_grid(required(object, "spectral_grid")?)?,
        layer_count: u32_value(required(object, "layer_count")?)?,
        sublayer_divisions: u8_value(required(object, "sublayer_divisions")?)?,
        surface_pressure_hpa: f64_value(required(object, "surface_pressure_hpa")?)?,
        fit_interval_index_1based: u32_value(required(object, "fit_interval_index_1based")?)?,
        intervals: array(required(object, "intervals")?)?
            .iter()
            .map(parse_vertical_interval)
            .collect::<Result<Vec<_>, _>>()?,
        surface_albedo: f64_value(required(object, "surface_albedo")?)?,
        geometry: parse_geometry(required(object, "geometry")?)?,
        aerosol: parse_aerosol(required(object, "aerosol")?)?,
        observation: parse_observation(required(object, "observation")?)?,
        o2: parse_o2(required(object, "o2")?)?,
        o2o2: parse_cia(required(object, "o2o2")?)?,
        rtm_controls: parse_rtm_controls(required(object, "rtm_controls")?)?,
        outputs: array(required(object, "outputs")?)?
            .iter()
            .map(parse_output_request)
            .collect::<Result<Vec<_>, _>>()?,
        validation: parse_validation(required(object, "validation")?)?,
    })
}

fn parse_metadata(value: &Value) -> Result<Metadata, JsonError> {
    let object = object(value)?;
    expect_keys(object, &["id", "storage", "description"])?;
    Ok(Metadata {
        id: string(required(object, "id")?)?.to_string(),
        storage: string(required(object, "storage")?)?.to_string(),
        description: string(required(object, "description")?)?.to_string(),
    })
}

fn parse_plan(value: &Value) -> Result<PlanSpec, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "model_family",
            "transport_solver",
            "execution_solver_mode",
            "execution_derivative_mode",
        ],
    )?;
    Ok(PlanSpec {
        model_family: string(required(object, "model_family")?)?.to_string(),
        transport_solver: string(required(object, "transport_solver")?)?.to_string(),
        execution_solver_mode: string(required(object, "execution_solver_mode")?)?.to_string(),
        execution_derivative_mode: string(required(object, "execution_derivative_mode")?)?
            .to_string(),
    })
}

fn parse_inputs(value: &Value) -> Result<InputsSpec, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "atmosphere_profile",
            "vendor_reference_csv",
            "raw_solar_reference",
            "airmass_factor_lut",
        ],
    )?;
    Ok(InputsSpec {
        atmosphere_profile: parse_asset(required(object, "atmosphere_profile")?)?,
        vendor_reference_csv: parse_asset(required(object, "vendor_reference_csv")?)?,
        raw_solar_reference: parse_asset(required(object, "raw_solar_reference")?)?,
        airmass_factor_lut: parse_asset(required(object, "airmass_factor_lut")?)?,
    })
}

fn parse_asset(value: &Value) -> Result<ExternalAsset, JsonError> {
    let object = object(value)?;
    expect_keys(object, &["id", "path", "format"])?;
    Ok(ExternalAsset {
        id: string(required(object, "id")?)?.to_string(),
        path: string(required(object, "path")?)?.to_string(),
        format: string(required(object, "format")?)?.to_string(),
    })
}

fn parse_spectral_grid(value: &Value) -> Result<SpectralGrid, JsonError> {
    let object = object(value)?;
    expect_keys(object, &["start_nm", "end_nm", "sample_count"])?;
    Ok(SpectralGrid {
        start_nm: f64_value(required(object, "start_nm")?)?,
        end_nm: f64_value(required(object, "end_nm")?)?,
        sample_count: u32_value(required(object, "sample_count")?)?,
    })
}

fn parse_vertical_interval(value: &Value) -> Result<VerticalInterval, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "index_1based",
            "top_pressure_hpa",
            "bottom_pressure_hpa",
            "top_altitude_km",
            "bottom_altitude_km",
            "top_pressure_variance_hpa2",
            "bottom_pressure_variance_hpa2",
            "altitude_divisions",
        ],
    )?;
    Ok(VerticalInterval {
        index_1based: u32_value(required(object, "index_1based")?)?,
        top_pressure_hpa: f64_value(required(object, "top_pressure_hpa")?)?,
        bottom_pressure_hpa: f64_value(required(object, "bottom_pressure_hpa")?)?,
        top_altitude_km: optional_f64(object, "top_altitude_km")?.unwrap_or(f64::NAN),
        bottom_altitude_km: optional_f64(object, "bottom_altitude_km")?.unwrap_or(f64::NAN),
        top_pressure_variance_hpa2: optional_f64(object, "top_pressure_variance_hpa2")?
            .unwrap_or(0.0),
        bottom_pressure_variance_hpa2: optional_f64(object, "bottom_pressure_variance_hpa2")?
            .unwrap_or(0.0),
        altitude_divisions: u32_value(required(object, "altitude_divisions")?)?,
    })
}

fn parse_geometry(value: &Value) -> Result<GeometrySpec, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "model",
            "solar_zenith_deg",
            "viewing_zenith_deg",
            "relative_azimuth_deg",
        ],
    )?;
    Ok(GeometrySpec {
        model: parse_geometry_model(string(required(object, "model")?)?)?,
        solar_zenith_deg: f64_value(required(object, "solar_zenith_deg")?)?,
        viewing_zenith_deg: f64_value(required(object, "viewing_zenith_deg")?)?,
        relative_azimuth_deg: f64_value(required(object, "relative_azimuth_deg")?)?,
    })
}

fn parse_aerosol(value: &Value) -> Result<AerosolSpec, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "optical_depth",
            "single_scatter_albedo",
            "asymmetry_factor",
            "angstrom_exponent",
            "reference_wavelength_nm",
            "layer_center_km",
            "layer_width_km",
            "placement",
        ],
    )?;
    Ok(AerosolSpec {
        optical_depth: f64_value(required(object, "optical_depth")?)?,
        single_scatter_albedo: f64_value(required(object, "single_scatter_albedo")?)?,
        asymmetry_factor: f64_value(required(object, "asymmetry_factor")?)?,
        angstrom_exponent: f64_value(required(object, "angstrom_exponent")?)?,
        reference_wavelength_nm: f64_value(required(object, "reference_wavelength_nm")?)?,
        layer_center_km: f64_value(required(object, "layer_center_km")?)?,
        layer_width_km: f64_value(required(object, "layer_width_km")?)?,
        placement: parse_placement(required(object, "placement")?)?,
    })
}

fn parse_placement(value: &Value) -> Result<IntervalPlacement, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "semantics",
            "interval_index_1based",
            "top_pressure_hpa",
            "bottom_pressure_hpa",
            "top_altitude_km",
            "bottom_altitude_km",
        ],
    )?;
    Ok(IntervalPlacement {
        semantics: parse_particle_placement_semantics(string(required(object, "semantics")?)?)?,
        interval_index_1based: u32_value(required(object, "interval_index_1based")?)?,
        top_pressure_hpa: f64_value(required(object, "top_pressure_hpa")?)?,
        bottom_pressure_hpa: f64_value(required(object, "bottom_pressure_hpa")?)?,
        top_altitude_km: optional_f64(object, "top_altitude_km")?.unwrap_or(f64::NAN),
        bottom_altitude_km: optional_f64(object, "bottom_altitude_km")?.unwrap_or(f64::NAN),
    })
}

fn parse_observation(value: &Value) -> Result<ObservationSpec, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "instrument_name",
            "regime",
            "sampling",
            "noise_model",
            "instrument_line_fwhm_nm",
            "builtin_line_shape",
            "high_resolution_step_nm",
            "high_resolution_half_span_nm",
            "adaptive_reference_grid",
            "solar_reference_asset_id",
        ],
    )?;
    Ok(ObservationSpec {
        instrument_name: string(required(object, "instrument_name")?)?.to_string(),
        regime: parse_regime(string(required(object, "regime")?)?)?,
        sampling: SamplingMode::parse(string(required(object, "sampling")?)?)
            .map_err(|_| JsonError::UnsupportedValue)?,
        noise_model: NoiseModelKind::parse(string(required(object, "noise_model")?)?)
            .map_err(|_| JsonError::UnsupportedValue)?,
        instrument_line_fwhm_nm: f64_value(required(object, "instrument_line_fwhm_nm")?)?,
        builtin_line_shape: BuiltinLineShapeKind::parse(string(required(
            object,
            "builtin_line_shape",
        )?)?)
        .map_err(|_| JsonError::UnsupportedValue)?,
        high_resolution_step_nm: f64_value(required(object, "high_resolution_step_nm")?)?,
        high_resolution_half_span_nm: f64_value(required(object, "high_resolution_half_span_nm")?)?,
        adaptive_reference_grid: parse_adaptive_reference_grid(required(
            object,
            "adaptive_reference_grid",
        )?)?,
        solar_reference_asset_id: string(required(object, "solar_reference_asset_id")?)?
            .to_string(),
    })
}

fn parse_adaptive_reference_grid(value: &Value) -> Result<AdaptiveReferenceGrid, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "points_per_fwhm",
            "strong_line_min_divisions",
            "strong_line_max_divisions",
        ],
    )?;
    Ok(AdaptiveReferenceGrid {
        points_per_fwhm: u16_value(required(object, "points_per_fwhm")?)?,
        strong_line_min_divisions: u16_value(required(object, "strong_line_min_divisions")?)?,
        strong_line_max_divisions: u16_value(required(object, "strong_line_max_divisions")?)?,
    })
}

fn parse_o2(value: &Value) -> Result<LineGasSpec, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "line_list_asset",
            "line_mixing_asset",
            "strong_lines_asset",
            "line_mixing_factor",
            "isotopes_sim",
            "threshold_line_sim",
            "cutoff_sim_cm1",
        ],
    )?;
    Ok(LineGasSpec {
        line_list_asset: parse_asset(required(object, "line_list_asset")?)?,
        line_mixing_asset: parse_asset(required(object, "line_mixing_asset")?)?,
        strong_lines_asset: parse_asset(required(object, "strong_lines_asset")?)?,
        line_mixing_factor: optional_f64(object, "line_mixing_factor")?,
        isotopes_sim: array(required(object, "isotopes_sim")?)?
            .iter()
            .map(u8_value)
            .collect::<Result<Vec<_>, _>>()?,
        threshold_line_sim: optional_f64(object, "threshold_line_sim")?,
        cutoff_sim_cm1: optional_f64(object, "cutoff_sim_cm1")?,
    })
}

fn parse_cia(value: &Value) -> Result<CiaSpec, JsonError> {
    let object = object(value)?;
    expect_keys(object, &["enabled", "cia_asset"])?;
    Ok(CiaSpec {
        enabled: bool_value(required(object, "enabled")?)?,
        cia_asset: match object.get("cia_asset") {
            Some(Value::Null) | None => None,
            Some(value) => Some(parse_asset(value)?),
        },
    })
}

fn parse_rtm_controls(value: &Value) -> Result<RadiativeTransferControls, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "scattering",
            "n_streams",
            "use_adding",
            "performance_thresholds",
            "use_spherical_correction",
            "integrate_source_function",
            "renorm_phase_function",
            "stokes_dimension",
        ],
    )?;
    Ok(RadiativeTransferControls {
        scattering: parse_scattering(string(required(object, "scattering")?)?)?,
        n_streams: u16_value(required(object, "n_streams")?)?,
        use_adding: bool_value(required(object, "use_adding")?)?,
        performance_thresholds: parse_thresholds(required(object, "performance_thresholds")?)?,
        use_spherical_correction: bool_value(required(object, "use_spherical_correction")?)?,
        integrate_source_function: bool_value(required(object, "integrate_source_function")?)?,
        renorm_phase_function: bool_value(required(object, "renorm_phase_function")?)?,
        stokes_dimension: u8_value(required(object, "stokes_dimension")?)?,
    })
}

fn parse_thresholds(value: &Value) -> Result<RadiativeTransferPerformanceThresholds, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "num_orders_max",
            "fourier_floor_scalar",
            "fourier_order_cap",
            "fourier_tail_reflectance_epsilon",
            "threshold_conv_first",
            "threshold_conv_mult",
            "threshold_doubl",
            "threshold_mul",
            "phase_function_truncation_threshold",
        ],
    )?;
    Ok(RadiativeTransferPerformanceThresholds {
        num_orders_max: u16_value(required(object, "num_orders_max")?)?,
        fourier_floor_scalar: u16_value(required(object, "fourier_floor_scalar")?)?,
        fourier_order_cap: optional_u16(object, "fourier_order_cap")?,
        fourier_tail_reflectance_epsilon: f64_value(required(
            object,
            "fourier_tail_reflectance_epsilon",
        )?)?,
        threshold_conv_first: f64_value(required(object, "threshold_conv_first")?)?,
        threshold_conv_mult: f64_value(required(object, "threshold_conv_mult")?)?,
        threshold_doubl: f64_value(required(object, "threshold_doubl")?)?,
        threshold_mul: f64_value(required(object, "threshold_mul")?)?,
        phase_function_truncation_threshold: optional_f64(
            object,
            "phase_function_truncation_threshold",
        )?
        .unwrap_or(1.0e-8),
    })
}

fn parse_output_request(value: &Value) -> Result<OutputRequest, JsonError> {
    let object = object(value)?;
    expect_keys(object, &["kind", "path"])?;
    Ok(OutputRequest {
        kind: parse_output_kind(string(required(object, "kind")?)?)?,
        path: string(required(object, "path")?)?.to_string(),
    })
}

fn parse_validation(value: &Value) -> Result<ValidationPolicy, JsonError> {
    let object = object(value)?;
    expect_keys(
        object,
        &[
            "strict_unknown_fields",
            "require_resolved_assets",
            "require_resolved_stage_references",
        ],
    )?;
    Ok(ValidationPolicy {
        strict_unknown_fields: bool_value(required(object, "strict_unknown_fields")?)?,
        require_resolved_assets: bool_value(required(object, "require_resolved_assets")?)?,
        require_resolved_stage_references: bool_value(required(
            object,
            "require_resolved_stage_references",
        )?)?,
    })
}

fn input_value(input: &ResolvedVendorO2ACase) -> Value {
    json!({
        "metadata": metadata_value(&input.metadata),
        "plan": plan_value(&input.plan),
        "inputs": inputs_value(&input.inputs),
        "scene_id": input.scene_id,
        "spectral_grid": spectral_grid_value(input.spectral_grid),
        "layer_count": input.layer_count,
        "sublayer_divisions": input.sublayer_divisions,
        "surface_pressure_hpa": input.surface_pressure_hpa,
        "fit_interval_index_1based": input.fit_interval_index_1based,
        "intervals": input.intervals.iter().map(|interval| vertical_interval_value(*interval)).collect::<Vec<_>>(),
        "surface_albedo": input.surface_albedo,
        "geometry": geometry_value(input.geometry),
        "aerosol": aerosol_value(input.aerosol),
        "observation": observation_value(&input.observation),
        "o2": o2_value(&input.o2),
        "o2o2": cia_value(&input.o2o2),
        "rtm_controls": rtm_controls_value(input.rtm_controls),
        "outputs": input.outputs.iter().map(output_request_value).collect::<Vec<_>>(),
        "validation": validation_value(input.validation),
    })
}

fn metadata_value(metadata: &Metadata) -> Value {
    json!({
        "id": metadata.id,
        "storage": metadata.storage,
        "description": metadata.description,
    })
}

fn plan_value(plan: &PlanSpec) -> Value {
    json!({
        "model_family": plan.model_family,
        "transport_solver": plan.transport_solver,
        "execution_solver_mode": plan.execution_solver_mode,
        "execution_derivative_mode": plan.execution_derivative_mode,
    })
}

fn inputs_value(inputs: &InputsSpec) -> Value {
    json!({
        "atmosphere_profile": asset_value(&inputs.atmosphere_profile),
        "vendor_reference_csv": asset_value(&inputs.vendor_reference_csv),
        "raw_solar_reference": asset_value(&inputs.raw_solar_reference),
        "airmass_factor_lut": asset_value(&inputs.airmass_factor_lut),
    })
}

fn asset_value(asset: &ExternalAsset) -> Value {
    json!({
        "id": asset.id,
        "path": asset.path,
        "format": asset.format,
    })
}

fn spectral_grid_value(grid: SpectralGrid) -> Value {
    json!({
        "start_nm": grid.start_nm,
        "end_nm": grid.end_nm,
        "sample_count": grid.sample_count,
    })
}

fn vertical_interval_value(interval: VerticalInterval) -> Value {
    json!({
        "index_1based": interval.index_1based,
        "top_pressure_hpa": interval.top_pressure_hpa,
        "bottom_pressure_hpa": interval.bottom_pressure_hpa,
        "top_altitude_km": f64_json(interval.top_altitude_km),
        "bottom_altitude_km": f64_json(interval.bottom_altitude_km),
        "top_pressure_variance_hpa2": interval.top_pressure_variance_hpa2,
        "bottom_pressure_variance_hpa2": interval.bottom_pressure_variance_hpa2,
        "altitude_divisions": interval.altitude_divisions,
    })
}

fn geometry_value(geometry: GeometrySpec) -> Value {
    json!({
        "model": geometry_model_label(geometry.model),
        "solar_zenith_deg": geometry.solar_zenith_deg,
        "viewing_zenith_deg": geometry.viewing_zenith_deg,
        "relative_azimuth_deg": geometry.relative_azimuth_deg,
    })
}

fn aerosol_value(aerosol: AerosolSpec) -> Value {
    json!({
        "optical_depth": aerosol.optical_depth,
        "single_scatter_albedo": aerosol.single_scatter_albedo,
        "asymmetry_factor": aerosol.asymmetry_factor,
        "angstrom_exponent": aerosol.angstrom_exponent,
        "reference_wavelength_nm": aerosol.reference_wavelength_nm,
        "layer_center_km": aerosol.layer_center_km,
        "layer_width_km": aerosol.layer_width_km,
        "placement": placement_value(aerosol.placement),
    })
}

fn placement_value(placement: IntervalPlacement) -> Value {
    json!({
        "semantics": particle_placement_label(placement.semantics),
        "interval_index_1based": placement.interval_index_1based,
        "top_pressure_hpa": placement.top_pressure_hpa,
        "bottom_pressure_hpa": placement.bottom_pressure_hpa,
        "top_altitude_km": f64_json(placement.top_altitude_km),
        "bottom_altitude_km": f64_json(placement.bottom_altitude_km),
    })
}

fn observation_value(observation: &ObservationSpec) -> Value {
    json!({
        "instrument_name": observation.instrument_name,
        "regime": regime_label(observation.regime),
        "sampling": observation.sampling.label(),
        "noise_model": observation.noise_model.label(),
        "instrument_line_fwhm_nm": observation.instrument_line_fwhm_nm,
        "builtin_line_shape": builtin_line_shape_label(observation.builtin_line_shape),
        "high_resolution_step_nm": observation.high_resolution_step_nm,
        "high_resolution_half_span_nm": observation.high_resolution_half_span_nm,
        "adaptive_reference_grid": {
            "points_per_fwhm": observation.adaptive_reference_grid.points_per_fwhm,
            "strong_line_min_divisions": observation.adaptive_reference_grid.strong_line_min_divisions,
            "strong_line_max_divisions": observation.adaptive_reference_grid.strong_line_max_divisions,
        },
        "solar_reference_asset_id": observation.solar_reference_asset_id,
    })
}

fn o2_value(o2: &LineGasSpec) -> Value {
    json!({
        "line_list_asset": asset_value(&o2.line_list_asset),
        "line_mixing_asset": asset_value(&o2.line_mixing_asset),
        "strong_lines_asset": asset_value(&o2.strong_lines_asset),
        "line_mixing_factor": optional_f64_json(o2.line_mixing_factor),
        "isotopes_sim": o2.isotopes_sim,
        "threshold_line_sim": optional_f64_json(o2.threshold_line_sim),
        "cutoff_sim_cm1": optional_f64_json(o2.cutoff_sim_cm1),
    })
}

fn cia_value(cia: &CiaSpec) -> Value {
    json!({
        "enabled": cia.enabled,
        "cia_asset": cia.cia_asset.as_ref().map(asset_value),
    })
}

fn rtm_controls_value(controls: RadiativeTransferControls) -> Value {
    json!({
        "scattering": scattering_label(controls.scattering),
        "n_streams": controls.n_streams,
        "use_adding": controls.use_adding,
        "performance_thresholds": thresholds_value(controls.performance_thresholds),
        "use_spherical_correction": controls.use_spherical_correction,
        "integrate_source_function": controls.integrate_source_function,
        "renorm_phase_function": controls.renorm_phase_function,
        "stokes_dimension": controls.stokes_dimension,
    })
}

fn thresholds_value(thresholds: RadiativeTransferPerformanceThresholds) -> Value {
    json!({
        "num_orders_max": thresholds.num_orders_max,
        "fourier_floor_scalar": thresholds.fourier_floor_scalar,
        "fourier_order_cap": thresholds.fourier_order_cap,
        "fourier_tail_reflectance_epsilon": thresholds.fourier_tail_reflectance_epsilon,
        "threshold_conv_first": thresholds.threshold_conv_first,
        "threshold_conv_mult": thresholds.threshold_conv_mult,
        "threshold_doubl": thresholds.threshold_doubl,
        "threshold_mul": thresholds.threshold_mul,
        "phase_function_truncation_threshold": thresholds.phase_function_truncation_threshold,
    })
}

fn output_request_value(output: &OutputRequest) -> Value {
    json!({
        "kind": output_kind_label(output.kind),
        "path": output.path,
    })
}

fn validation_value(validation: ValidationPolicy) -> Value {
    json!({
        "strict_unknown_fields": validation.strict_unknown_fields,
        "require_resolved_assets": validation.require_resolved_assets,
        "require_resolved_stage_references": validation.require_resolved_stage_references,
    })
}

fn object(value: &Value) -> Result<&JsonMap, JsonError> {
    value.as_object().ok_or(JsonError::Shape)
}

fn array(value: &Value) -> Result<&[Value], JsonError> {
    value.as_array().map(Vec::as_slice).ok_or(JsonError::Shape)
}

fn required<'a>(object: &'a JsonMap, key: &str) -> Result<&'a Value, JsonError> {
    object.get(key).ok_or(JsonError::Shape)
}

fn expect_keys(object: &JsonMap, allowed: &[&str]) -> Result<(), JsonError> {
    if object
        .keys()
        .all(|key| allowed.iter().any(|allowed_key| key == allowed_key))
    {
        Ok(())
    } else {
        Err(JsonError::Shape)
    }
}

fn string(value: &Value) -> Result<&str, JsonError> {
    value.as_str().ok_or(JsonError::Shape)
}

fn f64_value(value: &Value) -> Result<f64, JsonError> {
    match value {
        Value::Number(number) => number.as_f64().ok_or(JsonError::Shape),
        Value::String(text) if text.eq_ignore_ascii_case("nan") => Ok(f64::NAN),
        Value::String(text) => text.parse::<f64>().map_err(|_| JsonError::Shape),
        _ => Err(JsonError::Shape),
    }
}

fn optional_f64(object: &JsonMap, key: &str) -> Result<Option<f64>, JsonError> {
    match object.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => f64_value(value).map(Some),
    }
}

fn optional_u16(object: &JsonMap, key: &str) -> Result<Option<u16>, JsonError> {
    match object.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => u16_value(value).map(Some),
    }
}

fn u64_value(value: &Value) -> Result<u64, JsonError> {
    match value {
        Value::Number(number) => number.as_u64().ok_or(JsonError::Shape),
        Value::String(text) => text.parse::<u64>().map_err(|_| JsonError::Shape),
        _ => Err(JsonError::Shape),
    }
}

fn u32_value(value: &Value) -> Result<u32, JsonError> {
    u64_value(value)?.try_into().map_err(|_| JsonError::Shape)
}

fn u16_value(value: &Value) -> Result<u16, JsonError> {
    u64_value(value)?.try_into().map_err(|_| JsonError::Shape)
}

fn u8_value(value: &Value) -> Result<u8, JsonError> {
    u64_value(value)?.try_into().map_err(|_| JsonError::Shape)
}

fn bool_value(value: &Value) -> Result<bool, JsonError> {
    match value {
        Value::Bool(value) => Ok(*value),
        Value::String(text) if text.eq_ignore_ascii_case("true") || text == "1" => Ok(true),
        Value::String(text) if text.eq_ignore_ascii_case("false") || text == "0" => Ok(false),
        Value::Number(number) => Ok(number.as_i64().unwrap_or_default() != 0),
        _ => Err(JsonError::Shape),
    }
}

fn f64_json(value: f64) -> Value {
    if value.is_nan() {
        return Value::String("nan".to_string());
    }
    Value::Number(Number::from_f64(value).unwrap_or_else(|| Number::from(0)))
}

fn optional_f64_json(value: Option<f64>) -> Value {
    value.map_or(Value::Null, f64_json)
}

fn parse_geometry_model(value: &str) -> Result<geometry::Model, JsonError> {
    match value {
        "plane_parallel" => Ok(geometry::Model::PlaneParallel),
        "pseudo_spherical" => Ok(geometry::Model::PseudoSpherical),
        "spherical" => Ok(geometry::Model::Spherical),
        _ => Err(JsonError::UnsupportedValue),
    }
}

fn geometry_model_label(model: geometry::Model) -> &'static str {
    match model {
        geometry::Model::PlaneParallel => "plane_parallel",
        geometry::Model::PseudoSpherical => "pseudo_spherical",
        geometry::Model::Spherical => "spherical",
    }
}

fn parse_particle_placement_semantics(
    value: &str,
) -> Result<ParticlePlacementSemantics, JsonError> {
    match value {
        "none" => Ok(ParticlePlacementSemantics::None),
        "altitude_center_width_approximation" => {
            Ok(ParticlePlacementSemantics::AltitudeCenterWidthApproximation)
        }
        "explicit_interval_bounds" => Ok(ParticlePlacementSemantics::ExplicitIntervalBounds),
        _ => Err(JsonError::UnsupportedValue),
    }
}

fn particle_placement_label(semantics: ParticlePlacementSemantics) -> &'static str {
    match semantics {
        ParticlePlacementSemantics::None => "none",
        ParticlePlacementSemantics::AltitudeCenterWidthApproximation => {
            "altitude_center_width_approximation"
        }
        ParticlePlacementSemantics::ExplicitIntervalBounds => "explicit_interval_bounds",
    }
}

fn parse_regime(value: &str) -> Result<ObservationRegime, JsonError> {
    match value {
        "nadir" => Ok(ObservationRegime::Nadir),
        "limb" => Ok(ObservationRegime::Limb),
        "occultation" => Ok(ObservationRegime::Occultation),
        _ => Err(JsonError::UnsupportedValue),
    }
}

fn regime_label(regime: ObservationRegime) -> &'static str {
    match regime {
        ObservationRegime::Nadir => "nadir",
        ObservationRegime::Limb => "limb",
        ObservationRegime::Occultation => "occultation",
    }
}

fn builtin_line_shape_label(kind: BuiltinLineShapeKind) -> &'static str {
    match kind {
        BuiltinLineShapeKind::Gaussian => "gaussian",
        BuiltinLineShapeKind::FlatTopN4 => "flat_top_n4",
        BuiltinLineShapeKind::TripleFlatTopN4 => "triple_flat_top_n4",
    }
}

fn parse_scattering(value: &str) -> Result<ScatteringMode, JsonError> {
    match value {
        "none" => Ok(ScatteringMode::None),
        "single" => Ok(ScatteringMode::Single),
        "multiple" => Ok(ScatteringMode::Multiple),
        _ => Err(JsonError::UnsupportedValue),
    }
}

fn scattering_label(scattering: ScatteringMode) -> &'static str {
    match scattering {
        ScatteringMode::None => "none",
        ScatteringMode::Single => "single",
        ScatteringMode::Multiple => "multiple",
    }
}

fn parse_output_kind(value: &str) -> Result<OutputKind, JsonError> {
    match value {
        "summary_json" => Ok(OutputKind::SummaryJson),
        "generated_spectrum_csv" => Ok(OutputKind::GeneratedSpectrumCsv),
        _ => Err(JsonError::UnsupportedValue),
    }
}

fn output_kind_label(kind: OutputKind) -> &'static str {
    match kind {
        OutputKind::SummaryJson => "summary_json",
        OutputKind::GeneratedSpectrumCsv => "generated_spectrum_csv",
    }
}
