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

#[repr(C)]
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct ZdsAtmosphericBudgetRow {
    pub wavelength_nm: f64,
    pub layer_index: u32,
    pub sublayer_index: u32,
    pub global_sublayer_index: u32,
    pub interval_index_1based: u32,
    pub support_row_kind: u32,
    pub subcolumn_label: u32,
    pub altitude_km: f64,
    pub top_altitude_km: f64,
    pub bottom_altitude_km: f64,
    pub pressure_hpa: f64,
    pub top_pressure_hpa: f64,
    pub bottom_pressure_hpa: f64,
    pub temperature_k: f64,
    pub number_density_cm3: f64,
    pub oxygen_number_density_cm3: f64,
    pub absorber_number_density_cm3: f64,
    pub path_length_cm: f64,
    pub aerosol_fraction: f64,
    pub cloud_fraction: f64,
    pub gas_absorption_optical_depth: f64,
    pub gas_scattering_optical_depth: f64,
    pub cia_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub aerosol_scattering_optical_depth: f64,
    pub aerosol_absorption_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub cloud_scattering_optical_depth: f64,
    pub cloud_absorption_optical_depth: f64,
    pub total_absorption_optical_depth: f64,
    pub total_scattering_optical_depth: f64,
    pub total_optical_depth: f64,
    pub single_scatter_albedo: f64,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ZdsAtmosphericBudget {
    pub len: usize,
    pub rows: *const ZdsAtmosphericBudgetRow,
}

#[repr(C)]
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct ZdsO2LineContributionRow {
    pub wavelength_nm: f64,
    pub profile_node_index: u32,
    pub altitude_km: f64,
    pub row_kind: u32,
    pub status: u32,
    pub line_index: u32,
    pub strong_line_index: u32,
    pub matched_strong_line_index: u32,
    pub gas_index: u16,
    pub isotope_number: u8,
    pub isotopologue_code: i32,
    pub center_wavelength_nm: f64,
    pub center_wavenumber_cm1: f64,
    pub shifted_center_wavenumber_cm1: f64,
    pub line_strength_cm2_per_molecule: f64,
    pub air_half_width_cm1: f64,
    pub pressure_shift_cm1: f64,
    pub lower_state_energy_cm1: f64,
    pub temperature_k: f64,
    pub pressure_hpa: f64,
    pub weak_line_sigma_cm2_per_molecule: f64,
    pub strong_line_sigma_cm2_per_molecule: f64,
    pub line_mixing_sigma_cm2_per_molecule: f64,
    pub total_sigma_cm2_per_molecule: f64,
    pub abs_total_sigma_cm2_per_molecule: f64,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ZdsO2LineContributions {
    pub len: usize,
    pub total_row_count: usize,
    pub truncated: u8,
    pub rows: *const ZdsO2LineContributionRow,
}

#[repr(C)]
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct ZdsInstrumentResponseRow {
    pub nominal_index: i32,
    pub nominal_wavelength_nm: f64,
    pub channel: u32,
    pub sample_index: u32,
    pub support_count: u32,
    pub offset_nm: f64,
    pub support_wavelength_nm: f64,
    pub weight: f64,
    pub support_width_nm: f64,
    pub instrument_fwhm_nm: f64,
    pub high_resolution_step_nm: f64,
    pub high_resolution_half_span_nm: f64,
    pub integration_mode: u32,
    pub response_enabled: u8,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ZdsInstrumentResponse {
    pub len: usize,
    pub rows: *const ZdsInstrumentResponseRow,
}

#[repr(C)]
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct ZdsO2O2CiaRow {
    pub wavelength_nm: f64,
    pub layer_index: u32,
    pub sublayer_index: u32,
    pub global_sublayer_index: u32,
    pub interval_index_1based: u32,
    pub altitude_km: f64,
    pub pressure_hpa: f64,
    pub temperature_k: f64,
    pub oxygen_number_density_cm3: f64,
    pub path_length_cm: f64,
    pub cia_cross_section_cm5_per_molecule2: f64,
    pub cia_optical_depth: f64,
    pub total_absorption_optical_depth: f64,
    pub total_optical_depth: f64,
    pub cia_share_of_total_absorption: f64,
    pub cia_share_of_total_optical_depth: f64,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ZdsO2O2CiaDiagnostics {
    pub len: usize,
    pub rows: *const ZdsO2O2CiaRow,
}

#[repr(C)]
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct ZdsRadiativeTransferDiagnosticRow {
    pub wavelength_nm: f64,
    pub layer_index: u32,
    pub sublayer_index: u32,
    pub global_sublayer_index: u32,
    pub interval_index_1based: u32,
    pub altitude_km: f64,
    pub total_optical_depth: f64,
    pub total_absorption_optical_depth: f64,
    pub total_scattering_optical_depth: f64,
    pub single_scatter_albedo: f64,
    pub cumulative_optical_depth_above: f64,
    pub mid_layer_transmission_proxy: f64,
    pub direct_surface_transmission_proxy: f64,
    pub atmospheric_scattering_source_proxy: f64,
    pub absorption_loss_proxy: f64,
    pub pseudo_spherical_airmass_factor: f64,
    pub n_streams: u32,
    pub integrate_source_function: u8,
    pub final_reflectance: f64,
    pub final_radiance: f64,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ZdsRadiativeTransferDiagnostics {
    pub len: usize,
    pub rows: *const ZdsRadiativeTransferDiagnosticRow,
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

impl Default for ZdsAtmosphericBudget {
    fn default() -> Self {
        Self {
            len: 0,
            rows: ptr::null(),
        }
    }
}

impl Default for ZdsO2LineContributions {
    fn default() -> Self {
        Self {
            len: 0,
            total_row_count: 0,
            truncated: 0,
            rows: ptr::null(),
        }
    }
}

impl Default for ZdsInstrumentResponse {
    fn default() -> Self {
        Self {
            len: 0,
            rows: ptr::null(),
        }
    }
}

impl Default for ZdsO2O2CiaDiagnostics {
    fn default() -> Self {
        Self {
            len: 0,
            rows: ptr::null(),
        }
    }
}

impl Default for ZdsRadiativeTransferDiagnostics {
    fn default() -> Self {
        Self {
            len: 0,
            rows: ptr::null(),
        }
    }
}

pub struct Context {
    prepared: Option<crate::PreparedO2A>,
    o2a_session_storage: crate::O2ASessionStorage,
    // The box keeps each product address stable while C/Python holds array pointers.
    #[allow(clippy::vec_box)]
    results: Vec<Box<crate::Output>>,
    atmospheric_budgets: Vec<Box<[ZdsAtmosphericBudgetRow]>>,
    o2_line_contribution_tables: Vec<Box<[ZdsO2LineContributionRow]>>,
    instrument_responses: Vec<Box<[ZdsInstrumentResponseRow]>>,
    o2_o2_cia_tables: Vec<Box<[ZdsO2O2CiaRow]>>,
    radiative_transfer_tables: Vec<Box<[ZdsRadiativeTransferDiagnosticRow]>>,
    last_error: CString,
}

impl Default for Context {
    fn default() -> Self {
        Self {
            prepared: None,
            o2a_session_storage: crate::O2ASessionStorage::default(),
            results: Vec::new(),
            atmospheric_budgets: Vec::new(),
            o2_line_contribution_tables: Vec::new(),
            instrument_responses: Vec::new(),
            o2_o2_cia_tables: Vec::new(),
            radiative_transfer_tables: Vec::new(),
            last_error: empty_error(),
        }
    }
}

impl Context {
    fn clear_results(&mut self) {
        self.results.clear();
    }

    fn remove_atmospheric_budget(&mut self, rows: *const ZdsAtmosphericBudgetRow) {
        remove_row_table(&mut self.atmospheric_budgets, rows);
    }

    fn remove_o2_line_contribution_table(&mut self, rows: *const ZdsO2LineContributionRow) {
        remove_row_table(&mut self.o2_line_contribution_tables, rows);
    }

    fn remove_instrument_response(&mut self, rows: *const ZdsInstrumentResponseRow) {
        remove_row_table(&mut self.instrument_responses, rows);
    }

    fn remove_o2_o2_cia_table(&mut self, rows: *const ZdsO2O2CiaRow) {
        remove_row_table(&mut self.o2_o2_cia_tables, rows);
    }

    fn remove_radiative_transfer_table(&mut self, rows: *const ZdsRadiativeTransferDiagnosticRow) {
        remove_row_table(&mut self.radiative_transfer_tables, rows);
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
/// # Safety
///
/// `json_ptr` must point to `json_len` readable bytes when `json_len` is nonzero.
pub unsafe extern "C" fn zds_prepare_o2a_json(
    ctx: *mut Context,
    json_ptr: *const u8,
    json_len: usize,
) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    if json_ptr.is_null() {
        return fail(resolved, "null input JSON");
    }
    if json_len == 0 {
        return fail(resolved, "empty input JSON");
    }
    let json = unsafe { std::slice::from_raw_parts(json_ptr, json_len) };
    let input = match crate::o2a::parse_input_json(json) {
        Ok(input) => input,
        Err(err) => return fail(resolved, format!("failed to parse O2A JSON: {err:?}")),
    };

    match crate::prepare_o2a(&input) {
        Ok(prepared) => {
            resolved.clear_results();
            resolved.o2a_session_storage = crate::O2ASessionStorage::default();
            resolved.prepared = Some(prepared);
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(resolved, format!("failed to prepare O2A case: {err:?}")),
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
/// When `out` is non-null, it must point to `capacity` writable bytes. `out_len`
/// may be null or writable for one `usize`.
pub unsafe extern "C" fn zds_default_o2a_input_json(
    ctx: *mut Context,
    out: *mut u8,
    capacity: usize,
    out_len: *mut usize,
) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    let json = match crate::o2a::render_default_input_json() {
        Ok(json) => json,
        Err(err) => {
            return fail(
                resolved,
                format!("failed to render default O2A JSON: {err:?}"),
            );
        }
    };
    if !out_len.is_null() {
        unsafe {
            *out_len = json.len();
        }
    }
    if !out.is_null() {
        if capacity < json.len() + 1 {
            return fail(resolved, "buffer too small");
        }
        unsafe {
            ptr::copy_nonoverlapping(json.as_ptr(), out, json.len());
            *out.add(json.len()) = 0;
        }
    }
    resolved.clear_error();
    ZDS_OK
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
/// `ctx` must be live, `wavelengths_ptr` must point to `wavelength_count`
/// readable `f64` values, and `out` must be valid for writing one table handle.
pub unsafe extern "C" fn zds_atmospheric_budget(
    ctx: *mut Context,
    wavelengths_ptr: *const f64,
    wavelength_count: usize,
    out: *mut ZdsAtmosphericBudget,
) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    if out.is_null() {
        return fail(resolved, "null atmospheric budget");
    }
    let wavelengths = match unsafe { wavelength_slice(wavelengths_ptr, wavelength_count) } {
        Ok(wavelengths) => wavelengths,
        Err(message) => return fail(resolved, message),
    };
    let Some(prepared) = resolved.prepared.as_ref() else {
        return fail(resolved, "no prepared O2A case loaded");
    };

    match crate::report::build_atmospheric_budget(&prepared.scene, &prepared.prepared, wavelengths)
    {
        Ok(native_rows) => {
            let rows = native_rows
                .into_iter()
                .map(copy_atmospheric_budget_row)
                .collect::<Vec<_>>()
                .into_boxed_slice();
            let len = rows.len();
            let rows_ptr = rows.as_ptr();
            resolved.atmospheric_budgets.push(rows);
            unsafe {
                *out = ZdsAtmosphericBudget {
                    len,
                    rows: rows_ptr,
                };
            }
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(
            resolved,
            format!("failed to build atmospheric budget: {err:?}"),
        ),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live, `wavelengths_ptr` must point to `wavelength_count`
/// readable `f64` values, and `out` must be valid for writing one table handle.
pub unsafe extern "C" fn zds_o2_line_contributions(
    ctx: *mut Context,
    wavelengths_ptr: *const f64,
    wavelength_count: usize,
    max_rows: usize,
    out: *mut ZdsO2LineContributions,
) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    if out.is_null() {
        return fail(resolved, "null O2 line contribution table");
    }
    let wavelengths = match unsafe { wavelength_slice(wavelengths_ptr, wavelength_count) } {
        Ok(wavelengths) => wavelengths,
        Err(message) => return fail(resolved, message),
    };
    if max_rows == 0 {
        return fail(resolved, "invalid row limit");
    }
    let Some(prepared) = resolved.prepared.as_ref() else {
        return fail(resolved, "no prepared O2A case loaded");
    };

    match crate::report::build_o2_line_contributions(&prepared.prepared, wavelengths, max_rows) {
        Ok(native_table) => {
            let rows = native_table
                .rows
                .into_iter()
                .map(copy_o2_line_contribution_row)
                .collect::<Vec<_>>()
                .into_boxed_slice();
            let len = rows.len();
            let rows_ptr = rows.as_ptr();
            resolved.o2_line_contribution_tables.push(rows);
            unsafe {
                *out = ZdsO2LineContributions {
                    len,
                    total_row_count: native_table.total_row_count,
                    truncated: u8::from(native_table.truncated),
                    rows: rows_ptr,
                };
            }
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(
            resolved,
            format!("failed to build O2 line contributions: {err:?}"),
        ),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live, `wavelengths_ptr` must point to `wavelength_count`
/// readable `f64` values, and `out` must be valid for writing one table handle.
pub unsafe extern "C" fn zds_instrument_response_sampling(
    ctx: *mut Context,
    wavelengths_ptr: *const f64,
    wavelength_count: usize,
    channel_mask: u32,
    out: *mut ZdsInstrumentResponse,
) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    if out.is_null() {
        return fail(resolved, "null instrument response table");
    }
    let wavelengths = match unsafe { wavelength_slice(wavelengths_ptr, wavelength_count) } {
        Ok(wavelengths) => wavelengths,
        Err(message) => return fail(resolved, message),
    };
    let Some(prepared) = resolved.prepared.as_ref() else {
        return fail(resolved, "no prepared O2A case loaded");
    };

    match crate::report::build_instrument_response(
        &prepared.scene,
        &prepared.prepared,
        wavelengths,
        channel_mask,
    ) {
        Ok(native_rows) => {
            let rows = native_rows
                .into_iter()
                .map(copy_instrument_response_row)
                .collect::<Vec<_>>()
                .into_boxed_slice();
            let len = rows.len();
            let rows_ptr = rows.as_ptr();
            resolved.instrument_responses.push(rows);
            unsafe {
                *out = ZdsInstrumentResponse {
                    len,
                    rows: rows_ptr,
                };
            }
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(
            resolved,
            format!("failed to build instrument response: {err:?}"),
        ),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live, `wavelengths_ptr` must point to `wavelength_count`
/// readable `f64` values, and `out` must be valid for writing one table handle.
pub unsafe extern "C" fn zds_o2_o2_cia_diagnostics(
    ctx: *mut Context,
    wavelengths_ptr: *const f64,
    wavelength_count: usize,
    out: *mut ZdsO2O2CiaDiagnostics,
) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    if out.is_null() {
        return fail(resolved, "null O2-O2 CIA table");
    }
    let wavelengths = match unsafe { wavelength_slice(wavelengths_ptr, wavelength_count) } {
        Ok(wavelengths) => wavelengths,
        Err(message) => return fail(resolved, message),
    };
    let Some(prepared) = resolved.prepared.as_ref() else {
        return fail(resolved, "no prepared O2A case loaded");
    };

    match crate::report::build_o2_o2_cia(&prepared.scene, &prepared.prepared, wavelengths) {
        Ok(native_rows) => {
            let rows = native_rows
                .into_iter()
                .map(copy_o2_o2_cia_row)
                .collect::<Vec<_>>()
                .into_boxed_slice();
            let len = rows.len();
            let rows_ptr = rows.as_ptr();
            resolved.o2_o2_cia_tables.push(rows);
            unsafe {
                *out = ZdsO2O2CiaDiagnostics {
                    len,
                    rows: rows_ptr,
                };
            }
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(
            resolved,
            format!("failed to build O2-O2 CIA diagnostics: {err:?}"),
        ),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live, `wavelengths_ptr` must point to `wavelength_count`
/// readable `f64` values, `spectrum` may be null or a spectrum returned by this
/// context, and `out` must be valid for writing one table handle.
pub unsafe extern "C" fn zds_radiative_transfer_diagnostics(
    ctx: *mut Context,
    wavelengths_ptr: *const f64,
    wavelength_count: usize,
    spectrum: *const ZdsSpectrum,
    out: *mut ZdsRadiativeTransferDiagnostics,
) -> c_int {
    let Some(resolved) = context_mut(ctx) else {
        return ZDS_FAILURE;
    };
    if out.is_null() {
        return fail(resolved, "null radiative-transfer table");
    }
    let wavelengths = match unsafe { wavelength_slice(wavelengths_ptr, wavelength_count) } {
        Ok(wavelengths) => wavelengths,
        Err(message) => return fail(resolved, message),
    };
    let Some(prepared) = resolved.prepared.as_ref() else {
        return fail(resolved, "no prepared O2A case loaded");
    };
    let spectrum_view = match unsafe { spectrum_view(resolved, spectrum) } {
        Ok(view) => view,
        Err(message) => return fail(resolved, message),
    };

    match crate::report::build_radiative_transfer_diagnostics(
        &prepared.scene,
        &prepared.prepared,
        prepared.route,
        wavelengths,
        spectrum_view,
    ) {
        Ok(native_rows) => {
            let rows = native_rows
                .into_iter()
                .map(copy_radiative_transfer_diagnostic_row)
                .collect::<Vec<_>>()
                .into_boxed_slice();
            let len = rows.len();
            let rows_ptr = rows.as_ptr();
            resolved.radiative_transfer_tables.push(rows);
            unsafe {
                *out = ZdsRadiativeTransferDiagnostics {
                    len,
                    rows: rows_ptr,
                };
            }
            resolved.clear_error();
            ZDS_OK
        }
        Err(err) => fail(
            resolved,
            format!("failed to build radiative-transfer diagnostics: {err:?}"),
        ),
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
/// # Safety
///
/// `ctx` must be live and `out` must point to a table previously returned by this context.
pub unsafe extern "C" fn zds_atmospheric_budget_free(
    ctx: *mut Context,
    out: *mut ZdsAtmosphericBudget,
) {
    let Some(resolved) = context_mut(ctx) else {
        return;
    };
    if out.is_null() {
        return;
    }

    let rows = unsafe { (*out).rows };
    resolved.remove_atmospheric_budget(rows);
    unsafe {
        *out = ZdsAtmosphericBudget::default();
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live and `out` must point to a table previously returned by this context.
pub unsafe extern "C" fn zds_o2_line_contributions_free(
    ctx: *mut Context,
    out: *mut ZdsO2LineContributions,
) {
    let Some(resolved) = context_mut(ctx) else {
        return;
    };
    if out.is_null() {
        return;
    }

    let rows = unsafe { (*out).rows };
    resolved.remove_o2_line_contribution_table(rows);
    unsafe {
        *out = ZdsO2LineContributions::default();
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live and `out` must point to a table previously returned by this context.
pub unsafe extern "C" fn zds_instrument_response_free(
    ctx: *mut Context,
    out: *mut ZdsInstrumentResponse,
) {
    let Some(resolved) = context_mut(ctx) else {
        return;
    };
    if out.is_null() {
        return;
    }

    let rows = unsafe { (*out).rows };
    resolved.remove_instrument_response(rows);
    unsafe {
        *out = ZdsInstrumentResponse::default();
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live and `out` must point to a table previously returned by this context.
pub unsafe extern "C" fn zds_o2_o2_cia_diagnostics_free(
    ctx: *mut Context,
    out: *mut ZdsO2O2CiaDiagnostics,
) {
    let Some(resolved) = context_mut(ctx) else {
        return;
    };
    if out.is_null() {
        return;
    }

    let rows = unsafe { (*out).rows };
    resolved.remove_o2_o2_cia_table(rows);
    unsafe {
        *out = ZdsO2O2CiaDiagnostics::default();
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ctx` must be live and `out` must point to a table previously returned by this context.
pub unsafe extern "C" fn zds_radiative_transfer_diagnostics_free(
    ctx: *mut Context,
    out: *mut ZdsRadiativeTransferDiagnostics,
) {
    let Some(resolved) = context_mut(ctx) else {
        return;
    };
    if out.is_null() {
        return;
    }

    let rows = unsafe { (*out).rows };
    resolved.remove_radiative_transfer_table(rows);
    unsafe {
        *out = ZdsRadiativeTransferDiagnostics::default();
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

unsafe fn wavelength_slice<'a>(
    wavelengths_ptr: *const f64,
    wavelength_count: usize,
) -> Result<&'a [f64], &'static str> {
    if wavelengths_ptr.is_null() {
        return Err("null wavelengths");
    }
    if wavelength_count == 0 {
        return Err("empty wavelengths");
    }
    Ok(unsafe { std::slice::from_raw_parts(wavelengths_ptr, wavelength_count) })
}

unsafe fn spectrum_view<'a>(
    ctx: &'a Context,
    spectrum: *const ZdsSpectrum,
) -> Result<Option<crate::RadiativeTransferSpectrumView<'a>>, &'static str> {
    if spectrum.is_null() {
        return Ok(None);
    }
    let handle = unsafe { (*spectrum).result_handle.cast::<crate::Output>() };
    if handle.is_null() {
        return Err("spectrum is closed");
    }
    let Some(product) = ctx.result_for_handle(handle) else {
        return Err("unknown spectrum result");
    };
    Ok(Some(crate::RadiativeTransferSpectrumView {
        wavelength_nm: &product.wavelengths,
        reflectance: &product.reflectance,
        radiance: &product.radiance,
    }))
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

fn remove_row_table<Row>(tables: &mut Vec<Box<[Row]>>, rows: *const Row) {
    if rows.is_null() {
        return;
    }
    if let Some(index) = tables.iter().position(|stored| stored.as_ptr() == rows) {
        drop(tables.swap_remove(index));
    }
}

fn copy_atmospheric_budget_row(row: crate::AtmosphericBudgetRow) -> ZdsAtmosphericBudgetRow {
    ZdsAtmosphericBudgetRow {
        wavelength_nm: row.wavelength_nm,
        layer_index: row.layer_index,
        sublayer_index: row.sublayer_index,
        global_sublayer_index: row.global_sublayer_index,
        interval_index_1based: row.interval_index_1based,
        support_row_kind: row.support_row_kind as u32,
        subcolumn_label: row.subcolumn_label as u32,
        altitude_km: row.altitude_km,
        top_altitude_km: row.top_altitude_km,
        bottom_altitude_km: row.bottom_altitude_km,
        pressure_hpa: row.pressure_hpa,
        top_pressure_hpa: row.top_pressure_hpa,
        bottom_pressure_hpa: row.bottom_pressure_hpa,
        temperature_k: row.temperature_k,
        number_density_cm3: row.number_density_cm3,
        oxygen_number_density_cm3: row.oxygen_number_density_cm3,
        absorber_number_density_cm3: row.absorber_number_density_cm3,
        path_length_cm: row.path_length_cm,
        aerosol_fraction: row.aerosol_fraction,
        cloud_fraction: row.cloud_fraction,
        gas_absorption_optical_depth: row.gas_absorption_optical_depth,
        gas_scattering_optical_depth: row.gas_scattering_optical_depth,
        cia_optical_depth: row.cia_optical_depth,
        aerosol_optical_depth: row.aerosol_optical_depth,
        aerosol_scattering_optical_depth: row.aerosol_scattering_optical_depth,
        aerosol_absorption_optical_depth: row.aerosol_absorption_optical_depth,
        cloud_optical_depth: row.cloud_optical_depth,
        cloud_scattering_optical_depth: row.cloud_scattering_optical_depth,
        cloud_absorption_optical_depth: row.cloud_absorption_optical_depth,
        total_absorption_optical_depth: row.total_absorption_optical_depth,
        total_scattering_optical_depth: row.total_scattering_optical_depth,
        total_optical_depth: row.total_optical_depth,
        single_scatter_albedo: row.single_scatter_albedo,
    }
}

fn copy_o2_line_contribution_row(row: crate::O2LineContributionRow) -> ZdsO2LineContributionRow {
    ZdsO2LineContributionRow {
        wavelength_nm: row.wavelength_nm,
        profile_node_index: row.profile_node_index,
        altitude_km: row.altitude_km,
        row_kind: row.row_kind as u32,
        status: row.status as u32,
        line_index: row.line_index,
        strong_line_index: row.strong_line_index,
        matched_strong_line_index: row.matched_strong_line_index,
        gas_index: row.gas_index,
        isotope_number: row.isotope_number,
        isotopologue_code: row.isotopologue_code,
        center_wavelength_nm: row.center_wavelength_nm,
        center_wavenumber_cm1: row.center_wavenumber_cm1,
        shifted_center_wavenumber_cm1: row.shifted_center_wavenumber_cm1,
        line_strength_cm2_per_molecule: row.line_strength_cm2_per_molecule,
        air_half_width_cm1: row.air_half_width_cm1,
        pressure_shift_cm1: row.pressure_shift_cm1,
        lower_state_energy_cm1: row.lower_state_energy_cm1,
        temperature_k: row.temperature_k,
        pressure_hpa: row.pressure_hpa,
        weak_line_sigma_cm2_per_molecule: row.weak_line_sigma_cm2_per_molecule,
        strong_line_sigma_cm2_per_molecule: row.strong_line_sigma_cm2_per_molecule,
        line_mixing_sigma_cm2_per_molecule: row.line_mixing_sigma_cm2_per_molecule,
        total_sigma_cm2_per_molecule: row.total_sigma_cm2_per_molecule,
        abs_total_sigma_cm2_per_molecule: row.abs_total_sigma_cm2_per_molecule,
    }
}

fn copy_instrument_response_row(row: crate::InstrumentResponseRow) -> ZdsInstrumentResponseRow {
    ZdsInstrumentResponseRow {
        nominal_index: row.nominal_index,
        nominal_wavelength_nm: row.nominal_wavelength_nm,
        channel: row.channel,
        sample_index: row.sample_index,
        support_count: row.support_count,
        offset_nm: row.offset_nm,
        support_wavelength_nm: row.support_wavelength_nm,
        weight: row.weight,
        support_width_nm: row.support_width_nm,
        instrument_fwhm_nm: row.instrument_fwhm_nm,
        high_resolution_step_nm: row.high_resolution_step_nm,
        high_resolution_half_span_nm: row.high_resolution_half_span_nm,
        integration_mode: row.integration_mode,
        response_enabled: row.response_enabled,
    }
}

fn copy_o2_o2_cia_row(row: crate::O2O2CiaRow) -> ZdsO2O2CiaRow {
    ZdsO2O2CiaRow {
        wavelength_nm: row.wavelength_nm,
        layer_index: row.layer_index,
        sublayer_index: row.sublayer_index,
        global_sublayer_index: row.global_sublayer_index,
        interval_index_1based: row.interval_index_1based,
        altitude_km: row.altitude_km,
        pressure_hpa: row.pressure_hpa,
        temperature_k: row.temperature_k,
        oxygen_number_density_cm3: row.oxygen_number_density_cm3,
        path_length_cm: row.path_length_cm,
        cia_cross_section_cm5_per_molecule2: row.cia_cross_section_cm5_per_molecule2,
        cia_optical_depth: row.cia_optical_depth,
        total_absorption_optical_depth: row.total_absorption_optical_depth,
        total_optical_depth: row.total_optical_depth,
        cia_share_of_total_absorption: row.cia_share_of_total_absorption,
        cia_share_of_total_optical_depth: row.cia_share_of_total_optical_depth,
    }
}

fn copy_radiative_transfer_diagnostic_row(
    row: crate::RadiativeTransferDiagnosticRow,
) -> ZdsRadiativeTransferDiagnosticRow {
    ZdsRadiativeTransferDiagnosticRow {
        wavelength_nm: row.wavelength_nm,
        layer_index: row.layer_index,
        sublayer_index: row.sublayer_index,
        global_sublayer_index: row.global_sublayer_index,
        interval_index_1based: row.interval_index_1based,
        altitude_km: row.altitude_km,
        total_optical_depth: row.total_optical_depth,
        total_absorption_optical_depth: row.total_absorption_optical_depth,
        total_scattering_optical_depth: row.total_scattering_optical_depth,
        single_scatter_albedo: row.single_scatter_albedo,
        cumulative_optical_depth_above: row.cumulative_optical_depth_above,
        mid_layer_transmission_proxy: row.mid_layer_transmission_proxy,
        direct_surface_transmission_proxy: row.direct_surface_transmission_proxy,
        atmospheric_scattering_source_proxy: row.atmospheric_scattering_source_proxy,
        absorption_loss_proxy: row.absorption_loss_proxy,
        pseudo_spherical_airmass_factor: row.pseudo_spherical_airmass_factor,
        n_streams: row.n_streams,
        integrate_source_function: row.integrate_source_function,
        final_reflectance: row.final_reflectance,
        final_radiance: row.final_radiance,
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
    use crate::{
        forward_model::{
            instrument_grid::InstrumentGridSummary,
            optical_properties::{
                PreparedOpticalState, PreparedSublayer, state_build::PreparedLineAbsorber,
            },
            radiative_transfer::{
                common_route,
                common_types::{
                    DispatchRequest, ExecutionMode, RadiativeTransferControls, ScatteringMode,
                },
            },
        },
        input::{
            atmospheric_types::AbsorberSpecies,
            o2a_reference::ReferenceSample,
            reference_data::{SpectroscopyLine, SpectroscopyLineList},
            scene::Scene,
        },
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
    fn default_o2a_json_can_prepare_context() {
        let mut ctx = Context::default();
        let mut len = 0_usize;

        assert_eq!(
            unsafe { zds_default_o2a_input_json(&mut ctx, ptr::null_mut(), 0, &mut len) },
            ZDS_OK
        );
        assert!(len > 0);

        let mut buffer = vec![0_u8; len + 1];
        assert_eq!(
            unsafe {
                zds_default_o2a_input_json(&mut ctx, buffer.as_mut_ptr(), buffer.len(), &mut len)
            },
            ZDS_OK
        );
        assert_eq!(buffer[len], 0);
        assert_eq!(
            unsafe { zds_prepare_o2a_json(&mut ctx, buffer.as_ptr(), len) },
            ZDS_OK
        );
        assert!(ctx.prepared.is_some());
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

    #[test]
    fn atmospheric_budget_returns_owned_rows_and_free_resets_handle() {
        let mut ctx = Context {
            prepared: Some(synthetic_prepared_o2a()),
            ..Context::default()
        };
        let wavelengths = [760.0];
        let mut budget = ZdsAtmosphericBudget::default();

        let status = unsafe {
            zds_atmospheric_budget(
                &mut ctx,
                wavelengths.as_ptr(),
                wavelengths.len(),
                &mut budget,
            )
        };

        assert_eq!(status, ZDS_OK);
        assert_eq!(budget.len, 1);
        assert!(!budget.rows.is_null());
        let rows = unsafe { std::slice::from_raw_parts(budget.rows, budget.len) };
        assert_eq!(rows[0].wavelength_nm, 760.0);
        assert_eq!(rows[0].path_length_cm, 100_000.0);

        unsafe {
            zds_atmospheric_budget_free(&mut ctx, &mut budget);
        }
        assert_eq!(budget, ZdsAtmosphericBudget::default());
    }

    #[test]
    fn o2_line_contributions_returns_owned_rows_and_free_resets_handle() {
        let mut ctx = Context {
            prepared: Some(synthetic_prepared_o2a_with_o2_line()),
            ..Context::default()
        };
        let wavelengths = [760.5];
        let mut table = ZdsO2LineContributions::default();

        let status = unsafe {
            zds_o2_line_contributions(
                &mut ctx,
                wavelengths.as_ptr(),
                wavelengths.len(),
                10,
                &mut table,
            )
        };

        assert_eq!(status, ZDS_OK);
        assert_eq!(table.len, 1);
        assert_eq!(table.total_row_count, 1);
        assert_eq!(table.truncated, 0);
        assert!(!table.rows.is_null());
        let rows = unsafe { std::slice::from_raw_parts(table.rows, table.len) };
        assert_eq!(rows[0].wavelength_nm, 760.5);
        assert_eq!(rows[0].gas_index, 7);
        assert_eq!(rows[0].isotope_number, 1);
        assert!(rows[0].total_sigma_cm2_per_molecule >= 0.0);

        unsafe {
            zds_o2_line_contributions_free(&mut ctx, &mut table);
        }
        assert_eq!(table, ZdsO2LineContributions::default());
    }

    #[test]
    fn instrument_response_sampling_returns_owned_rows_and_free_resets_handle() {
        let mut ctx = Context {
            prepared: Some(synthetic_prepared_o2a()),
            ..Context::default()
        };
        let wavelengths = [759.0, 761.0];
        let mut table = ZdsInstrumentResponse::default();

        let status = unsafe {
            zds_instrument_response_sampling(
                &mut ctx,
                wavelengths.as_ptr(),
                wavelengths.len(),
                crate::report::CHANNEL_MASK_RADIANCE,
                &mut table,
            )
        };

        assert_eq!(status, ZDS_OK);
        assert_eq!(table.len, 2);
        assert!(!table.rows.is_null());
        let rows = unsafe { std::slice::from_raw_parts(table.rows, table.len) };
        assert_eq!(rows[0].nominal_wavelength_nm, 759.0);
        assert_eq!(rows[0].channel, 0);
        assert_eq!(rows[0].weight, 1.0);
        assert_eq!(rows[1].nominal_wavelength_nm, 761.0);

        unsafe {
            zds_instrument_response_free(&mut ctx, &mut table);
        }
        assert_eq!(table, ZdsInstrumentResponse::default());
    }

    #[test]
    fn o2_o2_cia_diagnostics_returns_owned_rows_and_free_resets_handle() {
        let mut ctx = Context {
            prepared: Some(synthetic_prepared_o2a()),
            ..Context::default()
        };
        let wavelengths = [760.0];
        let mut table = ZdsO2O2CiaDiagnostics::default();

        let status = unsafe {
            zds_o2_o2_cia_diagnostics(
                &mut ctx,
                wavelengths.as_ptr(),
                wavelengths.len(),
                &mut table,
            )
        };

        assert_eq!(status, ZDS_OK);
        assert_eq!(table.len, 1);
        assert!(!table.rows.is_null());
        let rows = unsafe { std::slice::from_raw_parts(table.rows, table.len) };
        assert_eq!(rows[0].wavelength_nm, 760.0);
        assert_eq!(rows[0].path_length_cm, 100_000.0);

        unsafe {
            zds_o2_o2_cia_diagnostics_free(&mut ctx, &mut table);
        }
        assert_eq!(table, ZdsO2O2CiaDiagnostics::default());
    }

    #[test]
    fn radiative_transfer_diagnostics_reads_optional_spectrum_handle() {
        let mut ctx = Context {
            prepared: Some(synthetic_prepared_o2a()),
            ..Context::default()
        };
        let mut spectrum = ZdsSpectrum::default();
        assert_eq!(unsafe { zds_run_spectrum(&mut ctx, &mut spectrum) }, ZDS_OK);

        let wavelengths = [759.0];
        let mut table = ZdsRadiativeTransferDiagnostics::default();
        let status = unsafe {
            zds_radiative_transfer_diagnostics(
                &mut ctx,
                wavelengths.as_ptr(),
                wavelengths.len(),
                &spectrum,
                &mut table,
            )
        };

        assert_eq!(status, ZDS_OK);
        assert_eq!(table.len, 1);
        assert!(!table.rows.is_null());
        let rows = unsafe { std::slice::from_raw_parts(table.rows, table.len) };
        assert_eq!(rows[0].wavelength_nm, 759.0);
        assert_eq!(rows[0].final_reflectance, 0.23);
        assert!(rows[0].final_radiance > 0.0);

        unsafe {
            zds_radiative_transfer_diagnostics_free(&mut ctx, &mut table);
            zds_spectrum_free(&mut ctx, &mut spectrum);
        }
        assert_eq!(table, ZdsRadiativeTransferDiagnostics::default());
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

    fn synthetic_prepared_o2a_with_o2_line() -> crate::PreparedO2A {
        let mut prepared = synthetic_prepared_o2a();
        prepared.prepared.effective_temperature_k = 296.0;
        prepared.prepared.effective_pressure_hpa = 500.0;
        prepared.prepared.line_absorbers = vec![PreparedLineAbsorber {
            species: AbsorberSpecies::O2,
            line_list: SpectroscopyLineList {
                lines: vec![SpectroscopyLine {
                    gas_index: 7,
                    isotope_number: 1,
                    center_wavelength_nm: 760.5,
                    center_wavenumber_cm1: Some(1.0e7 / 760.5),
                    line_strength_cm2_per_molecule: 1.0e-24,
                    air_half_width_cm1: Some(0.05),
                    temperature_exponent: 0.75,
                    lower_state_energy_cm1: 10.0,
                    pressure_shift_cm1: Some(0.0),
                    ..SpectroscopyLine::default()
                }],
                ..SpectroscopyLineList::default()
            },
            number_densities_cm3: Vec::new(),
            strong_line_states: Vec::new(),
            column_density_factor: 1.0,
        }];
        prepared
    }
}
