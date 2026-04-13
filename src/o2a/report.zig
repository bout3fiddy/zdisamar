pub const json = @import("report/json.zig");
pub const Report = json.SummaryReport;
pub const ForwardProfile = @import("../kernels/transport/measurement/types.zig").ForwardProfile;

pub fn writeReport(
    summary_path: []const u8,
    report: Report,
) !void {
    return json.writeSummaryReport(summary_path, report);
}
