const bundled_data = @import("input/reference_data/bundled/load.zig");
const o2a_reference = @import("input/o2a_reference/root.zig");
const std = @import("std");
const atmospheric_budget = @import("output/atmospheric_budget.zig");
const instrument_response = @import("output/instrument_response.zig");
const o2_o2_cia = @import("output/o2_o2_cia.zig");
const o2_line_contributions = @import("output/o2_line_contributions.zig");
const radiative_transfer_diagnostics = @import("output/radiative_transfer_diagnostics.zig");
const report_json = @import("output/json.zig");
const radiative_transfer = @import("forward_model/radiative_transfer/root.zig");
const measurement = @import("forward_model/instrument_grid/root.zig");
pub const optimal_estimation = @import("optimal_estimation/retrieval.zig");

// root.zig ---------------------------------------------------------------------------------------------------|
// Public Zig module root for the O2 A forward model, diagnostics, and retrieval entry points.                 |
//                                                                                                             |
// called by                                                                                                   |
//   build.zig exposes this file as the zdisamar module                                                        |
//   src/api/c.zig owns the C/Python boundary and converts external handles into these public calls            |
//   validation CLIs and Zig tests import zdisamar directly                                                    |
//                                                                                                             |
// public flow                                                                                                 |
//   defaultO2AInput / parseO2AInputJson / renderDefaultO2AInputJson                                           |
//     -> prepareO2A or prepare                                                                                |
//        -> runO2A / runO2AWithSessionStorage / run                                                           |
//           -> output tables, generated spectra, diagnostic rows, and optional OE results                     |
//                                                                                                             |
// boundary shape                                                                                              |
//   This file is a narrow facade. It names stable public types, forwards preparation and run calls to the     |
//   O2 A/input/forward-model modules, and keeps loading/parsing/report-writing out of the RTM compute path.   |
//   Tests cover the facade export set so non-public helpers stay behind internal and test routers.            |
//                                                                                                             |
// memory                                                                                                      |
//   PreparedInput embeds the input, reference data, optical state, and product workspace owner. Deinit order  |
//   is storage -> optical properties -> reference data so borrowed buffers are released after their users.    |
// ------------------------------------------------------------------------------------------------------------|
pub const Input = @import("input/Scene.zig").Scene;
pub const O2AInput = o2a_reference.O2AInput;
pub const ReferenceData = bundled_data.Data;
pub const OpticalProperties = @import("forward_model/optical_properties/root.zig").PreparedOpticalState;
pub const CalculationStorage = measurement.ProductStorage;
pub const Output = measurement.InstrumentGridProduct;
pub const PreparedO2A = o2a_reference.PreparedO2A;
pub const O2ASessionStorage = o2a_reference.SessionStorage;
pub const DiagnosticReport = report_json.SummaryReport;
pub const AtmosphericBudgetRow = atmospheric_budget.AtmosphericBudgetRow;
pub const InstrumentResponseRow = instrument_response.InstrumentResponseRow;
pub const O2LineContributionRow = o2_line_contributions.O2LineContributionRow;
pub const O2LineContributionTable = o2_line_contributions.O2LineContributionTable;
pub const O2O2CIARow = o2_o2_cia.O2O2CIARow;
pub const RadiativeTransferDiagnosticRow = radiative_transfer_diagnostics.RadiativeTransferDiagnosticRow;
pub const RadiativeTransferSpectrumView = radiative_transfer_diagnostics.SpectrumView;
pub const RadiativeTransferPerformanceThresholds = radiative_transfer.RadiativeTransferPerformanceThresholds;
pub const RadiativeTransferControls = radiative_transfer.RadiativeTransferControls;
pub const RadiativeTransferJacobian = radiative_transfer.Jacobian;

// PreparedInput ----------------------------------------------------------------------------------------------|
// Public owner bundle returned by prepare().                                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 4368 B (4.266 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0.. 671] input              : Input                                                                     |
// [ 672..1679] reference_data     : ReferenceData                                                             |
// [1680..3815] optical_properties: OpticalProperties                                                          |
// [3816..4367] storage            : CalculationStorage                                                        |
//                                                                                                             |
// referenced storage                                                                                          |
//   Embedded owners retain their own buffers; this row owns teardown order.                                   |
//   Backing arrays stay inside those embedded owners.                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 69 cache lines at 64 B per line                                                                 |
// footprint: per instance = 4368 B (4.266 KiB); total also includes referenced storage in each embedded owner |
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
// ------------------------------------------------------------------------------------------------------------|

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

    var optical_properties = try bundled_data.buildOptics(allocator, &reference_data);
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
    rtm_controls: RadiativeTransferControls,
) !Output {
    const rtm_config = try radiative_transfer.prepareSolveConfig(.{
        .derivative_mode = .none,
        .rtm_controls = rtm_controls,
    });

    const view = try measurement.simulateProductWithWorkspace(
        allocator,
        &prepared.storage,
        &prepared.input,
        rtm_config,
        &prepared.optical_properties,
    );
    return view.toOwned(allocator);
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

pub fn runO2AWithSessionStorage(
    allocator: std.mem.Allocator,
    storage: *O2ASessionStorage,
    prepared: *const PreparedO2A,
) !Output {
    return o2a_reference.runO2AWithSessionStorage(allocator, storage, prepared);
}

pub fn warmO2ASessionStorage(
    allocator: std.mem.Allocator,
    storage: *O2ASessionStorage,
    prepared: *const PreparedO2A,
) !void {
    return o2a_reference.warmO2ASessionStorage(allocator, storage, prepared);
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
    rtm_config: radiative_transfer.SolveConfig,
    wavelengths_nm: []const f64,
    spectrum_view: ?RadiativeTransferSpectrumView,
) ![]RadiativeTransferDiagnosticRow {
    return radiative_transfer_diagnostics.build(
        allocator,
        input,
        optical_properties,
        rtm_config,
        wavelengths_nm,
        spectrum_view,
    );
}

pub fn writeReport(summary_path: []const u8, summary: DiagnosticReport) !void {
    return report_json.writeSummaryReport(summary_path, summary);
}
