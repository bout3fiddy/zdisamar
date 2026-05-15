use std::{
    ffi::CString,
    os::raw::{c_char, c_int, c_void},
    ptr,
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

unsafe fn write_spectrum(out: *mut ZdsSpectrum, product: &crate::Output, handle: *mut c_void) {
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
            jacobian_state_count: product
                .jacobian
                .as_ref()
                .map_or(0, |_| crate::forward_model::jacobian::STATE_COUNT),
            result_handle: handle,
        };
    }
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
    use crate::forward_model::instrument_grid::InstrumentGridSummary;

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
}
