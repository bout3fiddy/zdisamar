const Diagnostics = @import("diagnostics.zig").Diagnostics;
const Provenance = @import("provenance.zig").Provenance;
const MeasurementSpaceSummary = @import("../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;

pub const Result = struct {
    pub const Status = enum {
        success,
        invalid_request,
        internal_error,
    };

    status: Status = .success,
    plan_id: u64,
    workspace_label: []const u8,
    scene_id: []const u8,
    provenance: Provenance = .{},
    diagnostics: Diagnostics = .{},
    measurement_space: ?MeasurementSpaceSummary = null,

    pub fn init(
        plan_id: u64,
        workspace_label: []const u8,
        scene_id: []const u8,
        provenance: Provenance,
    ) Result {
        return .{
            .plan_id = plan_id,
            .workspace_label = workspace_label,
            .scene_id = scene_id,
            .provenance = provenance,
            .diagnostics = Diagnostics.fromSpec(.{ .provenance = true }, "Prepared transport routing and provenance are wired; full transport and retrieval numerics remain scaffold-only."),
        };
    }
};
