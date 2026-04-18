const bundled_data = @import("data/bundled/load.zig");
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

pub fn loadData(
    allocator: @import("std").mem.Allocator,
    case: *const Case,
) !Data {
    return bundled_data.load(allocator, case);
}

pub fn buildOptics(
    allocator: @import("std").mem.Allocator,
    case: *const Case,
    loaded: *Data,
) !Optics {
    return bundled_data.buildOptics(allocator, case, loaded);
}

pub fn runSpectrum(
    allocator: @import("std").mem.Allocator,
    case: *const Case,
    prepared_optics: *const Optics,
    work: ?*Work,
    method: Method,
    rtm_controls: RtmControls,
    profile_out: ?*ForwardProfile,
) !Result {
    return spectrum.run(
        allocator,
        case,
        prepared_optics,
        work,
        method,
        rtm_controls,
        profile_out,
    );
}

pub fn writeReport(summary_path: []const u8, summary: Report) !void {
    return report_json.writeSummaryReport(summary_path, summary);
}
