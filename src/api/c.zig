const std = @import("std");
const zdisamar = @import("zdisamar");

const allocator = std.heap.smp_allocator;
const max_aerosol_profile_request_layers = zdisamar.o2a.max_aerosol_profile_layers;

pub const ZdsStatus = enum(c_int) {
    ok = 0,
    failure = 1,
};

// layout(64-bit):
//   size: 64 B, align: 8 B
//   field storage: 64 B across 8 fields; largest: len=8 B, wavelength_nm=8 B, radiance=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: len=8 B
//   out-of-line: wavelength_nm, radiance, irradiance, reflectance, result_handle carry references/descriptors; referenced storage is not included in size
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 64 B (0.062 KiB); total also includes referenced storage above
pub const ZdsSpectrum = extern struct {
    len: usize = 0,
    wavelength_nm: [*]const f64 = undefined,
    radiance: [*]const f64 = undefined,
    irradiance: [*]const f64 = undefined,
    reflectance: [*]const f64 = undefined,
    jacobian: ?[*]const f64 = null,
    jacobian_state_count: usize = 0,
    result_handle: ?*anyopaque = null,
};

pub const ZdsAerosolProfileLayer = extern struct {
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.93,
    asymmetry_factor: f64 = 0.65,
    angstrom_exponent: f64 = 1.3,
    reference_wavelength_nm: f64 = 550.0,
};

pub const ZdsAerosolProfileSpectrumRequest = extern struct {
    layer_count: usize = 0,
    layers: ?[*]const ZdsAerosolProfileLayer = null,
};

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: 44 B across 6 fields; largest: wavelength_start_nm=8 B, wavelength_end_nm=8 B, mean_radiance=8 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total = per instance * live instance count
pub const ZdsDiagnosticReport = extern struct {
    sample_count: u32 = 0,
    wavelength_start_nm: f64 = 0.0,
    wavelength_end_nm: f64 = 0.0,
    mean_radiance: f64 = 0.0,
    mean_irradiance: f64 = 0.0,
    mean_reflectance: f64 = 0.0,
};

// layout(64-bit):
//   size: 96 B, align: 8 B
//   field storage: 88 B across 13 fields; largest: initial=8 B, prior=8 B, variance=8 B; padding: 8 B (64 bits)
//   unused bits: 64 padding + 0 bool-storage slack = 64 bits
//   out-of-line: pressure_profile_altitude_km and pressure_profile_pressure_hpa borrow caller buffers
//   cache span: 2 cache line(s) at 64 B per line
//   count: retrieval state count, currently 1..3
//   footprint: per instance = 96 B (0.094 KiB); total also includes borrowed profile arrays
pub const ZdsOptimalEstimationStateSpec = extern struct {
    state_id: u8 = 0,
    has_lower: u8 = 0,
    has_upper: u8 = 0,
    interval_index_1based: u32 = 0,
    initial: f64 = 0.0,
    prior: f64 = 0.0,
    variance: f64 = 0.0,
    lower: f64 = 0.0,
    upper: f64 = 0.0,
    thickness_hpa: f64 = 0.0,
    pressure_profile_count: usize = 0,
    pressure_profile_altitude_km: ?[*]const f64 = null,
    pressure_profile_pressure_hpa: ?[*]const f64 = null,
};

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: 24 B across 3 fields; largest: max_iterations=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 1 cache line(s) at 64 B per line
//   count: one per native OE request
//   footprint: per instance = 24 B (0.023 KiB)
pub const ZdsOptimalEstimationControls = extern struct {
    max_iterations: usize = 10,
    state_vector_convergence_threshold: f64 = 1.0,
    max_change_transformed_state: f64 = 1.0,
};

// layout(64-bit):
//   size: 72 B, align: 8 B
//   field storage: 72 B across 8 fields; largest: sample_count=8 B, wavelength_nm=8 B, reflectance=8 B; padding: 0 B
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: measurement arrays and state specs borrow caller buffers
//   cache span: 2 cache line(s) at 64 B per line
//   count: one per native OE request
//   footprint: per instance = 72 B (0.070 KiB); total also includes borrowed buffers
pub const ZdsOptimalEstimationRequest = extern struct {
    sample_count: usize = 0,
    wavelength_nm: ?[*]const f64 = null,
    reflectance: ?[*]const f64 = null,
    variance: ?[*]const f64 = null,
    state_count: usize = 0,
    states: ?[*]const ZdsOptimalEstimationStateSpec = null,
    controls: ZdsOptimalEstimationControls = .{},
};

// layout(64-bit):
//   size: 120 B, align: 8 B
//   field storage: 113 B across 15 fields; largest: state_count=8 B, iteration_count=8 B, state_ids=8 B; padding: 7 B
//   unused bits: 56 padding + 0 bool-storage slack = 56 bits
//   out-of-line: all pointer fields borrow the native result handle until freed
//   cache span: 2 cache line(s) at 64 B per line
//   count: one per native OE result
//   footprint: per instance = 120 B (0.117 KiB); total also includes native result arrays
pub const ZdsOptimalEstimationResult = extern struct {
    state_count: usize = 0,
    iteration_count: usize = 0,
    converged: u8 = 0,
    state_ids: ?[*]const u8 = null,
    state: ?[*]const f64 = null,
    initial_state: ?[*]const f64 = null,
    posterior_covariance: ?[*]const f64 = null,
    averaging_kernel: ?[*]const f64 = null,
    history_state: ?[*]const f64 = null,
    history_chi2: ?[*]const f64 = null,
    history_chi2_reflectance: ?[*]const f64 = null,
    history_chi2_state_vector: ?[*]const f64 = null,
    history_state_vector_convergence: ?[*]const f64 = null,
    history_snr_normal: ?[*]const u8 = null,
    result_handle: ?*anyopaque = null,
};

