const std = @import("std");
const internal = @import("internal");

const LoadedAsset = internal.input_reference_data.ingest_reference_assets_loaded_asset.LoadedAsset;

test "spectroscopy line-list conversion preserves null vendor metadata fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const column_names = try allocator.alloc([]const u8, 14);
    for ([_][]const u8{
        "gas_index",
        "isotope_number",
        "abundance_fraction",
        "center_wavelength_nm",
        "line_strength_cm2_per_molecule",
        "air_half_width_nm",
        "temperature_exponent",
        "lower_state_energy_cm1",
        "pressure_shift_nm",
        "line_mixing_coefficient",
        "branch_ic1",
        "branch_ic2",
        "rotational_nf",
        "vendor_filter_metadata_from_source",
    }, 0..) |name, index| {
        column_names[index] = try allocator.dupe(u8, name);
    }

    var asset = LoadedAsset{
        .kind = .spectroscopy_line_list,
        .bundle_manifest_path = try allocator.dupe(u8, "test_manifest"),
        .bundle_id = try allocator.dupe(u8, "test_bundle"),
        .owner_package = try allocator.dupe(u8, "test_owner"),
        .asset_id = try allocator.dupe(u8, "test_asset"),
        .asset_path = try allocator.dupe(u8, "test_path"),
        .dataset_id = try allocator.dupe(u8, "test_dataset"),
        .dataset_hash = try allocator.dupe(u8, "test_hash"),
        .column_names = column_names,
        .values = try allocator.dupe(f64, &.{
            7.0,
            1.0,
            0.9973,
            760.0,
            1.0e-20,
            0.0015,
            0.63,
            1800.0,
            0.0,
            0.0,
            std.math.nan(f64),
            std.math.nan(f64),
            std.math.nan(f64),
            0.0,
        }),
        .row_count = 1,
    };

    var line_list = try asset.toSpectroscopyLineList(std.testing.allocator);
    defer line_list.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, null), line_list.lines[0].branch_ic1);
    try std.testing.expectEqual(@as(?u8, null), line_list.lines[0].branch_ic2);
    try std.testing.expectEqual(@as(?u8, null), line_list.lines[0].rotational_nf);
    try std.testing.expect(!line_list.lines[0].vendor_filter_metadata_from_source);
}
