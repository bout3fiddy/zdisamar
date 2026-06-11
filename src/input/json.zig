const errors = @import("../common/errors.zig");

pub fn parseReferenceCaseJson(_: []const u8) !void {
    // parseReferenceCaseJson ---------------------------------------------------------------------------------|
    // Reject JSON input until the package that owns public/API parsing ports that surface.                    |
    // --------------------------------------------------------------------------------------------------------|
    return errors.Error.UnsupportedJsonInput;
}
