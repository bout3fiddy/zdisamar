const std = @import("std");
const zdisamar = @import("zdisamar");

const allocator = std.heap.page_allocator;

pub const ZdsStatus = enum(c_int) {
    ok = 0,
    failure = 1,
};

pub const ZdsSpectrum = extern struct {
    len: usize = 0,
    wavelength_nm: [*]const f64 = undefined,
    radiance: [*]const f64 = undefined,
    irradiance: [*]const f64 = undefined,
    reflectance: [*]const f64 = undefined,
    result_handle: ?*anyopaque = null,
};

pub const ZdsDiagnosticReport = extern struct {
    sample_count: u32 = 0,
    wavelength_start_nm: f64 = 0.0,
    wavelength_end_nm: f64 = 0.0,
    mean_radiance: f64 = 0.0,
    mean_irradiance: f64 = 0.0,
    mean_reflectance: f64 = 0.0,
};

pub const ZdsAtmosphericBudgetRow = extern struct {
    wavelength_nm: f64 = 0.0,
    layer_index: u32 = 0,
    sublayer_index: u32 = 0,
    global_sublayer_index: u32 = 0,
    interval_index_1based: u32 = 0,
    support_row_kind: u32 = 0,
    subcolumn_label: u32 = 0,
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
    cloud_fraction: f64 = 0.0,
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    aerosol_absorption_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_scattering_optical_depth: f64 = 0.0,
    cloud_absorption_optical_depth: f64 = 0.0,
    total_absorption_optical_depth: f64 = 0.0,
    total_scattering_optical_depth: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
};

pub const ZdsAtmosphericBudget = extern struct {
    len: usize = 0,
    rows: [*]const ZdsAtmosphericBudgetRow = undefined,
};

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

pub const ZdsO2LineContributions = extern struct {
    len: usize = 0,
    total_row_count: usize = 0,
    truncated: u8 = 0,
    rows: [*]const ZdsO2LineContributionRow = undefined,
};

