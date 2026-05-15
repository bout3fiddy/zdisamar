use std::ffi::CStr;

use zdisamar::{
    PreparedO2A,
    api::c::{
        ZdsDiagnosticReport, ZdsSpectrum, zds_context_create, zds_context_destroy, zds_last_error,
        zds_run_spectrum, zds_spectrum_free, zds_spectrum_report,
    },
    forward_model::{
        optical_properties::{PreparedOpticalState, PreparedSublayer},
        radiative_transfer::{
            common_route,
            common_types::{
                DispatchRequest, ExecutionMode, RadiativeTransferControls, ScatteringMode,
            },
        },
    },
    input::{
        o2a_reference::ReferenceSample,
        scene::{DerivativeMode, Scene},
    },
};

#[test]
fn root_o2a_api_exposes_default_prepare_and_session_run_boundaries() {
    let default = zdisamar::default_o2a_input();

    assert_eq!(default.scene_id, "o2a_disamar_reference_python");
    assert_eq!(default.spectral_grid.sample_count, 701);

    let prepared = synthetic_prepared_o2a();
    let product = zdisamar::run_o2a(&prepared).unwrap();

    assert_eq!(product.wavelengths, vec![759.0, 761.0]);
    assert_eq!(product.reflectance, vec![0.23, 0.23]);

    let mut storage = zdisamar::O2ASessionStorage::default();
    zdisamar::warm_o2a_session_storage(&mut storage, &prepared).unwrap();
    let session_product = zdisamar::run_o2a_with_session_storage(&mut storage, &prepared).unwrap();

    assert_eq!(session_product.wavelengths, product.wavelengths);
    assert_eq!(session_product.reflectance, product.reflectance);
    assert!(storage.wavelength_plan_valid);
    assert!(storage.forward_misses_valid);
}

#[test]
fn c_api_context_lifecycle_reports_missing_prepared_case() {
    let ctx = zds_context_create();
    assert!(!ctx.is_null());

    let mut raw = ZdsSpectrum::default();
    assert_ne!(unsafe { zds_run_spectrum(ctx, &mut raw) }, 0);

    let message = unsafe { CStr::from_ptr(zds_last_error(ctx)) }
        .to_str()
        .unwrap();
    assert!(message.contains("no prepared O2A case loaded"));

    unsafe {
        let mut report = ZdsDiagnosticReport::default();
        assert_ne!(zds_spectrum_report(ctx, &raw, &mut report), 0);
        zds_spectrum_free(ctx, &mut raw);
        zds_context_destroy(ctx);
    }
}

fn synthetic_prepared_o2a() -> PreparedO2A {
    let mut scene = Scene::default();
    scene.surface.albedo = 0.23;
    scene.spectral_grid.start_nm = 759.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 2;

    let mut rtm_controls = RadiativeTransferControls {
        scattering: ScatteringMode::None,
        ..RadiativeTransferControls::default()
    };
    rtm_controls.integrate_source_function = false;

    let route = common_route::prepare_route(DispatchRequest {
        regime: scene.observation_model.regime,
        execution_mode: ExecutionMode::Scalar,
        derivative_mode: DerivativeMode::None,
        rtm_controls,
    })
    .unwrap();

    PreparedO2A {
        reference: Vec::<ReferenceSample>::new(),
        scene,
        route,
        prepared: PreparedOpticalState {
            sublayers: Some(vec![PreparedSublayer {
                altitude_km: 1.0,
                path_length_cm: 100_000.0,
                ..PreparedSublayer::default()
            }]),
            ..PreparedOpticalState::default()
        },
    }
}
