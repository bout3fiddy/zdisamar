const std = @import("std");
const internal = @import("internal");

const labos = internal.forward_model.radiative_transfer.labos.internal.basis;

const n = 12;
const n_gauss = 10;
const threshold_mul = 1.0e-12;

pub fn main() !void {
    var r = matrixSeed(0.008, 0.0003);
    var t = matrixSeed(0.41, 0.0008);
    var c = matrixSeed(0.19, 0.0005);
    var e = vecSeed();

    try runMatBench("qseries_12x10", 200_000, &r, &t, &c, &e, benchQseries);
    try runMatBench("qseries_nonzero_12x10", 200_000, &r, &t, &c, &e, benchQseriesNonzero);
    try runMatBench("smul_12x10", 800_000, &r, &t, &c, &e, benchSmul);
    try runMatBench("matAddSemul3_12", 3_000_000, &r, &t, &c, &e, benchMatAddSemul3);
    try runMatBench("matAddEsmul3_12", 3_000_000, &r, &t, &c, &e, benchMatAddEsmul3);
    try runMatBench("semulAdd_12", 3_000_000, &r, &t, &c, &e, benchSemulAdd);
    try runMatBench("esmulSemulAdd_12", 3_000_000, &r, &t, &c, &e, benchEsmulSemulAdd);
}

const Kernel = *const fn (*const labos.Mat, *const labos.Mat, *const labos.Mat, *const labos.Vec) labos.Mat;

fn runMatBench(
    comptime name: []const u8,
    iterations: usize,
    r: *labos.Mat,
    t: *labos.Mat,
    c: *labos.Mat,
    e: *labos.Vec,
    kernel: Kernel,
) !void {
    var warm_checksum: f64 = 0.0;
    for (0..2_000) |_| {
        const result = kernel(r, t, c, e);
        warm_checksum += checksum(&result);
    }
    std.mem.doNotOptimizeAway(warm_checksum);

    var timer = try std.time.Timer.start();
    var sum: f64 = 0.0;
    for (0..iterations) |_| {
        const result = kernel(r, t, c, e);
        sum += checksum(&result);
    }
    const elapsed_ns = timer.read();
    std.mem.doNotOptimizeAway(sum);

    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1.0e6;
    const ns_per_call = @as(f64, @floatFromInt(elapsed_ns)) /
        @as(f64, @floatFromInt(iterations));
    std.debug.print(
        "{s}: iterations={} elapsed_ms={d:.3} ns_per_call={d:.3} checksum={d:.12}\n",
        .{ name, iterations, elapsed_ms, ns_per_call, sum },
    );
}

fn benchQseries(r: *const labos.Mat, _: *const labos.Mat, _: *const labos.Mat, _: *const labos.Vec) labos.Mat {
    return labos.qseries(n, n_gauss, threshold_mul, r, r);
}

fn benchQseriesNonzero(r: *const labos.Mat, _: *const labos.Mat, _: *const labos.Mat, _: *const labos.Vec) labos.Mat {
    return labos.qseriesKnownNonzeroProduct(n, n_gauss, r, r);
}

fn benchSmul(r: *const labos.Mat, t: *const labos.Mat, _: *const labos.Mat, _: *const labos.Vec) labos.Mat {
    return labos.smul(n, n_gauss, threshold_mul, r, t);
}

fn benchMatAddSemul3(r: *const labos.Mat, t: *const labos.Mat, c: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.matAddSemul3(n, r, t, e, c);
}

fn benchMatAddEsmul3(r: *const labos.Mat, t: *const labos.Mat, c: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.matAddEsmul3(n, r, e, t, c);
}

fn benchSemulAdd(r: *const labos.Mat, t: *const labos.Mat, _: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.semulAdd(n, r, e, t);
}

fn benchEsmulSemulAdd(r: *const labos.Mat, t: *const labos.Mat, c: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.esmulSemulAdd(n, e, r, t, c);
}

fn matrixSeed(base: f64, delta: f64) labos.Mat {
    var mat = labos.Mat{ .data = undefined, .n = n };
    for (0..n) |i| {
        for (0..n) |j| {
            const linear = @as(f64, @floatFromInt(i * n + j + 1));
            const diagonal: f64 = if (i == j and i < n_gauss) base else 0.0;
            mat.data[i * n + j] = diagonal + delta * linear;
        }
    }
    return mat;
}

fn vecSeed() labos.Vec {
    var vec = labos.Vec{ .data = undefined, .n = n };
    for (0..n) |i| {
        vec.data[i] = 0.77 + 0.01 * @as(f64, @floatFromInt(i));
    }
    return vec;
}

fn checksum(mat: *const labos.Mat) f64 {
    var sum: f64 = 0.0;
    for (mat.data[0 .. n * n], 0..) |value, idx| {
        sum += value * @as(f64, @floatFromInt(idx + 1));
    }
    return sum;
}
