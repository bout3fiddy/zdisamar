pub const spectral_ascii = @import("spectral_ascii.zig");
pub const reference_assets = @import("reference_assets.zig");

test "ingest package includes spectral and reference loaders" {
    _ = @import("spectral_ascii.zig");
    _ = @import("reference_assets.zig");
}
