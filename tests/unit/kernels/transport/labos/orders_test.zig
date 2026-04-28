const std = @import("std");
const internal = @import("internal");

const labos = internal.kernels.transport.labos;
const Geometry = labos.Geometry;
const LayerRT = labos.LayerRT;
const Mat = labos.Mat;
const OrdersWorkspace = labos.OrdersWorkspace;
const ordersScatInto = labos.ordersScatInto;

test "multiple scattering drops the first below-threshold order" {
    const allocator = std.testing.allocator;
    const geo = Geometry.init(2, 0.58, 0.64);
    const nlevel = 2;
    const nmutot = geo.nmutot;
    const UnitAtten = struct {
        pub fn get(_: @This(), _: usize, _: usize, _: usize) f64 {
            return 1.0;
        }
    };

    var rt = [_]LayerRT{
        .{
            .R = Mat.zero(nmutot),
            .T = Mat.zero(nmutot),
        },
        .{
            .R = Mat.zero(nmutot),
            .T = Mat.zero(nmutot),
        },
    };
    for (0..nmutot) |imu| {
        for (0..2) |extra| {
            const source_col = geo.n_gauss + extra;
            rt[0].R.set(imu, source_col, 0.02);
            rt[1].R.set(imu, source_col, 0.01);
            rt[1].T.set(imu, source_col, 0.03);
        }
        for (0..geo.n_gauss) |gauss_col| {
            rt[0].R.set(imu, gauss_col, 0.02);
            rt[1].R.set(imu, gauss_col, 0.01);
            rt[1].T.set(imu, gauss_col, 0.03);
        }
    }

    var single_workspace = try OrdersWorkspace.init(allocator, nlevel);
    defer single_workspace.deinit();
    var multiple_workspace = try OrdersWorkspace.init(allocator, nlevel);
    defer multiple_workspace.deinit();

    const single_result = ordersScatInto(
        &single_workspace,
        0,
        1,
        &geo,
        UnitAtten{},
        &rt,
        .{
            .scattering = .single,
            .threshold_conv_first = 1.0e-12,
            .threshold_conv_mult = 1.0,
        },
        20,
    );
    const multiple_result = ordersScatInto(
        &multiple_workspace,
        0,
        1,
        &geo,
        UnitAtten{},
        &rt,
        .{
            .scattering = .multiple,
            .threshold_conv_first = 1.0e-12,
            .threshold_conv_mult = 1.0,
        },
        20,
    );

    for (0..nlevel) |ilevel| {
        for (0..2) |col| {
            for (0..nmutot) |imu| {
                try std.testing.expectApproxEqAbs(
                    single_result.ud[ilevel].U.col[col].get(imu),
                    multiple_result.ud[ilevel].U.col[col].get(imu),
                    1.0e-15,
                );
                try std.testing.expectApproxEqAbs(
                    single_result.ud[ilevel].D.col[col].get(imu),
                    multiple_result.ud[ilevel].D.col[col].get(imu),
                    1.0e-15,
                );
            }
        }
    }
}
