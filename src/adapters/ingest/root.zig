pub const reference_assets = @import("reference_assets.zig");

test "ingest package includes retained reference loaders" {
    _ = @import("reference_assets.zig");
}
