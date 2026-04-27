const bundled_data = @import("data/bundled/load.zig");
const std = @import("std");
const report_json = @import("o2a/report/json.zig");
const spectrum = @import("o2a/spectrum.zig");

pub const Case = @import("model/Scene.zig").Scene;
pub const Data = bundled_data.Data;
pub const Optics = @import("kernels/optics/preparation.zig").PreparedOpticalState;
pub const Method = @import("o2a/method.zig").Method;
pub const RunStorage = @import("kernels/transport/measurement/workspace.zig").SummaryWorkspace;
pub const Result = spectrum.Result;
pub const Report = report_json.SummaryReport;
pub const RadiativeTransferControls = @import("kernels/transport/common.zig").RadiativeTransferControls;
pub const report = report_json;

pub const parity = @import("o2a/data/vendor_parity_yaml.zig");

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
