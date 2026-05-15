pub mod metrics;
pub mod run;
pub mod types;

use crate::{
    forward_model::radiative_transfer::common_types::{
        RadiativeTransferControls, RadiativeTransferPerformanceThresholds, ScatteringMode,
    },
    input::{
        atmosphere::{ParticlePlacementSemantics, VerticalInterval},
        geometry,
        instrument::{AdaptiveReferenceGrid, BuiltinLineShapeKind, NoiseModelKind, SamplingMode},
        observation_model::ObservationRegime,
        spectrum::SpectralGrid,
    },
};

pub use metrics::{
    AssessmentOutcome, AssessmentTrend, AssessmentVerdict, ComparisonMetrics, RangeExtremum,
    TrendState, TrendTolerances, assess_against_baseline, compare_absolute_ceiling,
    compare_higher_is_better, compare_lower_is_better, compute_comparison_metrics,
    interpolate_vector, max_reference_in_range, max_vector_in_range, mean_reference_in_range,
    mean_vector_in_range, min_reference_in_range, min_vector_in_range,
};
pub use run::{
    Error as RunError, Route, build_o2_absorber_set, build_resolved_vendor_o2a_scene,
    build_vendor_trace_gas_spectroscopy_profile, load_climatology_profile, load_reference_samples,
    load_solar_spectrum_samples, prepare_resolved_vendor_o2a_route, reference_spectral_response,
    retain_solar_support,
};
pub use types::{
    AerosolSpec, CiaSpec, ExternalAsset, GeometrySpec, InputsSpec, LineGasSpec, Metadata,
    ObservationSpec, OutputKind, OutputRequest, PlanError, PlanSpec, ReferenceSample,
    ResolvedVendorO2ACase, SolarSpectrumSample, ValidationPolicy,
};

const DEFAULT_ISOTOPES: [u8; 3] = [1, 2, 3];

