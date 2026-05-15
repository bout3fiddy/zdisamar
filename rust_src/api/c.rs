use std::{
    ffi::CString,
    os::raw::{c_char, c_int, c_void},
    ptr,
};

use crate::{
    forward_model::jacobian::{self, State},
    input::scene::DerivativeMode,
};

const ZDS_OK: c_int = 0;
const ZDS_FAILURE: c_int = 1;

const NULL_CONTEXT_ERROR: &[u8] = b"zdisamar context is null\0";

#[repr(C)]
pub struct ZdsSpectrum {
    pub len: usize,
    pub wavelength_nm: *const f64,
    pub radiance: *const f64,
    pub irradiance: *const f64,
    pub reflectance: *const f64,
    pub jacobian: *const f64,
    pub jacobian_state_count: usize,
    pub result_handle: *mut c_void,
}

#[repr(C)]
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct ZdsDiagnosticReport {
    pub sample_count: u32,
    pub wavelength_start_nm: f64,
    pub wavelength_end_nm: f64,
    pub mean_radiance: f64,
    pub mean_irradiance: f64,
    pub mean_reflectance: f64,
}

impl Default for ZdsSpectrum {
    fn default() -> Self {
        Self {
            len: 0,
            wavelength_nm: ptr::null(),
            radiance: ptr::null(),
            irradiance: ptr::null(),
            reflectance: ptr::null(),
            jacobian: ptr::null(),
            jacobian_state_count: 0,
            result_handle: ptr::null_mut(),
        }
    }
}

pub struct Context {
    prepared: Option<crate::PreparedO2A>,
    o2a_session_storage: crate::O2ASessionStorage,
    // The box keeps each product address stable while C/Python holds array pointers.
    #[allow(clippy::vec_box)]
    results: Vec<Box<crate::Output>>,
    last_error: CString,
}

impl Default for Context {
    fn default() -> Self {
        Self {
            prepared: None,
            o2a_session_storage: crate::O2ASessionStorage::default(),
            results: Vec::new(),
            last_error: empty_error(),
        }
    }
}

impl Context {
    fn clear_results(&mut self) {
        self.results.clear();
    }

    fn result_for_handle(&self, handle: *const crate::Output) -> Option<&crate::Output> {
        self.results
            .iter()
            .map(Box::as_ref)
            .find(|product| ptr::eq(*product, handle))
    }

    fn set_error(&mut self, message: impl AsRef<str>) {
        self.last_error = c_string_lossy(message.as_ref());
    }