const Context = struct {
    prepared: ?zdisamar.PreparedO2A = null,
    parsed_input: ?std.json.Parsed(zdisamar.O2AInput) = null,
    results: std.ArrayList(*zdisamar.Output) = .empty,
    atmospheric_budgets: std.ArrayList([]ZdsAtmosphericBudgetRow) = .empty,
    o2_line_contribution_tables: std.ArrayList([]ZdsO2LineContributionRow) = .empty,
    last_error: [256:0]u8 = [_:0]u8{0} ** 256,

    fn clearResults(self: *Context) void {
        for (self.results.items) |result| {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        self.results.clearAndFree(allocator);
    }

    fn clearAtmosphericBudgets(self: *Context) void {
        for (self.atmospheric_budgets.items) |rows| allocator.free(rows);
        self.atmospheric_budgets.clearAndFree(allocator);
    }

    fn clearO2LineContributionTables(self: *Context) void {
        for (self.o2_line_contribution_tables.items) |rows| allocator.free(rows);
        self.o2_line_contribution_tables.clearAndFree(allocator);
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

    fn removeAtmosphericBudget(self: *Context, rows_ptr: [*]const ZdsAtmosphericBudgetRow) ?[]ZdsAtmosphericBudgetRow {
        for (self.atmospheric_budgets.items, 0..) |stored, index| {
            if (stored.ptr == rows_ptr) {
                return self.atmospheric_budgets.swapRemove(index);
            }
        }
        return null;
    }

    fn removeO2LineContributionTable(
        self: *Context,
        rows_ptr: [*]const ZdsO2LineContributionRow,
    ) ?[]ZdsO2LineContributionRow {
        for (self.o2_line_contribution_tables.items, 0..) |stored, index| {
            if (stored.ptr == rows_ptr) {
                return self.o2_line_contribution_tables.swapRemove(index);
            }
        }
        return null;
    }

    fn ownsResult(self: *const Context, result: *const zdisamar.Output) bool {
        for (self.results.items) |stored| {
            if (stored == result) return true;
        }
        return false;
    }

    fn clearPrepared(self: *Context) void {
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

export fn zds_context_create() ?*Context {
    const ctx = allocator.create(Context) catch return null;
    ctx.* = .{};
    return ctx;
}

export fn zds_context_destroy(ctx: ?*Context) void {
    const resolved = ctx orelse return;
    resolved.clearResults();
    resolved.clearAtmosphericBudgets();
    resolved.clearO2LineContributionTables();
    resolved.clearPrepared();
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
    result.* = zdisamar.runO2A(allocator, prepared) catch |err| {
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
    const wavelengths = wavelengths_ptr orelse {
        resolved.setError("null wavelengths");
        return @intFromEnum(ZdsStatus.failure);
    };
    if (wavelength_count == 0) {
        resolved.setError("empty wavelengths");
        return @intFromEnum(ZdsStatus.failure);
    }
    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    }
    const prepared = &resolved.prepared.?;

    const native_rows = zdisamar.buildAtmosphericBudget(
        allocator,
        &prepared.scene,
        &prepared.prepared,
        wavelengths[0..wavelength_count],
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(native_rows);

    const rows = allocator.alloc(ZdsAtmosphericBudgetRow, native_rows.len) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer allocator.free(rows);
    for (native_rows, rows) |native, *row| row.* = copyAtmosphericBudgetRow(native);

    resolved.atmospheric_budgets.append(allocator, rows) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
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
    const wavelengths = wavelengths_ptr orelse {
        resolved.setError("null wavelengths");
        return @intFromEnum(ZdsStatus.failure);
    };
    if (wavelength_count == 0) {
        resolved.setError("empty wavelengths");
        return @intFromEnum(ZdsStatus.failure);
    }
    if (max_rows == 0) {
        resolved.setError("invalid row limit");
        return @intFromEnum(ZdsStatus.failure);
    }
    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    }
    const prepared = &resolved.prepared.?;

    var native_table = zdisamar.buildO2LineContributions(
        allocator,
        &prepared.prepared,
        wavelengths[0..wavelength_count],
        max_rows,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer native_table.deinit(allocator);

    const rows = allocator.alloc(ZdsO2LineContributionRow, native_table.rows.len) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer allocator.free(rows);
    for (native_table.rows, rows) |native, *row| row.* = copyO2LineContributionRow(native);

    resolved.o2_line_contribution_tables.append(allocator, rows) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved_out.* = .{
        .len = rows.len,
        .total_row_count = native_table.total_row_count,
        .truncated = if (native_table.truncated) 1 else 0,
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

export fn zds_last_error(ctx: ?*Context) [*:0]const u8 {
    const resolved = ctx orelse return "null context";
    return @ptrCast(&resolved.last_error);
}

fn copyAtmosphericBudgetRow(row: zdisamar.AtmosphericBudgetRow) ZdsAtmosphericBudgetRow {
    return .{
        .wavelength_nm = row.wavelength_nm,
        .layer_index = row.layer_index,
        .sublayer_index = row.sublayer_index,
        .global_sublayer_index = row.global_sublayer_index,
        .interval_index_1based = row.interval_index_1based,
        .support_row_kind = @intFromEnum(row.support_row_kind),
        .subcolumn_label = @intFromEnum(row.subcolumn_label),
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
        .cloud_fraction = row.cloud_fraction,
        .gas_absorption_optical_depth = row.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = row.gas_scattering_optical_depth,
        .cia_optical_depth = row.cia_optical_depth,
        .aerosol_optical_depth = row.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = row.aerosol_scattering_optical_depth,
        .aerosol_absorption_optical_depth = row.aerosol_absorption_optical_depth,
        .cloud_optical_depth = row.cloud_optical_depth,
        .cloud_scattering_optical_depth = row.cloud_scattering_optical_depth,
        .cloud_absorption_optical_depth = row.cloud_absorption_optical_depth,
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
