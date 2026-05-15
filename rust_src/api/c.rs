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
