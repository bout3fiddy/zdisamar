const errors = @import("../core/errors.zig");

pub const Surface = struct {
    kind: []const u8 = "lambertian",
    albedo: f64 = 0.0,

    pub fn validate(self: Surface) errors.Error!void {
        if (self.kind.len == 0) {
            return errors.Error.InvalidRequest;
        }
        if (self.albedo < 0.0 or self.albedo > 1.0) {
            return errors.Error.InvalidRequest;
        }
    }
};
