const bundled_data = @import("input/reference_data/bundled/load.zig");
const o2a_reference = @import("input/o2a_reference/root.zig");
const std = @import("std");
const atmospheric_budget = @import("output/atmospheric_budget.zig");
const instrument_response = @import("output/instrument_response.zig");
const o2_o2_cia = @import("output/o2_o2_cia.zig");
const o2_line_contributions = @import("output/o2_line_contributions.zig");
const radiative_transfer_diagnostics = @import("output/radiative_transfer_diagnostics.zig");
const report_json = @import("output/json.zig");
const spectrum = @import("forward_model/run_spectrum.zig");

pub const Input = @import("input/Scene.zig").Scene;
pub const O2AInput = o2a_reference.O2AInput;
pub const ReferenceData = bundled_data.Data;
pub const OpticalProperties = @import("forward_model/optical_properties/root.zig").PreparedOpticalState;
pub const Method = @import("forward_model/method.zig").Method;
pub const CalculationStorage = @import("forward_model/instrument_grid/grid_calculation/storage.zig").SummaryStorage;
pub const Output = spectrum.Result;
pub const PreparedO2A = o2a_reference.PreparedO2A;
pub const DiagnosticReport = report_json.SummaryReport;
pub const AtmosphericBudgetRow = atmospheric_budget.AtmosphericBudgetRow;
pub const InstrumentResponseRow = instrument_response.InstrumentResponseRow;
pub const O2LineContributionRow = o2_line_contributions.O2LineContributionRow;
pub const O2LineContributionTable = o2_line_contributions.O2LineContributionTable;
pub const O2O2CIARow = o2_o2_cia.O2O2CIARow;
pub const RadiativeTransferDiagnosticRow = radiative_transfer_diagnostics.RadiativeTransferDiagnosticRow;
pub const RadiativeTransferSpectrumView = radiative_transfer_diagnostics.SpectrumView;
pub const RadiativeTransferControls = @import("forward_model/radiative_transfer/root.zig").RadiativeTransferControls;
pub const PreparedInput = struct {
    input: Input,
    reference_data: ReferenceData,
    optical_properties: OpticalProperties,
    storage: CalculationStorage = .{},

    pub fn deinit(self: *PreparedInput, allocator: std.mem.Allocator) void {
        self.storage.deinit(allocator);
        self.optical_properties.deinit(allocator);
        self.reference_data.deinit(allocator);
        self.* = undefined;
    }
};

pub const disamar_reference = @import("validation/disamar_reference/yaml.zig");
pub const o2a = o2a_reference;
pub const report = report_json;
pub const atmospheric_budget_table = atmospheric_budget;
pub const instrument_response_table = instrument_response;
pub const o2_line_contribution_table = o2_line_contributions;
pub const o2_o2_cia_table = o2_o2_cia;
pub const radiative_transfer_diagnostic_table = radiative_transfer_diagnostics;

pub fn prepare(
    allocator: std.mem.Allocator,
    input: *const Input,
) !PreparedInput {
    var reference_data = try bundled_data.load(allocator, input);
    errdefer reference_data.deinit(allocator);

    var optical_properties = try bundled_data.buildOptics(allocator, &reference_data.working_case, &reference_data);
    errdefer optical_properties.deinit(allocator);

    return .{
        .input = reference_data.working_case,
        .reference_data = reference_data,
        .optical_properties = optical_properties,
        .storage = .{},
    };
}

pub fn run(
    allocator: std.mem.Allocator,
    prepared: *PreparedInput,
    method: Method,
    rtm_controls: RadiativeTransferControls,
) !Output {
    return spectrum.run(
        allocator,
        &prepared.input,
        &prepared.optical_properties,
        &prepared.storage,
        method,
        rtm_controls,
    );
}

pub fn defaultO2AInput() O2AInput {
    return o2a_reference.defaultInput();
}

pub fn parseO2AInputJson(
    allocator: std.mem.Allocator,
    json: []const u8,
) !std.json.Parsed(O2AInput) {
    return o2a_reference.parseInputJson(allocator, json);
}

pub fn renderDefaultO2AInputJson(allocator: std.mem.Allocator) ![]u8 {
    return o2a_reference.renderDefaultInputJson(allocator);
}

pub fn prepareO2A(
    allocator: std.mem.Allocator,
    input: *const O2AInput,
) !PreparedO2A {
    return o2a_reference.prepareO2A(allocator, input);
}

pub fn runO2A(
    allocator: std.mem.Allocator,
    prepared: *const PreparedO2A,
) !Output {
    return o2a_reference.runO2A(allocator, prepared);
}

pub fn buildAtmosphericBudget(
    allocator: std.mem.Allocator,
    input: *const Input,
    optical_properties: *const OpticalProperties,
    wavelengths_nm: []const f64,
) ![]AtmosphericBudgetRow {
    return atmospheric_budget.build(allocator, input, optical_properties, wavelengths_nm);
}

pub fn buildO2LineContributions(
    allocator: std.mem.Allocator,
    optical_properties: *const OpticalProperties,
    wavelengths_nm: []const f64,
    max_rows: usize,
) !O2LineContributionTable {
    return o2_line_contributions.build(allocator, optical_properties, wavelengths_nm, max_rows);
}

pub fn buildInstrumentResponse(
    allocator: std.mem.Allocator,
    input: *const Input,
    optical_properties: *const OpticalProperties,
    wavelengths_nm: []const f64,
    channel_mask: u32,
) ![]InstrumentResponseRow {
    return instrument_response.build(allocator, input, optical_properties, wavelengths_nm, channel_mask);
}

pub fn buildO2O2CIADiagnostics(
    allocator: std.mem.Allocator,
    input: *const Input,
    optical_properties: *const OpticalProperties,
    wavelengths_nm: []const f64,
) ![]O2O2CIARow {
    return o2_o2_cia.build(allocator, input, optical_properties, wavelengths_nm);
}

pub fn buildRadiativeTransferDiagnostics(
    allocator: std.mem.Allocator,
    input: *const Input,
    optical_properties: *const OpticalProperties,
    route: @import("forward_model/radiative_transfer/root.zig").Route,
    wavelengths_nm: []const f64,
    spectrum_view: ?RadiativeTransferSpectrumView,
) ![]RadiativeTransferDiagnosticRow {
    return radiative_transfer_diagnostics.build(
        allocator,
        input,
        optical_properties,
        route,
        wavelengths_nm,
        spectrum_view,
    );
}

pub fn writeReport(summary_path: []const u8, summary: DiagnosticReport) !void {
    return report_json.writeSummaryReport(summary_path, summary);
}