pub fn default_input() -> ResolvedVendorO2ACase {
    ResolvedVendorO2ACase {
        metadata: Metadata {
            id: "disamar_reference_o2a".to_string(),
            storage: "disamar-reference-o2a".to_string(),
            description: "DISAMAR O2 A reference case for Python and validation.".to_string(),
        },
        plan: PlanSpec {
            model_family: "disamar_standard".to_string(),
            transport_solver: "dispatcher".to_string(),
            execution_solver_mode: "scalar".to_string(),
            execution_derivative_mode: "none".to_string(),
        },
        inputs: InputsSpec {
            atmosphere_profile: asset(
                "atmosphere_profile",
                "data/reference_data/climatologies/vendor_config_o2a_profile.csv",
                "profile_csv",
            ),
            vendor_reference_csv: asset(
                "vendor_reference_csv",
                "data/reference_data/validation/o2a_with_cia_disamar_reference.csv",
                "disamar_o2a_reference_csv",
            ),
            raw_solar_reference: asset(
                "raw_solar_reference",
                "data/reference_data/solar/o2a_solar_reference_753_778.csv",
                "solar_reference_csv",
            ),
            airmass_factor_lut: asset(
                "airmass_factor_lut",
                "data/reference_data/luts/airmass_factor_nadir_demo.csv",
                "csv",
            ),
        },
        scene_id: "o2a_disamar_reference_python".to_string(),
        spectral_grid: SpectralGrid {
            start_nm: 755.0,
            end_nm: 776.0,
            sample_count: 701,
        },
        layer_count: 3,
        sublayer_divisions: 4,
        surface_pressure_hpa: 1013.25,
        fit_interval_index_1based: 2,
        intervals: default_intervals(),
        surface_albedo: 0.2,
        geometry: GeometrySpec {
            model: geometry::Model::PseudoSpherical,
            solar_zenith_deg: 60.0,
            viewing_zenith_deg: 30.0,
            relative_azimuth_deg: 120.0,
        },
        aerosol: AerosolSpec {
            optical_depth: 0.3,
            single_scatter_albedo: 1.0,
            asymmetry_factor: 0.7,
            angstrom_exponent: 0.0,
            reference_wavelength_nm: 550.0,
            layer_center_km: 5.4,
            layer_width_km: 0.4,
            placement: crate::input::atmosphere::IntervalPlacement {
                semantics: ParticlePlacementSemantics::ExplicitIntervalBounds,
                interval_index_1based: 2,
                top_pressure_hpa: 500.0,
                bottom_pressure_hpa: 520.0,
                ..crate::input::atmosphere::IntervalPlacement::default()
            },
        },
        observation: ObservationSpec {
            instrument_name: "disamar-o2a-compare".to_string(),
            regime: ObservationRegime::Nadir,
            sampling: SamplingMode::Native,
            noise_model: NoiseModelKind::None,
            instrument_line_fwhm_nm: 0.38,
            builtin_line_shape: BuiltinLineShapeKind::FlatTopN4,
            high_resolution_step_nm: 0.01,
            high_resolution_half_span_nm: 1.14,
            adaptive_reference_grid: AdaptiveReferenceGrid {
                points_per_fwhm: 20,
                strong_line_min_divisions: 8,
                strong_line_max_divisions: 40,
            },
            solar_reference_asset_id: "raw_solar_reference".to_string(),
        },
        o2: LineGasSpec {
            line_list_asset: asset(
                "o2_hitran",
                "data/reference_data/cross_sections/o2a_hitran_07_hit08_tropomi.par",
                "hitran_par_o2a",
            ),
            line_mixing_asset: asset(
                "o2_line_mixing",
                "data/reference_data/cross_sections/o2a_lisa_rmf.dat",
                "lisa_rmf",
            ),
            strong_lines_asset: asset(
                "o2_strong_lines",
                "data/reference_data/cross_sections/o2a_lisa_sdf.dat",
                "lisa_sdf",
            ),
            line_mixing_factor: Some(1.0),
            isotopes_sim: DEFAULT_ISOTOPES.to_vec(),
            threshold_line_sim: Some(3.0e-5),
            cutoff_sim_cm1: Some(200.0),
        },
        o2o2: CiaSpec {
            enabled: true,
            cia_asset: Some(asset(
                "o2o2_cia",
                "data/reference_data/cross_sections/o2o2_bira_o2a.dat",
                "bira_cia",
            )),
        },
        rtm_controls: RadiativeTransferControls {
            scattering: ScatteringMode::Multiple,
            n_streams: 20,
            use_adding: false,
            performance_thresholds: RadiativeTransferPerformanceThresholds::o2a_default(),
            use_spherical_correction: true,
            integrate_source_function: true,
            renorm_phase_function: true,
            stokes_dimension: 1,
        },
        outputs: Vec::new(),
        validation: ValidationPolicy {
            strict_unknown_fields: true,
            require_resolved_assets: true,
            require_resolved_stage_references: true,
        },
    }
}

fn default_intervals() -> Vec<VerticalInterval> {
    vec![
        VerticalInterval {
            index_1based: 1,
            top_pressure_hpa: 0.3,
            bottom_pressure_hpa: 500.0,
            altitude_divisions: 28,
            ..VerticalInterval::default()
        },
        VerticalInterval {
            index_1based: 2,
            top_pressure_hpa: 500.0,
            bottom_pressure_hpa: 520.0,
            altitude_divisions: 6,
            ..VerticalInterval::default()
        },
        VerticalInterval {
            index_1based: 3,
            top_pressure_hpa: 520.0,
            bottom_pressure_hpa: 1013.25,
            altitude_divisions: 8,
            ..VerticalInterval::default()
        },
    ]
}

fn asset(id: &str, path: &str, format: &str) -> ExternalAsset {
    ExternalAsset {
        id: id.to_string(),
        path: path.to_string(),
        format: format.to_string(),
    }
}
