const bundled_data = @import("input/reference_data/bundled/load.zig");
const std = @import("std");
const report_json = @import("output/json.zig");
const spectrum = @import("forward_model/run_spectrum.zig");

pub const Case = @import("input/Scene.zig").Scene;
pub const Data = bundled_data.Data;
pub const Optics = @import("forward_model/optical_properties/root.zig").PreparedOpticalState;
pub const Method = @import("forward_model/method.zig").Method;
pub const RunStorage = @import("forward_model/instrument_grid/grid_calculation/workspace.zig").SummaryWorkspace;
pub const Result = spectrum.Result;
pub const Report = report_json.SummaryReport;
pub const RadiativeTransferControls = @import("forward_model/radiative_transfer/root.zig").RadiativeTransferControls;
pub const report = report_json;

pub const parity = @import("validation/disamar_reference/yaml.zig");

pub const Prepared = struct {
    case: Case,
    data: Data,
    optics: Optics,
    work: RunStorage = .{},

    pub fn deinit(self: *Prepared, allocator: std.mem.Allocator) void {
        self.work.deinit(allocator);
        self.optics.deinit(allocator);
        self.data.deinit(allocator);
        self.* = undefined;
    }
};

pub fn prepare(
    allocator: std.mem.Allocator,
    case: *const Case,
) !Prepared {
    var data = try bundled_data.load(allocator, case);
    errdefer data.deinit(allocator);

    var optics = try bundled_data.buildOptics(allocator, &data.working_case, &data);
    errdefer optics.deinit(allocator);

    return .{
        .case = data.working_case,
        .data = data,
        .optics = optics,
        .work = .{},
    };
}

pub fn run(
    allocator: std.mem.Allocator,
    prepared: *Prepared,
    method: Method,
    rtm_controls: RadiativeTransferControls,
) !Result {
    return spectrum.run(
        allocator,
        &prepared.case,
        &prepared.optics,
        &prepared.work,
        method,
        rtm_controls,
    );
}

pub fn writeReport(summary_path: []const u8, summary: Report) !void {
    return report_json.writeSummaryReport(summary_path, summary);
}
