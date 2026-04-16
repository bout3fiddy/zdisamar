const data = @import("o2a/data.zig");
const optics = @import("o2a/optics.zig");
const report = @import("o2a/report.zig");
const spectrum = @import("o2a/spectrum.zig");

pub const Case = @import("o2a/case.zig").Case;
pub const Data = data.Data;
pub const Optics = optics.Optics;
pub const Method = @import("o2a/method.zig").Method;
pub const Work = @import("o2a/work.zig").Work;
pub const Result = spectrum.Result;
pub const Report = report.Report;
pub const ForwardProfile = spectrum.ForwardProfile;
pub const RtmControls = @import("o2a/solver.zig").RtmControls;

pub const parity = @import("o2a/data/vendor_parity_yaml.zig");
pub const profile = report.json;

pub fn loadData(
    allocator: @import("std").mem.Allocator,
    case: *const Case,
) !Data {
    return data.loadData(allocator, case);
}

pub fn buildOptics(
    allocator: @import("std").mem.Allocator,
    case: *const Case,
    loaded: *Data,
) !Optics {
    return data.buildOptics(allocator, case, loaded);
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
    return report.writeReport(summary_path, summary);
}
