const bundled_data = @import("input/reference_data/bundled/load.zig");
const std = @import("std");
const report_json = @import("output/json.zig");
const spectrum = @import("forward_model/run_spectrum.zig");

pub const Input = @import("input/Scene.zig").Scene;
pub const ReferenceData = bundled_data.Data;
pub const OpticalProperties = @import("forward_model/optical_properties/root.zig").PreparedOpticalState;
pub const Method = @import("forward_model/method.zig").Method;
pub const CalculationStorage = @import("forward_model/instrument_grid/grid_calculation/storage.zig").SummaryStorage;
pub const Output = spectrum.Result;
pub const DiagnosticReport = report_json.SummaryReport;
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
pub const report = report_json;

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

pub fn writeReport(summary_path: []const u8, summary: DiagnosticReport) !void {
    return report_json.writeSummaryReport(summary_path, summary);
}
