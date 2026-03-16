const std = @import("std");

pub const StokesVector = struct {
    i: f64,
    q: f64 = 0.0,
    u: f64 = 0.0,
    v: f64 = 0.0,

    pub fn degreeOfLinearPolarization(self: StokesVector) f64 {
        const numerator = std.math.sqrt(self.q * self.q + self.u * self.u);
        if (self.i == 0.0) return 0.0;
        return numerator / self.i;
    }
};

test "stokes vector reports linear polarization degree" {
    const state = StokesVector{
        .i = 10.0,
        .q = 3.0,
        .u = 4.0,
    };
    try std.testing.expectApproxEqRel(@as(f64, 0.5), state.degreeOfLinearPolarization(), 1e-12);
}