    fn clear_error(&mut self) {
        self.last_error = empty_error();
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn zds_context_create() -> *mut Context {
    Box::into_raw(Box::<Context>::default())
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live, `spectrum` must come from that context, and `out` must be writable.
pub unsafe extern "C" fn zds_spectrum_report(
    ctx: *mut Context,
    spectrum: *const ZdsSpectrum,
    out: *mut ZdsDiagnosticReport,
) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    if spectrum.is_null() {
        return fail(resolved, "null spectrum");
    }
    if out.is_null() {
        return fail(resolved, "null diagnostic report");
    }

    let handle = unsafe { (*spectrum).result_handle.cast::<crate::Output>() };
    if handle.is_null() {
        return fail(resolved, "spectrum is closed");
    }
    let Some(product) = resolved.result_for_handle(handle) else {
        return fail(resolved, "unknown spectrum result");
    };
    let report = crate::report::summary_report_from_product(product);

    unsafe {
        *out = ZdsDiagnosticReport {
            sample_count: report.sample_count,
            wavelength_start_nm: report.wavelength_start_nm,
            wavelength_end_nm: report.wavelength_end_nm,
            mean_radiance: report.mean_radiance,
            mean_irradiance: report.mean_irradiance,
            mean_reflectance: report.mean_reflectance,
        };
    }
    resolved.clear_error();
    ZDS_OK
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be a pointer returned by `zds_context_create` and must not be used again.
pub unsafe extern "C" fn zds_context_destroy(ctx: *mut Context) {
    if ctx.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(ctx));
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn zds_prepare_default_o2a(ctx: *mut Context) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };

    let input = crate::default_o2a_input();
    match crate::prepare_o2a(&input) {
        Ok(prepared) => {
            resolved.clear_results();
            resolved.o2a_session_storage = crate::O2ASessionStorage::default();
            resolved.prepared = Some(prepared);
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(
            resolved,
            format!("failed to prepare default O2A case: {err:?}"),
        ),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn zds_warm_o2a_session(ctx: *mut Context) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    let Some(prepared) = resolved.prepared.as_ref() else {
        return fail(resolved, "no prepared O2A case loaded");
    };

    match crate::warm_o2a_session_storage(&mut resolved.o2a_session_storage, prepared) {
        Ok(()) => {
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(resolved, format!("failed to warm O2A session: {err:?}")),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be a live context pointer and `out` must be valid for writing one `ZdsSpectrum`.
pub unsafe extern "C" fn zds_run_spectrum(ctx: *mut Context, out: *mut ZdsSpectrum) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    if out.is_null() {
        return fail(resolved, "spectrum output pointer is null");
    }
    let Some(prepared) = resolved.prepared.as_ref() else {
        return fail(resolved, "no prepared O2A case loaded");
    };

    match crate::run_o2a_with_session_storage(&mut resolved.o2a_session_storage, prepared) {
        Ok(product) => {
            let mut boxed = Box::new(product);
            let raw_product = boxed.as_mut() as *mut crate::Output;
            unsafe {
                write_spectrum(out, &boxed, raw_product.cast::<c_void>());
            }
            resolved.results.push(boxed);
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(resolved, format!("failed to run spectrum: {err:?}")),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live and `out` must be valid for writing one `ZdsSpectrum`.
pub unsafe extern "C" fn zds_run_spectrum_jacobian(
    ctx: *mut Context,
    out: *mut ZdsSpectrum,
) -> c_int {
    unsafe { run_spectrum_jacobian_for_state_ids(ctx, out, ptr::null(), 0) }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` and `out` must be valid. When `state_count` is nonzero, `state_ids`
/// must point to `state_count` readable state ids.
pub unsafe extern "C" fn zds_run_spectrum_jacobian_for_states(
    ctx: *mut Context,
    out: *mut ZdsSpectrum,
    state_ids: *const u8,
    state_count: usize,
) -> c_int {
    if state_count != 0 && state_ids.is_null() {
        if let Some(resolved) = context_mut(ctx) {
            return fail(resolved, "null Jacobian state ids");
        }
        return ZDS_FAILURE;
    }
    unsafe { run_spectrum_jacobian_for_state_ids(ctx, out, state_ids, state_count) }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live and `out` must point to a `ZdsSpectrum` previously returned by this context.
pub unsafe extern "C" fn zds_spectrum_free(ctx: *mut Context, out: *mut ZdsSpectrum) {
    let Some(resolved) = context_mut(ctx) else {
        return;
    };
    if out.is_null() {
        return;
    }

    let handle = unsafe { (*out).result_handle.cast::<crate::Output>() };
    if handle.is_null() {
        unsafe {
            *out = ZdsSpectrum::default();
        }
        return;
    }

    if let Some(index) = resolved
        .results
        .iter()
        .position(|product| ptr::eq(product.as_ref(), handle))
    {
        drop(resolved.results.swap_remove(index));
    }

    unsafe {
        *out = ZdsSpectrum::default();
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn zds_last_error(ctx: *mut Context) -> *const c_char {
    let Some(resolved) = context_mut(ctx) else {
        return NULL_CONTEXT_ERROR.as_ptr().cast::<c_char>();
    };
    resolved.last_error.as_ptr()
}

fn context_mut(ctx: *mut Context) -> Option<&'static mut Context> {
    if ctx.is_null() {
        None
    } else {
        Some(unsafe { &mut *ctx })
    }
}

fn fail(ctx: &mut Context, message: impl AsRef<str>) -> c_int {
    ctx.set_error(message);
    ZDS_FAILURE
}

unsafe fn run_spectrum_jacobian_for_state_ids(
    ctx: *mut Context,
    out: *mut ZdsSpectrum,
    state_ids: *const u8,
    requested_state_count: usize,
) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    if out.is_null() {
        return fail(resolved, "spectrum output pointer is null");
    }
    let Some(prepared) = resolved.prepared.as_ref() else {
        return fail(resolved, "no prepared O2A case loaded");
    };
    let state_slice = if requested_state_count == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(state_ids, requested_state_count) }
    };
    let derivative_state_mask = match jacobian_state_mask(state_slice) {
        Some(mask) => mask,
        None => return fail(resolved, "unsupported Jacobian state"),
    };

    let mut prepared = prepared.clone();
    prepared.route.derivative_mode = DerivativeMode::SemiAnalytical;
    prepared.route.derivative_state_mask = derivative_state_mask;

    match crate::run_o2a_with_session_storage(&mut resolved.o2a_session_storage, &prepared) {
        Ok(mut product) => {
            let output_state_count = if requested_state_count == 0 {
                jacobian::STATE_COUNT
            } else {
                requested_state_count
            };
            if !state_slice.is_empty()
                && let Err(message) = compact_result_jacobian(&mut product, state_slice)
            {
                return fail(resolved, message);
            }

            let mut boxed = Box::new(product);
            let raw_product = boxed.as_mut() as *mut crate::Output;
            unsafe {
                write_spectrum_with_state_count(
                    out,
                    &boxed,
                    raw_product.cast::<c_void>(),
                    output_state_count,
                );
            }
            resolved.results.push(boxed);
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(
            resolved,
            format!("failed to run spectrum Jacobian: {err:?}"),
        ),
    }
}

unsafe fn write_spectrum(out: *mut ZdsSpectrum, product: &crate::Output, handle: *mut c_void) {
    let state_count = product
        .jacobian
        .as_ref()
        .map_or(0, |_| jacobian::STATE_COUNT);
    unsafe {
        write_spectrum_with_state_count(out, product, handle, state_count);
    }
}

unsafe fn write_spectrum_with_state_count(
    out: *mut ZdsSpectrum,
    product: &crate::Output,
    handle: *mut c_void,
    jacobian_state_count: usize,
) {
    unsafe {
        *out = ZdsSpectrum {
            len: product.wavelengths.len(),
            wavelength_nm: product.wavelengths.as_ptr(),
            radiance: product.radiance.as_ptr(),
            irradiance: product.irradiance.as_ptr(),
            reflectance: product.reflectance.as_ptr(),
            jacobian: product
                .jacobian
                .as_ref()
                .map_or(ptr::null(), |values| values.as_ptr()),
            jacobian_state_count,
            result_handle: handle,
        };
    }
}

fn jacobian_state_from_id(state_id: u8) -> Option<State> {
    match state_id {
        0 => Some(State::SurfaceAlbedo),
        1 => Some(State::AerosolOpticalDepth),
        2 => Some(State::AerosolLayerMidPressureHpa),
        _ => None,
    }
}

fn jacobian_state_mask(state_ids: &[u8]) -> Option<jacobian::StateMask> {
    if state_ids.is_empty() {
        return Some(jacobian::ALL_STATES_MASK);
    }
    let mut mask = 0;
    for &state_id in state_ids {
        let state = jacobian_state_from_id(state_id)?;
        mask |= jacobian::state_mask(state);
    }
    Some(jacobian::sanitized_mask(mask))
}

fn compact_result_jacobian(
    result: &mut crate::Output,
    state_ids: &[u8],
) -> Result<(), &'static str> {
    let Some(full) = result.jacobian.as_ref() else {
        return Err("missing Jacobian");
    };
    if full.len() != result.wavelengths.len() * jacobian::STATE_COUNT {
        return Err("Jacobian shape mismatch");
    }

    let mut compact = Vec::with_capacity(result.wavelengths.len() * state_ids.len());
    for sample_index in 0..result.wavelengths.len() {
        for &state_id in state_ids {
            let Some(state) = jacobian_state_from_id(state_id) else {
                return Err("unsupported Jacobian state");
            };
            compact.push(full[sample_index * jacobian::STATE_COUNT + jacobian::state_index(state)]);
        }
    }
    result.jacobian = Some(compact);
    Ok(())
}

fn empty_error() -> CString {
    CString::new("").expect("empty CString literal is valid")
}

fn c_string_lossy(message: &str) -> CString {
    let sanitized = message.replace('\0', " ");
    CString::new(sanitized).expect("nul bytes were removed")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        forward_model::{
            instrument_grid::InstrumentGridSummary,
            optical_properties::{PreparedOpticalState, PreparedSublayer},
            radiative_transfer::{
                common_route,
                common_types::{
                    DispatchRequest, ExecutionMode, RadiativeTransferControls, ScatteringMode,
                },
            },
        },
        input::{o2a_reference::ReferenceSample, scene::Scene},
    };

    #[test]
    fn spectrum_report_reads_owned_result_handle() {
        let product = crate::Output {
            summary: InstrumentGridSummary {
                sample_count: 2,
                wavelength_start_nm: 760.0,
                wavelength_end_nm: 761.0,
                mean_radiance: 1.0,
                mean_irradiance: 2.0,
                mean_reflectance: 0.5,
                mean_noise_sigma: 0.0,
                mean_jacobian: None,
            },
            wavelengths: vec![760.0, 761.0],
            radiance: vec![1.0, 1.0],
            irradiance: vec![2.0, 2.0],
            reflectance: vec![0.5, 0.5],
            noise_sigma: Vec::new(),
            radiance_noise_sigma: Vec::new(),
            irradiance_noise_sigma: Vec::new(),
            reflectance_noise_sigma: Vec::new(),
            jacobian: None,
            effective_air_mass_factor: 0.0,
            effective_single_scatter_albedo: 0.0,
            effective_temperature_k: 0.0,
            effective_pressure_hpa: 0.0,
            gas_optical_depth: 0.0,
            cia_optical_depth: 0.0,
            aerosol_optical_depth: 0.0,
            cloud_optical_depth: 0.0,
            total_optical_depth: 0.0,
            depolarization_factor: 0.0,
            d_optical_depth_d_temperature: 0.0,
        };
        let mut ctx = Context::default();
        ctx.results.push(Box::new(product));
        let handle = ctx.results[0].as_ref() as *const crate::Output as *mut c_void;
        let spectrum = ZdsSpectrum {
            len: 2,
            wavelength_nm: ctx.results[0].wavelengths.as_ptr(),
            radiance: ctx.results[0].radiance.as_ptr(),
            irradiance: ctx.results[0].irradiance.as_ptr(),
            reflectance: ctx.results[0].reflectance.as_ptr(),
            jacobian: ptr::null(),
            jacobian_state_count: 0,
            result_handle: handle,
        };
        let mut report = ZdsDiagnosticReport::default();

        let status = unsafe { zds_spectrum_report(&mut ctx, &spectrum, &mut report) };

        assert_eq!(status, ZDS_OK);
        assert_eq!(report.sample_count, 2);
        assert_eq!(report.wavelength_start_nm, 760.0);
        assert_eq!(report.wavelength_end_nm, 761.0);
        assert_eq!(report.mean_reflectance, 0.5);
    }

    #[test]
    fn spectrum_jacobian_for_states_compacts_selected_columns() {
        let mut ctx = Context {
            prepared: Some(synthetic_prepared_o2a()),
            ..Context::default()
        };
        let mut spectrum = ZdsSpectrum::default();
        let states = [State::SurfaceAlbedo as u8];

        let status = unsafe {
            zds_run_spectrum_jacobian_for_states(
                &mut ctx,
                &mut spectrum,
                states.as_ptr(),
                states.len(),
            )
        };

        assert_eq!(status, ZDS_OK);
        assert_eq!(spectrum.len, 2);
        assert_eq!(spectrum.jacobian_state_count, 1);
        assert!(!spectrum.jacobian.is_null());
        let jacobian = unsafe { std::slice::from_raw_parts(spectrum.jacobian, spectrum.len) };
        assert!(jacobian.iter().all(|value| value.is_finite()));
        assert!(jacobian.iter().all(|value| *value > 0.0));

        unsafe {
            zds_spectrum_free(&mut ctx, &mut spectrum);
        }
        assert!(spectrum.result_handle.is_null());
    }

    #[test]
    fn spectrum_jacobian_rejects_unknown_state_id() {
        let mut ctx = Context {
            prepared: Some(synthetic_prepared_o2a()),
            ..Context::default()
        };
        let mut spectrum = ZdsSpectrum::default();
        let states = [99_u8];

        let status = unsafe {
            zds_run_spectrum_jacobian_for_states(
                &mut ctx,
                &mut spectrum,
                states.as_ptr(),
                states.len(),
            )
        };

        assert_eq!(status, ZDS_FAILURE);
        assert!(ctx.last_error.to_str().unwrap().contains("unsupported"));
        assert!(spectrum.result_handle.is_null());
    }

    fn synthetic_prepared_o2a() -> crate::PreparedO2A {
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

        crate::PreparedO2A {
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
}
