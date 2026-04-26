const bundled_data = @import("data/bundled/load.zig");
const std = @import("std");
const report_json = @import("o2a/report/json.zig");
const spectrum = @import("o2a/spectrum.zig");

pub const Case = @import("model/Scene.zig").Scene;
pub const Data = bundled_data.Data;
pub const Optics = @import("kernels/optics/preparation.zig").PreparedOpticalState;
pub const Method = @import("o2a/method.zig").Method;
pub const Work = @import("kernels/transport/measurement/workspace.zig").SummaryWorkspace;
pub const Result = spectrum.Result;
pub const Report = report_json.SummaryReport;
pub const ForwardProfile = spectrum.ForwardProfile;
pub const RtmControls = @import("kernels/transport/common.zig").RtmControls;

pub const parity = @import("o2a/data/vendor_parity_yaml.zig");
pub const profile = report_json;

pub const Prepared = struct {
    case: Case,
    data: Data,
    optics: Optics,
    work: Work = .{},

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
    rtm_controls: RtmControls,
    profile_out: ?*ForwardProfile,
) !Result {
    return spectrum.run(
        allocator,
        &prepared.case,
        &prepared.optics,
        &prepared.work,
        method,
        rtm_controls,
        profile_out,
    );
}

pub fn writeReport(summary_path: []const u8, summary: Report) !void {
    return report_json.writeSummaryReport(summary_path, summary);
}