// layout(64-bit):
//   size: 240 B, align: 8 B
//   field storage: 240 B across 33 fields; largest: wavelength_nm=8 B, altitude_km=8 B, top_altitude_km=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 240 B (0.234 KiB); total = per instance * live instance count
pub const ZdsAtmosphericBudgetRow = extern struct {
    wavelength_nm: f64 = 0.0,
    layer_index: u32 = 0,
    sublayer_index: u32 = 0,
    global_sublayer_index: u32 = 0,
    interval_index_1based: u32 = 0,
    support_row_kind: u32 = 0,
    altitude_km: f64 = 0.0,
    top_altitude_km: f64 = 0.0,
    bottom_altitude_km: f64 = 0.0,
    pressure_hpa: f64 = 0.0,
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    temperature_k: f64 = 0.0,
    number_density_cm3: f64 = 0.0,
    oxygen_number_density_cm3: f64 = 0.0,
    absorber_number_density_cm3: f64 = 0.0,
    path_length_cm: f64 = 0.0,
    aerosol_fraction: f64 = 0.0,
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    aerosol_absorption_optical_depth: f64 = 0.0,
    total_absorption_optical_depth: f64 = 0.0,
    total_scattering_optical_depth: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: len=8 B, rows=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: len=8 B
//   out-of-line: rows carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
pub const ZdsAtmosphericBudget = extern struct {
    len: usize = 0,
    rows: [*]const ZdsAtmosphericBudgetRow = undefined,
};

// layout(64-bit):
//   size: 168 B, align: 8 B
//   field storage: 159 B across 25 fields; largest: wavelength_nm=8 B, altitude_km=8 B, center_wavelength_nm=8 B; padding: 9 B (72 bits)
//   unused bits: 72 padding + 0 bool-storage slack = 72 bits
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 168 B (0.164 KiB); total = per instance * live instance count
pub const ZdsO2LineContributionRow = extern struct {
    wavelength_nm: f64 = 0.0,
    profile_node_index: u32 = 0,
    altitude_km: f64 = 0.0,
    row_kind: u32 = 0,
    status: u32 = 0,
    line_index: u32 = 0,
    strong_line_index: u32 = 0,
    matched_strong_line_index: u32 = 0,
    gas_index: u16 = 0,
    isotope_number: u8 = 0,
    isotopologue_code: i32 = 0,
    center_wavelength_nm: f64 = 0.0,
    center_wavenumber_cm1: f64 = 0.0,
    shifted_center_wavenumber_cm1: f64 = 0.0,
    line_strength_cm2_per_molecule: f64 = 0.0,
    air_half_width_cm1: f64 = 0.0,
    pressure_shift_cm1: f64 = 0.0,
    lower_state_energy_cm1: f64 = 0.0,
    temperature_k: f64 = 0.0,
    pressure_hpa: f64 = 0.0,
    weak_line_sigma_cm2_per_molecule: f64 = 0.0,
    strong_line_sigma_cm2_per_molecule: f64 = 0.0,
    line_mixing_sigma_cm2_per_molecule: f64 = 0.0,
    total_sigma_cm2_per_molecule: f64 = 0.0,
    abs_total_sigma_cm2_per_molecule: f64 = 0.0,
};

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: len=8 B, total_row_count=8 B, truncated=1 B, rows=8 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 0 bool-storage slack = 56 bits
//   metadata fields: len=8 B
//   out-of-line: rows carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above
pub const ZdsO2LineContributions = extern struct {
    len: usize = 0,
    total_row_count: usize = 0,
    truncated: u8 = 0,
    rows: [*]const ZdsO2LineContributionRow = undefined,
};

// layout(64-bit):
//   size: 96 B, align: 8 B
//   field storage: 85 B across 14 fields; largest: nominal_wavelength_nm=8 B, offset_nm=8 B, support_wavelength_nm=8 B; padding: 11 B (88 bits)
//   unused bits: 88 padding + 0 bool-storage slack = 88 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 96 B (0.094 KiB); total = per instance * live instance count
pub const ZdsInstrumentResponseRow = extern struct {
    nominal_index: i32 = 0,
    nominal_wavelength_nm: f64 = 0.0,
    channel: u32 = 0,
    sample_index: u32 = 0,
    support_count: u32 = 0,
    offset_nm: f64 = 0.0,
    support_wavelength_nm: f64 = 0.0,
    weight: f64 = 0.0,
    support_width_nm: f64 = 0.0,
    instrument_fwhm_nm: f64 = 0.0,
    high_resolution_step_nm: f64 = 0.0,
    high_resolution_half_span_nm: f64 = 0.0,
    integration_mode: u32 = 0,
    response_enabled: u8 = 0,
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: len=8 B, rows=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: len=8 B
//   out-of-line: rows carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
pub const ZdsInstrumentResponse = extern struct {
    len: usize = 0,
    rows: [*]const ZdsInstrumentResponseRow = undefined,
};

// layout(64-bit):
//   size: 112 B, align: 8 B
//   field storage: 112 B across 16 fields; largest: wavelength_nm=8 B, altitude_km=8 B, pressure_hpa=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 112 B (0.109 KiB); total = per instance * live instance count
pub const ZdsO2O2CIARow = extern struct {
    wavelength_nm: f64 = 0.0,
    layer_index: u32 = 0,
    sublayer_index: u32 = 0,
    global_sublayer_index: u32 = 0,
    interval_index_1based: u32 = 0,
    altitude_km: f64 = 0.0,
    pressure_hpa: f64 = 0.0,
    temperature_k: f64 = 0.0,
    oxygen_number_density_cm3: f64 = 0.0,
    path_length_cm: f64 = 0.0,
    cia_cross_section_cm5_per_molecule2: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    total_absorption_optical_depth: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    cia_share_of_total_absorption: f64 = 0.0,
    cia_share_of_total_optical_depth: f64 = 0.0,
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: len=8 B, rows=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: len=8 B
//   out-of-line: rows carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
pub const ZdsO2O2CIADiagnostics = extern struct {
    len: usize = 0,
    rows: [*]const ZdsO2O2CIARow = undefined,
};

// layout(64-bit):
//   size: 136 B, align: 8 B
//   field storage: 133 B across 20 fields; largest: wavelength_nm=8 B, altitude_km=8 B, total_optical_depth=8 B; padding: 3 B (24 bits)
//   unused bits: 24 padding + 0 bool-storage slack = 24 bits
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 136 B (0.133 KiB); total = per instance * live instance count
pub const ZdsRadiativeTransferDiagnosticRow = extern struct {
    wavelength_nm: f64 = 0.0,
    layer_index: u32 = 0,
    sublayer_index: u32 = 0,
    global_sublayer_index: u32 = 0,
    interval_index_1based: u32 = 0,
    altitude_km: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    total_absorption_optical_depth: f64 = 0.0,
    total_scattering_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
    cumulative_optical_depth_above: f64 = 0.0,
    mid_layer_transmission_proxy: f64 = 0.0,
    direct_surface_transmission_proxy: f64 = 0.0,
    atmospheric_scattering_source_proxy: f64 = 0.0,
    absorption_loss_proxy: f64 = 0.0,
    pseudo_spherical_airmass_factor: f64 = 0.0,
    n_streams: u32 = 0,
    integrate_source_function: u8 = 0,
    final_reflectance: f64 = 0.0,
    final_radiance: f64 = 0.0,
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: len=8 B, rows=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: len=8 B
//   out-of-line: rows carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
pub const ZdsRadiativeTransferDiagnostics = extern struct {
    len: usize = 0,
    rows: [*]const ZdsRadiativeTransferDiagnosticRow = undefined,
};

// layout(64-bit):
//   size: 5840 B, align: 8 B
//   field storage: 5833 B across 11 fields; largest: prepared=3832 B, parsed_input=960 B, o2a_session_storage=616 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 0 bool-storage slack = 56 bits
//   inline arrays: last_error:[256:0]u8=257 B
//   out-of-line: results, oe_results, atmospheric_budgets, o2_line_contribution_tables, instrument_response_tables, o2_o2_cia_tables, +1 more carry references/descriptors; referenced storage is not included in size
//   cache span: 92 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 5840 B (5.703 KiB); total also includes referenced storage above
const Context = struct {
    prepared: ?zdisamar.PreparedO2A = null,
    parsed_input: ?std.json.Parsed(zdisamar.O2AInput) = null,
    aerosol_profile_session: ?zdisamar.o2a.AerosolProfileSpectrumSession = null,
    o2a_session_storage: zdisamar.O2ASessionStorage = .{},
    results: std.ArrayList(*zdisamar.Output) = .empty,
    oe_results: std.ArrayList(*zdisamar.optimal_estimation.Result) = .empty,
    atmospheric_budgets: std.ArrayList([]ZdsAtmosphericBudgetRow) = .empty,
    o2_line_contribution_tables: std.ArrayList([]ZdsO2LineContributionRow) = .empty,
    instrument_response_tables: std.ArrayList([]ZdsInstrumentResponseRow) = .empty,
    o2_o2_cia_tables: std.ArrayList([]ZdsO2O2CIARow) = .empty,
    radiative_transfer_tables: std.ArrayList([]ZdsRadiativeTransferDiagnosticRow) = .empty,
    last_error: [256:0]u8 = [_:0]u8{0} ** 256,

    fn clearResults(self: *Context) void {
        for (self.results.items) |result| {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        self.results.clearAndFree(allocator);
    }

    fn clearOptimalEstimationResults(self: *Context) void {
        for (self.oe_results.items) |result| {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        self.oe_results.clearAndFree(allocator);
    }

    fn clearAtmosphericBudgets(self: *Context) void {
        clearStoredRows(ZdsAtmosphericBudgetRow, &self.atmospheric_budgets);
    }

    fn clearO2LineContributionTables(self: *Context) void {
        clearStoredRows(ZdsO2LineContributionRow, &self.o2_line_contribution_tables);
    }

    fn clearInstrumentResponseTables(self: *Context) void {
        clearStoredRows(ZdsInstrumentResponseRow, &self.instrument_response_tables);
    }

    fn clearO2O2CIATables(self: *Context) void {
        clearStoredRows(ZdsO2O2CIARow, &self.o2_o2_cia_tables);
    }

    fn clearRadiativeTransferTables(self: *Context) void {
        clearStoredRows(ZdsRadiativeTransferDiagnosticRow, &self.radiative_transfer_tables);
    }

    fn removeResult(self: *Context, result: *zdisamar.Output) bool {
        for (self.results.items, 0..) |stored, index| {
            if (stored == result) {
                _ = self.results.swapRemove(index);
                return true;
            }
        }
        return false;
    }

    fn removeOptimalEstimationResult(self: *Context, result: *zdisamar.optimal_estimation.Result) bool {
        for (self.oe_results.items, 0..) |stored, index| {
            if (stored == result) {
                _ = self.oe_results.swapRemove(index);
                return true;
            }
        }
        return false;
    }

    fn removeAtmosphericBudget(self: *Context, rows_ptr: [*]const ZdsAtmosphericBudgetRow) ?[]ZdsAtmosphericBudgetRow {
        return removeStoredRows(ZdsAtmosphericBudgetRow, &self.atmospheric_budgets, rows_ptr);
    }

    fn removeO2LineContributionTable(
        self: *Context,
        rows_ptr: [*]const ZdsO2LineContributionRow,
    ) ?[]ZdsO2LineContributionRow {
        return removeStoredRows(ZdsO2LineContributionRow, &self.o2_line_contribution_tables, rows_ptr);
    }

    fn removeInstrumentResponseTable(self: *Context, rows_ptr: [*]const ZdsInstrumentResponseRow) ?[]ZdsInstrumentResponseRow {
        return removeStoredRows(ZdsInstrumentResponseRow, &self.instrument_response_tables, rows_ptr);
    }

    fn removeO2O2CIATable(self: *Context, rows_ptr: [*]const ZdsO2O2CIARow) ?[]ZdsO2O2CIARow {
        return removeStoredRows(ZdsO2O2CIARow, &self.o2_o2_cia_tables, rows_ptr);
    }

    fn removeRadiativeTransferTable(
        self: *Context,
        rows_ptr: [*]const ZdsRadiativeTransferDiagnosticRow,
    ) ?[]ZdsRadiativeTransferDiagnosticRow {
        return removeStoredRows(ZdsRadiativeTransferDiagnosticRow, &self.radiative_transfer_tables, rows_ptr);
    }

    fn ownsResult(self: *const Context, result: *const zdisamar.Output) bool {
        for (self.results.items) |stored| {
            if (stored == result) return true;
        }
        return false;
    }

    fn clearPrepared(self: *Context) void {
        if (self.aerosol_profile_session) |*session| session.deinit(allocator);
        self.aerosol_profile_session = null;
        if (self.prepared) |*prepared| prepared.deinit(allocator);
        self.prepared = null;
        if (self.parsed_input) |*parsed| parsed.deinit();
        self.parsed_input = null;
    }

    fn setError(self: *Context, message: []const u8) void {
        @memset(self.last_error[0..], 0);
        const n = @min(message.len, self.last_error.len - 1);
        @memcpy(self.last_error[0..n], message[0..n]);
    }
};

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: prepared=8 B, wavelengths=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: prepared, wavelengths carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total also includes referenced storage above
const PreparedWavelengthRequest = struct {
    prepared: *zdisamar.PreparedO2A,
    wavelengths: []const f64,
};

fn clearStoredRows(comptime Row: type, list: *std.ArrayList([]Row)) void {
    for (list.items) |rows| allocator.free(rows);
    list.clearAndFree(allocator);
}

fn removeStoredRows(comptime Row: type, list: *std.ArrayList([]Row), rows_ptr: [*]const Row) ?[]Row {
    for (list.items, 0..) |stored, index| {
        if (stored.ptr == rows_ptr) {
            return list.swapRemove(index);
        }
    }
    return null;
}

fn checkedWavelengthRequest(
    resolved: *Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
) ?PreparedWavelengthRequest {
    const wavelengths = wavelengths_ptr orelse {
        resolved.setError("null wavelengths");
        return null;
    };
    if (wavelength_count == 0) {
        resolved.setError("empty wavelengths");
        return null;
    }
    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return null;
    }
    return .{
        .prepared = &resolved.prepared.?,
        .wavelengths = wavelengths[0..wavelength_count],
    };
}

fn storeCopiedRows(
    comptime NativeRow: type,
    comptime ApiRow: type,
    resolved: *Context,
    list: *std.ArrayList([]ApiRow),
    native_rows: []const NativeRow,
    comptime copyRow: fn (NativeRow) ApiRow,
) ?[]ApiRow {
    const rows = allocator.alloc(ApiRow, native_rows.len) catch |err| {
        resolved.setError(@errorName(err));
        return null;
    };
    errdefer allocator.free(rows);
    for (native_rows, rows) |native, *row| row.* = copyRow(native);

    list.append(allocator, rows) catch |err| {
        allocator.free(rows);
        resolved.setError(@errorName(err));
        return null;
    };
    return rows;
}

export fn zds_context_create() ?*Context {
    const ctx = allocator.create(Context) catch return null;
    ctx.* = .{};
    return ctx;
}

export fn zds_context_destroy(ctx: ?*Context) void {
    const resolved = ctx orelse return;
    resolved.clearResults();
    resolved.clearOptimalEstimationResults();
    resolved.clearAtmosphericBudgets();
    resolved.clearO2LineContributionTables();
    resolved.clearInstrumentResponseTables();
    resolved.clearO2O2CIATables();
    resolved.clearRadiativeTransferTables();
    resolved.clearPrepared();
    resolved.o2a_session_storage.deinit(allocator);
    allocator.destroy(resolved);
}

export fn zds_prepare_default_o2a(ctx: ?*Context) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    resolved.clearPrepared();
    const input = zdisamar.defaultO2AInput();
    resolved.prepared = zdisamar.prepareO2A(allocator, &input) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_prepare_o2a_json(ctx: ?*Context, json_ptr: ?[*]const u8, json_len: usize) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const ptr = json_ptr orelse {
        resolved.setError("null input JSON");
        return @intFromEnum(ZdsStatus.failure);
    };
    if (json_len == 0) {
        resolved.setError("empty input JSON");
        return @intFromEnum(ZdsStatus.failure);
    }

    var parsed = zdisamar.parseO2AInputJson(allocator, ptr[0..json_len]) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer parsed.deinit();

    var prepared = zdisamar.prepareO2A(allocator, &parsed.value) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer prepared.deinit(allocator);

    resolved.clearPrepared();
    resolved.parsed_input = parsed;
    resolved.prepared = prepared;
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_warm_o2a_session(ctx: ?*Context) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    }
    zdisamar.warmO2ASessionStorage(
        allocator,
        &resolved.o2a_session_storage,
        &resolved.prepared.?,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_default_o2a_input_json(ctx: ?*Context, out: ?[*]u8, capacity: usize, out_len: ?*usize) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const json = zdisamar.renderDefaultO2AInputJson(allocator) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(json);

    if (out_len) |slot| slot.* = json.len;
    if (out) |buffer| {
        if (capacity < json.len + 1) {
            resolved.setError("buffer too small");
            return @intFromEnum(ZdsStatus.failure);
        }
        @memcpy(buffer[0..json.len], json);
        buffer[json.len] = 0;
    }
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_spectrum(ctx: ?*Context, out: ?*ZdsSpectrum) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const output = out orelse return @intFromEnum(ZdsStatus.failure);
    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    }
    const prepared = &resolved.prepared.?;
    const result = allocator.create(zdisamar.Output) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    result.* = zdisamar.runO2AWithSessionStorage(allocator, &resolved.o2a_session_storage, prepared) catch |err| {
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.results.append(allocator, result) catch |err| {
        result.deinit(allocator);
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{
        .len = result.wavelengths.len,
        .wavelength_nm = result.wavelengths.ptr,
        .radiance = result.radiance.ptr,
        .irradiance = result.irradiance.ptr,
        .reflectance = result.reflectance.ptr,
        .jacobian = null,
        .jacobian_state_count = 0,
        .result_handle = @ptrCast(result),
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_aerosol_profile_spectrum(
    ctx: ?*Context,
    request: ?*const ZdsAerosolProfileSpectrumRequest,
    out: ?*ZdsSpectrum,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_request = request orelse {
        resolved.setError("null aerosol-profile spectrum request");
        return @intFromEnum(ZdsStatus.failure);
    };
    const output = out orelse {
        resolved.setError("null spectrum output");
        return @intFromEnum(ZdsStatus.failure);
    };
    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    }
    if (resolved_request.layer_count == 0) {
        resolved.setError("empty aerosol profile");
        return @intFromEnum(ZdsStatus.failure);
    }
    if (resolved_request.layer_count > max_aerosol_profile_request_layers) {
        resolved.setError("too many aerosol profile layers");
        return @intFromEnum(ZdsStatus.failure);
    }
    const raw_layers = resolved_request.layers orelse {
        resolved.setError("null aerosol profile layers");
        return @intFromEnum(ZdsStatus.failure);
    };

    var profile_layer_buffer: [max_aerosol_profile_request_layers]zdisamar.o2a.AerosolProfileLayer = undefined;
    const profile_layers = profile_layer_buffer[0..resolved_request.layer_count];
    for (raw_layers[0..resolved_request.layer_count], profile_layers) |raw, *layer| {
        layer.* = .{
            .top_pressure_hpa = raw.top_pressure_hpa,
            .bottom_pressure_hpa = raw.bottom_pressure_hpa,
            .optical_depth = raw.optical_depth,
            .single_scatter_albedo = raw.single_scatter_albedo,
            .asymmetry_factor = raw.asymmetry_factor,
            .angstrom_exponent = raw.angstrom_exponent,
            .reference_wavelength_nm = raw.reference_wavelength_nm,
        };
    }

    if (resolved.aerosol_profile_session == null) {
        var default_input: zdisamar.O2AInput = undefined;
        const input = if (resolved.parsed_input) |*parsed|
            &parsed.value
        else input: {
            default_input = zdisamar.defaultO2AInput();
            break :input &default_input;
        };
        resolved.aerosol_profile_session = zdisamar.o2a.AerosolProfileSpectrumSession.init(allocator, input) catch |err| {
            resolved.setError(@errorName(err));
            return @intFromEnum(ZdsStatus.failure);
        };
    }

    const result = allocator.create(zdisamar.Output) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    result.* = resolved.aerosol_profile_session.?.run(
        allocator,
        &resolved.o2a_session_storage,
        profile_layers,
    ) catch |err| {
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.results.append(allocator, result) catch |err| {
        result.deinit(allocator);
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{
        .len = result.wavelengths.len,
        .wavelength_nm = result.wavelengths.ptr,
        .radiance = result.radiance.ptr,
        .irradiance = result.irradiance.ptr,
        .reflectance = result.reflectance.ptr,
        .jacobian = null,
        .jacobian_state_count = 0,
        .result_handle = @ptrCast(result),
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_spectrum_jacobian(ctx: ?*Context, out: ?*ZdsSpectrum) c_int {
    return runSpectrumJacobianForStateIds(ctx, out, null, 0);
}

export fn zds_run_spectrum_jacobian_for_states(
    ctx: ?*Context,
    out: ?*ZdsSpectrum,
    state_ids: ?[*]const u8,
    state_count: usize,
) c_int {
    if (state_count != 0 and state_ids == null) return @intFromEnum(ZdsStatus.failure);
    return runSpectrumJacobianForStateIds(ctx, out, state_ids, state_count);
}

export fn zds_run_o2a_optimal_estimation(
    ctx: ?*Context,
    request: ?*const ZdsOptimalEstimationRequest,
    out: ?*ZdsOptimalEstimationResult,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_request = request orelse {
        resolved.setError("null optimal-estimation request");
        return @intFromEnum(ZdsStatus.failure);
    };
    const resolved_out = out orelse {
        resolved.setError("null optimal-estimation result");
        return @intFromEnum(ZdsStatus.failure);
    };
    var default_input: zdisamar.O2AInput = undefined;
    const input = if (resolved.parsed_input) |*parsed|
        &parsed.value
    else input: {
        if (resolved.prepared == null) {
            resolved.setError("not prepared");
            return @intFromEnum(ZdsStatus.failure);
        }
        default_input = zdisamar.defaultO2AInput();
        break :input &default_input;
    };
    const wavelengths_ptr = resolved_request.wavelength_nm orelse {
        resolved.setError("null measurement wavelengths");
        return @intFromEnum(ZdsStatus.failure);
    };
    const reflectance_ptr = resolved_request.reflectance orelse {
        resolved.setError("null measurement reflectance");
        return @intFromEnum(ZdsStatus.failure);
    };
    const variance_ptr = resolved_request.variance orelse {
        resolved.setError("null measurement variance");
        return @intFromEnum(ZdsStatus.failure);
    };
    const state_specs_ptr = resolved_request.states orelse {
        resolved.setError("null state specs");
        return @intFromEnum(ZdsStatus.failure);
    };
    if (resolved_request.sample_count == 0) {
        resolved.setError("empty measurement");
        return @intFromEnum(ZdsStatus.failure);
    }
    if (resolved_request.state_count == 0 or resolved_request.state_count > zdisamar.optimal_estimation.max_state_count) {
        resolved.setError("invalid state count");
        return @intFromEnum(ZdsStatus.failure);
    }

    var profiles = [_]zdisamar.optimal_estimation.PressureAltitudeProfile{.{}} ** zdisamar.optimal_estimation.max_state_count;
    defer {
        for (&profiles) |*profile| {
            if (profile.hasSamples()) {
                zdisamar.optimal_estimation.freePressureProfile(allocator, profile.*);
                profile.* = .{};
            }
        }
    }
    var state_specs: [zdisamar.optimal_estimation.max_state_count]zdisamar.optimal_estimation.StateSpec = undefined;
    const raw_states = state_specs_ptr[0..resolved_request.state_count];
    for (raw_states, 0..) |raw, index| {
        const state = std.meta.intToEnum(zdisamar.RadiativeTransferJacobian.State, raw.state_id) catch |err| {
            resolved.setError(@errorName(err));
            return @intFromEnum(ZdsStatus.failure);
        };
        if (state == .aerosol_layer_mid_pressure_hpa) {
            const altitude_ptr = raw.pressure_profile_altitude_km orelse {
                resolved.setError("missing pressure profile altitude");
                return @intFromEnum(ZdsStatus.failure);
            };
            const pressure_ptr = raw.pressure_profile_pressure_hpa orelse {
                resolved.setError("missing pressure profile pressure");
                return @intFromEnum(ZdsStatus.failure);
            };
            profiles[index] = zdisamar.optimal_estimation.buildPressureProfile(
                allocator,
                altitude_ptr[0..raw.pressure_profile_count],
                pressure_ptr[0..raw.pressure_profile_count],
            ) catch |err| {
                resolved.setError(@errorName(err));
                return @intFromEnum(ZdsStatus.failure);
            };
        }
        if (raw.has_lower != 0 and !std.math.isFinite(raw.lower)) {
            resolved.setError("invalid optimal-estimation lower bound");
            return @intFromEnum(ZdsStatus.failure);
        }
        if (raw.has_upper != 0 and !std.math.isFinite(raw.upper)) {
            resolved.setError("invalid optimal-estimation upper bound");
            return @intFromEnum(ZdsStatus.failure);
        }
        state_specs[index] = .{
            .state = state,
            .initial = raw.initial,
            .prior = raw.prior,
            .variance = raw.variance,
            .lower_bound = if (raw.has_lower != 0) raw.lower else zdisamar.optimal_estimation.no_lower_bound,
            .upper_bound = if (raw.has_upper != 0) raw.upper else zdisamar.optimal_estimation.no_upper_bound,
            .thickness_hpa = raw.thickness_hpa,
            .interval_index_1based = raw.interval_index_1based,
            .pressure_altitude_profile = profiles[index],
        };
    }

    const native = allocator.create(zdisamar.optimal_estimation.Result) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    native.* = zdisamar.optimal_estimation.runO2A(
        allocator,
        input,
        wavelengths_ptr[0..resolved_request.sample_count],
        reflectance_ptr[0..resolved_request.sample_count],
        variance_ptr[0..resolved_request.sample_count],
        state_specs[0..resolved_request.state_count],
        &resolved.o2a_session_storage,
        .{
            .max_iterations = resolved_request.controls.max_iterations,
            .state_vector_convergence_threshold = resolved_request.controls.state_vector_convergence_threshold,
            .max_change_transformed_state = resolved_request.controls.max_change_transformed_state,
        },
    ) catch |err| {
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.oe_results.append(allocator, native) catch |err| {
        native.deinit(allocator);
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    resolved_out.* = optimalEstimationResultView(native);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

fn runSpectrumJacobianForStateIds(
    ctx: ?*Context,
    out: ?*ZdsSpectrum,
    state_ids: ?[*]const u8,
    requested_state_count: usize,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const output = out orelse return @intFromEnum(ZdsStatus.failure);
    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    }
    const state_slice = if (state_ids) |ids| ids[0..requested_state_count] else &.{};
    const selection = jacobianStateSelection(state_slice) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    var prepared = resolved.prepared.?;
    prepared.route.derivative_mode = .semi_analytical;
    prepared.route.derivative_state_mask = selection.mask;
    const result = allocator.create(zdisamar.Output) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    result.* = (if (selection.count == 0)
        zdisamar.runO2AWithSessionStorage(allocator, &resolved.o2a_session_storage, &prepared)
    else
        zdisamar.o2a.runO2AWithSessionStorageJacobianStates(
            allocator,
            &resolved.o2a_session_storage,
            &prepared,
            selection.slice(),
        )) catch |err| {
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.results.append(allocator, result) catch |err| {
        result.deinit(allocator);
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    const output_state_count = if (selection.count == 0)
        zdisamar.RadiativeTransferJacobian.state_count
    else
        selection.count;
    output.* = .{
        .len = result.wavelengths.len,
        .wavelength_nm = result.wavelengths.ptr,
        .radiance = result.radiance.ptr,
        .irradiance = result.irradiance.ptr,
        .reflectance = result.reflectance.ptr,
        .jacobian = if (result.jacobian) |values| values.ptr else null,
        .jacobian_state_count = output_state_count,
        .result_handle = @ptrCast(result),
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_spectrum_report(ctx: ?*Context, spectrum: ?*const ZdsSpectrum, out: ?*ZdsDiagnosticReport) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_spectrum = spectrum orelse {
        resolved.setError("null spectrum");
        return @intFromEnum(ZdsStatus.failure);
    };
    const resolved_out = out orelse {
        resolved.setError("null diagnostic report");
        return @intFromEnum(ZdsStatus.failure);
    };
    const handle = resolved_spectrum.result_handle orelse {
        resolved.setError("spectrum is closed");
        return @intFromEnum(ZdsStatus.failure);
    };
    const result: *zdisamar.Output = @ptrCast(@alignCast(handle));
    if (!resolved.ownsResult(result)) {
        resolved.setError("unknown spectrum result");
        return @intFromEnum(ZdsStatus.failure);
    }

    const report = zdisamar.report.summaryReportFromProduct(result);
    resolved_out.* = .{
        .sample_count = report.sample_count,
        .wavelength_start_nm = report.wavelength_start_nm,
        .wavelength_end_nm = report.wavelength_end_nm,
        .mean_radiance = report.mean_radiance,
        .mean_irradiance = report.mean_irradiance,
        .mean_reflectance = report.mean_reflectance,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_atmospheric_budget(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    out: ?*ZdsAtmosphericBudget,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_out = out orelse {
        resolved.setError("null atmospheric budget");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);

    const native_rows = zdisamar.buildAtmosphericBudget(
        allocator,
        &request.prepared.scene,
        &request.prepared.prepared,
        request.wavelengths,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(native_rows);

    const rows = storeCopiedRows(
        zdisamar.AtmosphericBudgetRow,
        ZdsAtmosphericBudgetRow,
        resolved,
        &resolved.atmospheric_budgets,
        native_rows,
        copyAtmosphericBudgetRow,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    resolved_out.* = .{
        .len = rows.len,
        .rows = rows.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_o2_line_contributions(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    max_rows: usize,
    out: ?*ZdsO2LineContributions,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_out = out orelse {
        resolved.setError("null O2 line contribution table");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);
    if (max_rows == 0) {
        resolved.setError("invalid row limit");
        return @intFromEnum(ZdsStatus.failure);
    }

    var native_table = zdisamar.buildO2LineContributions(
        allocator,
        &request.prepared.prepared,
        request.wavelengths,
        max_rows,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer native_table.deinit(allocator);

    const rows = storeCopiedRows(
        zdisamar.O2LineContributionRow,
        ZdsO2LineContributionRow,
        resolved,
        &resolved.o2_line_contribution_tables,
        native_table.rows,
        copyO2LineContributionRow,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    resolved_out.* = .{
        .len = rows.len,
        .total_row_count = native_table.total_row_count,
        .truncated = if (native_table.truncated) 1 else 0,
        .rows = rows.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_instrument_response_sampling(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    channel_mask: u32,
    out: ?*ZdsInstrumentResponse,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_out = out orelse {
        resolved.setError("null instrument response table");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);

    const native_rows = zdisamar.buildInstrumentResponse(
        allocator,
        &request.prepared.scene,
        &request.prepared.prepared,
        request.wavelengths,
        channel_mask,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(native_rows);

    const rows = storeCopiedRows(
        zdisamar.InstrumentResponseRow,
        ZdsInstrumentResponseRow,
        resolved,
        &resolved.instrument_response_tables,
        native_rows,
        copyInstrumentResponseRow,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    resolved_out.* = .{
        .len = rows.len,
        .rows = rows.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_o2_o2_cia_diagnostics(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    out: ?*ZdsO2O2CIADiagnostics,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_out = out orelse {
        resolved.setError("null O2-O2 CIA table");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);

    const native_rows = zdisamar.buildO2O2CIADiagnostics(
        allocator,
        &request.prepared.scene,
        &request.prepared.prepared,
        request.wavelengths,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(native_rows);

    const rows = storeCopiedRows(
        zdisamar.O2O2CIARow,
        ZdsO2O2CIARow,
        resolved,
        &resolved.o2_o2_cia_tables,
        native_rows,
        copyO2O2CIARow,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    resolved_out.* = .{
        .len = rows.len,
        .rows = rows.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_radiative_transfer_diagnostics(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    spectrum: ?*const ZdsSpectrum,
    out: ?*ZdsRadiativeTransferDiagnostics,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_out = out orelse {
        resolved.setError("null radiative-transfer table");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);
    const spectrum_view = spectrumView(resolved, spectrum) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    const native_rows = zdisamar.buildRadiativeTransferDiagnostics(
        allocator,
        &request.prepared.scene,
        &request.prepared.prepared,
        request.prepared.route,
        request.wavelengths,
        spectrum_view,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(native_rows);

    const rows = storeCopiedRows(
        zdisamar.RadiativeTransferDiagnosticRow,
        ZdsRadiativeTransferDiagnosticRow,
        resolved,
        &resolved.radiative_transfer_tables,
        native_rows,
        copyRadiativeTransferDiagnosticRow,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    resolved_out.* = .{
        .len = rows.len,
        .rows = rows.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_spectrum_free(ctx: ?*Context, out: ?*ZdsSpectrum) void {
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.Output = @ptrCast(@alignCast(handle));
        if (resolved.removeResult(result)) {
            result.deinit(allocator);
            allocator.destroy(result);
        }
    }
    output.* = .{};
}

export fn zds_optimal_estimation_result_free(ctx: ?*Context, out: ?*ZdsOptimalEstimationResult) void {
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.optimal_estimation.Result = @ptrCast(@alignCast(handle));
        if (resolved.removeOptimalEstimationResult(result)) {
            result.deinit(allocator);
            allocator.destroy(result);
        }
    }
    output.* = .{};
}

export fn zds_atmospheric_budget_free(ctx: ?*Context, out: ?*ZdsAtmosphericBudget) void {
    const resolved = ctx orelse return;
    const budget = out orelse return;
    if (budget.len != 0) {
        if (resolved.removeAtmosphericBudget(budget.rows)) |rows| allocator.free(rows);
    }
    budget.* = .{};
}

export fn zds_o2_line_contributions_free(ctx: ?*Context, out: ?*ZdsO2LineContributions) void {
    const resolved = ctx orelse return;
    const table = out orelse return;
    if (table.len != 0) {
        if (resolved.removeO2LineContributionTable(table.rows)) |rows| allocator.free(rows);
    }
    table.* = .{};
}

export fn zds_instrument_response_free(ctx: ?*Context, out: ?*ZdsInstrumentResponse) void {
    const resolved = ctx orelse return;
    const table = out orelse return;
    if (table.len != 0) {
        if (resolved.removeInstrumentResponseTable(table.rows)) |rows| allocator.free(rows);
    }
    table.* = .{};
}

export fn zds_o2_o2_cia_diagnostics_free(ctx: ?*Context, out: ?*ZdsO2O2CIADiagnostics) void {
    const resolved = ctx orelse return;
    const table = out orelse return;
    if (table.len != 0) {
        if (resolved.removeO2O2CIATable(table.rows)) |rows| allocator.free(rows);
    }
    table.* = .{};
}

export fn zds_radiative_transfer_diagnostics_free(ctx: ?*Context, out: ?*ZdsRadiativeTransferDiagnostics) void {
    const resolved = ctx orelse return;
    const table = out orelse return;
    if (table.len != 0) {
        if (resolved.removeRadiativeTransferTable(table.rows)) |rows| allocator.free(rows);
    }
    table.* = .{};
}

export fn zds_last_error(ctx: ?*Context) [*:0]const u8 {
    const resolved = ctx orelse return "null context";
    return @ptrCast(&resolved.last_error);
}

fn spectrumView(resolved: *const Context, spectrum: ?*const ZdsSpectrum) !?zdisamar.RadiativeTransferSpectrumView {
    const raw = spectrum orelse return null;
    const handle = raw.result_handle orelse return error.SpectrumClosed;
    const result: *zdisamar.Output = @ptrCast(@alignCast(handle));
    if (!resolved.ownsResult(result)) return error.UnknownSpectrumResult;
    return .{
        .wavelength_nm = raw.wavelength_nm[0..raw.len],
        .reflectance = raw.reflectance[0..raw.len],
        .radiance = raw.radiance[0..raw.len],
    };
}

fn optimalEstimationResultView(native: *zdisamar.optimal_estimation.Result) ZdsOptimalEstimationResult {
    return .{
        .state_count = @intCast(native.state_count),
        .iteration_count = @intCast(native.iteration_count),
        .converged = if (native.converged) 1 else 0,
        .state_ids = @ptrCast(native.state_ids.ptr),
        .state = native.state.ptr,
        .initial_state = native.initial_state.ptr,
        .posterior_covariance = native.posterior_covariance.ptr,
        .averaging_kernel = native.averaging_kernel.ptr,
        .history_state = native.history_state.ptr,
        .history_chi2 = native.history_chi2.ptr,
        .history_chi2_reflectance = native.history_chi2_reflectance.ptr,
        .history_chi2_state_vector = native.history_chi2_state_vector.ptr,
        .history_state_vector_convergence = native.history_state_vector_convergence.ptr,
        .history_snr_normal = native.history_snr_normal.ptr,
        .result_handle = @ptrCast(native),
    };
}

fn copyAtmosphericBudgetRow(row: zdisamar.AtmosphericBudgetRow) ZdsAtmosphericBudgetRow {
    return .{
        .wavelength_nm = row.wavelength_nm,
        .layer_index = row.layer_index,
        .sublayer_index = row.sublayer_index,
        .global_sublayer_index = row.global_sublayer_index,
        .interval_index_1based = row.interval_index_1based,
        .support_row_kind = @intFromEnum(row.support_row_kind),
        .altitude_km = row.altitude_km,
        .top_altitude_km = row.top_altitude_km,
        .bottom_altitude_km = row.bottom_altitude_km,
        .pressure_hpa = row.pressure_hpa,
        .top_pressure_hpa = row.top_pressure_hpa,
        .bottom_pressure_hpa = row.bottom_pressure_hpa,
        .temperature_k = row.temperature_k,
        .number_density_cm3 = row.number_density_cm3,
        .oxygen_number_density_cm3 = row.oxygen_number_density_cm3,
        .absorber_number_density_cm3 = row.absorber_number_density_cm3,
        .path_length_cm = row.path_length_cm,
        .aerosol_fraction = row.aerosol_fraction,
        .gas_absorption_optical_depth = row.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = row.gas_scattering_optical_depth,
        .cia_optical_depth = row.cia_optical_depth,
        .aerosol_optical_depth = row.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = row.aerosol_scattering_optical_depth,
        .aerosol_absorption_optical_depth = row.aerosol_absorption_optical_depth,
        .total_absorption_optical_depth = row.total_absorption_optical_depth,
        .total_scattering_optical_depth = row.total_scattering_optical_depth,
        .total_optical_depth = row.total_optical_depth,
        .single_scatter_albedo = row.single_scatter_albedo,
    };
}

fn copyO2LineContributionRow(row: zdisamar.O2LineContributionRow) ZdsO2LineContributionRow {
    return .{
        .wavelength_nm = row.wavelength_nm,
        .profile_node_index = row.profile_node_index,
        .altitude_km = row.altitude_km,
        .row_kind = @intFromEnum(row.row_kind),
        .status = @intFromEnum(row.status),
        .line_index = row.line_index,
        .strong_line_index = row.strong_line_index,
        .matched_strong_line_index = row.matched_strong_line_index,
        .gas_index = row.gas_index,
        .isotope_number = row.isotope_number,
        .isotopologue_code = row.isotopologue_code,
        .center_wavelength_nm = row.center_wavelength_nm,
        .center_wavenumber_cm1 = row.center_wavenumber_cm1,
        .shifted_center_wavenumber_cm1 = row.shifted_center_wavenumber_cm1,
        .line_strength_cm2_per_molecule = row.line_strength_cm2_per_molecule,
        .air_half_width_cm1 = row.air_half_width_cm1,
        .pressure_shift_cm1 = row.pressure_shift_cm1,
        .lower_state_energy_cm1 = row.lower_state_energy_cm1,
        .temperature_k = row.temperature_k,
        .pressure_hpa = row.pressure_hpa,
        .weak_line_sigma_cm2_per_molecule = row.weak_line_sigma_cm2_per_molecule,
        .strong_line_sigma_cm2_per_molecule = row.strong_line_sigma_cm2_per_molecule,
        .line_mixing_sigma_cm2_per_molecule = row.line_mixing_sigma_cm2_per_molecule,
        .total_sigma_cm2_per_molecule = row.total_sigma_cm2_per_molecule,
        .abs_total_sigma_cm2_per_molecule = row.abs_total_sigma_cm2_per_molecule,
    };
}

fn copyInstrumentResponseRow(row: zdisamar.InstrumentResponseRow) ZdsInstrumentResponseRow {
    return .{
        .nominal_index = row.nominal_index,
        .nominal_wavelength_nm = row.nominal_wavelength_nm,
        .channel = row.channel,
        .sample_index = row.sample_index,
        .support_count = row.support_count,
        .offset_nm = row.offset_nm,
        .support_wavelength_nm = row.support_wavelength_nm,
        .weight = row.weight,
        .support_width_nm = row.support_width_nm,
        .instrument_fwhm_nm = row.instrument_fwhm_nm,
        .high_resolution_step_nm = row.high_resolution_step_nm,
        .high_resolution_half_span_nm = row.high_resolution_half_span_nm,
        .integration_mode = row.integration_mode,
        .response_enabled = row.response_enabled,
    };
}

fn copyO2O2CIARow(row: zdisamar.O2O2CIARow) ZdsO2O2CIARow {
    return .{
        .wavelength_nm = row.wavelength_nm,
        .layer_index = row.layer_index,
        .sublayer_index = row.sublayer_index,
        .global_sublayer_index = row.global_sublayer_index,
        .interval_index_1based = row.interval_index_1based,
        .altitude_km = row.altitude_km,
        .pressure_hpa = row.pressure_hpa,
        .temperature_k = row.temperature_k,
        .oxygen_number_density_cm3 = row.oxygen_number_density_cm3,
        .path_length_cm = row.path_length_cm,
        .cia_cross_section_cm5_per_molecule2 = row.cia_cross_section_cm5_per_molecule2,
        .cia_optical_depth = row.cia_optical_depth,
        .total_absorption_optical_depth = row.total_absorption_optical_depth,
        .total_optical_depth = row.total_optical_depth,
        .cia_share_of_total_absorption = row.cia_share_of_total_absorption,
        .cia_share_of_total_optical_depth = row.cia_share_of_total_optical_depth,
    };
}

fn copyRadiativeTransferDiagnosticRow(
    row: zdisamar.RadiativeTransferDiagnosticRow,
) ZdsRadiativeTransferDiagnosticRow {
    return .{
        .wavelength_nm = row.wavelength_nm,
        .layer_index = row.layer_index,
        .sublayer_index = row.sublayer_index,
        .global_sublayer_index = row.global_sublayer_index,
        .interval_index_1based = row.interval_index_1based,
        .altitude_km = row.altitude_km,
        .total_optical_depth = row.total_optical_depth,
        .total_absorption_optical_depth = row.total_absorption_optical_depth,
        .total_scattering_optical_depth = row.total_scattering_optical_depth,
        .single_scatter_albedo = row.single_scatter_albedo,
        .cumulative_optical_depth_above = row.cumulative_optical_depth_above,
        .mid_layer_transmission_proxy = row.mid_layer_transmission_proxy,
        .direct_surface_transmission_proxy = row.direct_surface_transmission_proxy,
        .atmospheric_scattering_source_proxy = row.atmospheric_scattering_source_proxy,
        .absorption_loss_proxy = row.absorption_loss_proxy,
        .pseudo_spherical_airmass_factor = row.pseudo_spherical_airmass_factor,
        .n_streams = row.n_streams,
        .integrate_source_function = row.integrate_source_function,
        .final_reflectance = row.final_reflectance,
        .final_radiance = row.final_radiance,
    };
}

fn jacobianStateFromId(state_id: u8) !zdisamar.RadiativeTransferJacobian.State {
    return switch (state_id) {
        @intFromEnum(zdisamar.RadiativeTransferJacobian.State.surface_albedo) => .surface_albedo,
        @intFromEnum(zdisamar.RadiativeTransferJacobian.State.aerosol_optical_depth) => .aerosol_optical_depth,
        @intFromEnum(zdisamar.RadiativeTransferJacobian.State.aerosol_layer_mid_pressure_hpa) => .aerosol_layer_mid_pressure_hpa,
        else => error.UnsupportedJacobianState,
    };
}

const JacobianStateSelection = struct {
    states: [zdisamar.RadiativeTransferJacobian.state_count]zdisamar.RadiativeTransferJacobian.State = undefined,
    count: usize = 0,
    mask: zdisamar.RadiativeTransferJacobian.StateMask = zdisamar.RadiativeTransferJacobian.all_states_mask,

    fn slice(self: *const JacobianStateSelection) []const zdisamar.RadiativeTransferJacobian.State {
        return self.states[0..self.count];
    }
};

fn jacobianStateSelection(state_ids: []const u8) !JacobianStateSelection {
    if (state_ids.len == 0) return .{};
    if (state_ids.len > zdisamar.RadiativeTransferJacobian.state_count) return error.TooManyJacobianStates;

    var selection: JacobianStateSelection = .{
        .mask = 0,
    };
    for (state_ids) |state_id| {
        const state = try jacobianStateFromId(state_id);
        selection.states[selection.count] = state;
        selection.count += 1;
        selection.mask |= zdisamar.RadiativeTransferJacobian.stateMask(state);
    }
    selection.mask = zdisamar.RadiativeTransferJacobian.sanitizedMask(selection.mask);
    return selection;
}
