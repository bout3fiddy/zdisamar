const std = @import("std");
const ExportView = @import("spec.zig").ExportView;
const io = @import("io.zig");

pub const DiagnosticFormat = enum {
    csv,
    text,
};

pub const Error = io.Error || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.WriteError || std.fs.Dir.MakeError;

pub const DiagnosticReport = struct {
    destination_uri: []const u8,
    format: DiagnosticFormat,
    bytes_written: usize,
};

pub fn write(
    destination_uri: []const u8,
    format: DiagnosticFormat,
    view: ExportView,
    allocator: std.mem.Allocator,
) Error!DiagnosticReport {
    const path = try io.filePathFromUri(destination_uri);
    const payload = switch (format) {
        .csv => try renderCsv(allocator, view),
        .text => try renderText(allocator, view),
    };
    defer allocator.free(payload);

    const bytes_written = try io.writeTextFile(path, payload);
    return .{
        .destination_uri = destination_uri,
        .format = format,
        .bytes_written = bytes_written,
    };
}

fn renderCsv(allocator: std.mem.Allocator, view: ExportView) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "plan_id,scene_id,workspace_label,model_family,solver_route,status,plugin_count,dataset_hash_count\n{d},{s},{s},{s},{s},{s},{d},{d}\n",
        .{
            view.plan_id,
            view.scene_id,
            view.workspace_label,
            view.provenance.model_family,
            view.provenance.solver_route,
            @tagName(view.status),
            view.provenance.pluginVersionCount(),
            view.provenance.dataset_hashes.len,
        },
    );
}

fn renderText(allocator: std.mem.Allocator, view: ExportView) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "plan_id: {d}\nscene_id: {s}\nworkspace_label: {s}\nmodel_family: {s}\nsolver_route: {s}\nstatus: {s}\nplugin_count: {d}\ndataset_hash_count: {d}\n",
        .{
            view.plan_id,
            view.scene_id,
            view.workspace_label,
            view.provenance.model_family,
            view.provenance.solver_route,
            @tagName(view.status),
            view.provenance.pluginVersionCount(),
            view.provenance.dataset_hashes.len,
        },
    );
}

test "diagnostic exporter renders csv and text payloads" {
    const result = @import("../../core/Result.zig").Result.init(3, "diag-ws", "diag-scene", .{
        .plan_id = 3,
        .workspace_label = "diag-ws",
        .scene_id = "diag-scene",
    });

    const csv = try renderCsv(std.testing.allocator, ExportView.fromResult(&result));
    defer std.testing.allocator.free(csv);
    try std.testing.expect(std.mem.startsWith(u8, csv, "plan_id,scene_id"));

    const text = try renderText(std.testing.allocator, ExportView.fromResult(&result));
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "scene_id: diag-scene"));
}
