use zdisamar::{
    forward_model::radiative_transfer::common_types::ExecutionMode,
    input::{
        atmosphere::ParticlePlacementSemantics,
        geometry,
        instrument::{BuiltinLineShapeKind, SamplingMode},
        o2a_reference::{self, PlanError, PlanSpec},
        scene::DerivativeMode,
    },
};

#[test]
fn default_o2a_reference_input_matches_zig_reference_case() {
    let input = o2a_reference::default_input();

    input.validate().unwrap();
    assert_eq!(input.metadata.id, "disamar_reference_o2a");
    assert_eq!(input.scene_id, "o2a_disamar_reference_python");
    assert_eq!(input.spectral_grid.start_nm, 755.0);
    assert_eq!(input.spectral_grid.end_nm, 776.0);
    assert_eq!(input.spectral_grid.sample_count, 701);
    assert_eq!(input.layer_count, 3);
    assert_eq!(input.sublayer_divisions, 4);
    assert_eq!(input.fit_interval_index_1based, 2);
    assert_eq!(input.intervals.len(), 3);
    assert_eq!(input.intervals[1].top_pressure_hpa, 500.0);
    assert_eq!(input.intervals[1].bottom_pressure_hpa, 520.0);
    assert_eq!(input.geometry.model, geometry::Model::PseudoSpherical);
    assert_eq!(
        input.aerosol.placement.semantics,
        ParticlePlacementSemantics::ExplicitIntervalBounds
    );
    assert_eq!(input.observation.sampling, SamplingMode::Native);
    assert_eq!(
        input.observation.builtin_line_shape,
        BuiltinLineShapeKind::FlatTopN4
    );
    assert_eq!(
        input.observation.adaptive_reference_grid.points_per_fwhm,
        20
    );
    assert_eq!(input.o2.isotopes_sim, vec![1, 2, 3]);
    assert_eq!(input.o2.line_mixing_factor, Some(1.0));
    assert!(input.o2o2.enabled);
    assert_eq!(input.rtm_controls.n_streams, 20);
    assert!(input.rtm_controls.use_spherical_correction);
}

#[test]
fn o2a_plan_spec_resolves_execution_and_derivative_modes() {
    let plan = PlanSpec {
        model_family: "disamar_standard".to_string(),
        transport_solver: "dispatcher".to_string(),
        execution_solver_mode: "scalar".to_string(),
        execution_derivative_mode: "semi_analytical".to_string(),
    };

    plan.validate().unwrap();
    assert_eq!(plan.execution_mode().unwrap(), ExecutionMode::Scalar);
    assert_eq!(
        plan.derivative_mode().unwrap(),
        DerivativeMode::SemiAnalytical
    );
}

#[test]
fn o2a_plan_spec_rejects_unsupported_modes() {
    let mut plan = PlanSpec {
        model_family: "wrong".to_string(),
        transport_solver: "dispatcher".to_string(),
        execution_solver_mode: "scalar".to_string(),
        execution_derivative_mode: "none".to_string(),
    };
    assert_eq!(
        plan.validate().unwrap_err(),
        PlanError::UnsupportedModelFamily
    );

    plan.model_family = "disamar_standard".to_string();
    plan.execution_solver_mode = "parallel".to_string();
    assert_eq!(
        plan.validate().unwrap_err(),
        PlanError::UnsupportedExecutionMode
    );
}
