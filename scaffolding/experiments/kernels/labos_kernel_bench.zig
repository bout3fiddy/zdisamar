const std = @import("std");
const internal = @import("internal");
const timing = internal.common.runtime_io;

const labos = internal.forward_model.radiative_transfer.labos_basis;

const n = 12;
const n_gauss = 10;
const threshold_mul = 1.0e-12;
const phase_scan_max = 15;
const beta_reciprocal = build_beta_reciprocal: {
    var values: [labos.max_phase_coef]f64 = undefined;
    for (&values, 0..) |*value, idx| {
        const idx_f: f64 = @floatFromInt(idx);
        value.* = 1.0 / (2.0 * idx_f + 1.0);
    }
    break :build_beta_reciprocal values;
};

pub fn main(init: std.process.Init) !void {
    var r = matrixSeed(0.008, 0.0003);
    var t = matrixSeed(0.41, 0.0008);
    var c = matrixSeed(0.19, 0.0005);
    var e = vecSeed();
    var geo = labos.Geometry.init(n_gauss, 0.58, 0.64);
    var phase_coefs = phaseCoeffSeed();
    const phase_max_index = phase_scan_max;
    const plm_basis = labos.FourierPlmBasis.init(0, phase_max_index, &geo);

    try runMatBench(init.io, "qseries_12x10", 200_000, &r, &t, &c, &e, benchQseries);
    try runMatBench(init.io, "qseries_nonzero_12x10", 200_000, &r, &t, &c, &e, benchQseriesNonzero);
    try runMatBench(init.io, "smul_12x10", 800_000, &r, &t, &c, &e, benchSmul);
    try runMatBench(init.io, "smulAddSemul3_12", 800_000, &r, &t, &c, &e, benchSmulAddSemul3);
    try runKnownRightTraceBench(init.io, "smulAddSemul3KnownRightTrace_12", 800_000, &r, &t, &e);
    try runMatBench(init.io, "matAddSemul3_12", 3_000_000, &r, &t, &c, &e, benchMatAddSemul3);
    try runMatBench(init.io, "matAddEsmul3_12", 3_000_000, &r, &t, &c, &e, benchMatAddEsmul3);
    try runMatBench(init.io, "matAddEsmul_12", 3_000_000, &r, &t, &c, &e, benchMatAddEsmul);
    try runMatBench(init.io, "semul_12", 3_000_000, &r, &t, &c, &e, benchSemul);
    try runMatBench(init.io, "semulAdd_12", 3_000_000, &r, &t, &c, &e, benchSemulAdd);
    try runMatBench(init.io, "esmulSemul_12", 3_000_000, &r, &t, &c, &e, benchEsmulSemul);
    try runMatBench(init.io, "esmulSemulAdd_12", 3_000_000, &r, &t, &c, &e, benchEsmulSemulAdd);
    try runPhaseBench(init.io, "phase_fill_12x16", 300_000, &phase_coefs, &geo, &plm_basis, benchPhaseFill);
    try runBetaBench(init.io, "phase_beta_scan_div_16", 5_000_000, &phase_coefs, benchBetaScanDiv);
    try runBetaBench(init.io, "phase_beta_scan_recip_16", 5_000_000, &phase_coefs, benchBetaScanRecip);
}

const Kernel = *const fn (*const labos.Mat, *const labos.Mat, *const labos.Mat, *const labos.Vec) labos.Mat;
const PhaseKernel = *const fn (
    *const [labos.max_phase_coef]f64,
    *const labos.Geometry,
    *const labos.FourierPlmBasis,
) labos.PhaseKernel;
const BetaKernel = *const fn (*const [labos.max_phase_coef]f64) f64;

fn runMatBench(
    io: std.Io,
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

    var timer = timing.Timer.start(io);
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

fn runKnownRightTraceBench(
    io: std.Io,
    comptime name: []const u8,
    iterations: usize,
    r: *labos.Mat,
    t: *labos.Mat,
    e: *labos.Vec,
) !void {
    const trace_t = traceGauss12x10(t);
    var warm_checksum: f64 = 0.0;
    for (0..2_000) |_| {
        const result = benchSmulAddSemul3KnownRightTrace(r, e, t, trace_t);
        warm_checksum += checksum(&result);
    }
    std.mem.doNotOptimizeAway(warm_checksum);

    var timer = timing.Timer.start(io);
    var sum: f64 = 0.0;
    for (0..iterations) |_| {
        const result = benchSmulAddSemul3KnownRightTrace(r, e, t, trace_t);
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

fn runPhaseBench(
    io: std.Io,
    comptime name: []const u8,
    iterations: usize,
    phase_coefs: *const [labos.max_phase_coef]f64,
    geo: *const labos.Geometry,
    plm_basis: *const labos.FourierPlmBasis,
    kernel: PhaseKernel,
) !void {
    var warm_checksum: f64 = 0.0;
    for (0..2_000) |_| {
        const result = kernel(phase_coefs, geo, plm_basis);
        warm_checksum += checksumPhase(&result);
    }
    std.mem.doNotOptimizeAway(warm_checksum);

    var timer = timing.Timer.start(io);
    var sum: f64 = 0.0;
    for (0..iterations) |_| {
        const result = kernel(phase_coefs, geo, plm_basis);
        sum += checksumPhase(&result);
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

fn runBetaBench(
    io: std.Io,
    comptime name: []const u8,
    iterations: usize,
    phase_coefs: *const [labos.max_phase_coef]f64,
    kernel: BetaKernel,
) !void {
    var live_coefs = phase_coefs.*;
    var warm_checksum: f64 = 0.0;
    for (0..2_000) |_| {
        std.mem.doNotOptimizeAway(&live_coefs);
        warm_checksum += kernel(&live_coefs);
    }
    std.mem.doNotOptimizeAway(warm_checksum);

    var timer = timing.Timer.start(io);
    var sum: f64 = 0.0;
    for (0..iterations) |_| {
        std.mem.doNotOptimizeAway(&live_coefs);
        sum += kernel(&live_coefs);
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

fn benchSmulAddSemul3(r: *const labos.Mat, t: *const labos.Mat, _: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.smulAddSemul3(n, n_gauss, threshold_mul, r, e, t);
}

fn benchSmulAddSemul3KnownRightTrace(
    r: *const labos.Mat,
    e: *const labos.Vec,
    t: *const labos.Mat,
    trace_t: f64,
) labos.Mat {
    return labos.smulAddSemul3KnownRightTrace(n, n_gauss, threshold_mul, r, e, t, trace_t);
}

fn benchMatAddSemul3(r: *const labos.Mat, t: *const labos.Mat, c: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.matAddSemul3(n, r, t, e, c);
}

fn benchMatAddEsmul3(r: *const labos.Mat, t: *const labos.Mat, c: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.matAddEsmul3(n, r, e, t, c);
}

fn benchMatAddEsmul(r: *const labos.Mat, t: *const labos.Mat, _: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.matAddEsmul(n, r, e, t);
}

fn benchSemul(r: *const labos.Mat, _: *const labos.Mat, _: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.semul(n, r, e);
}

fn benchSemulAdd(r: *const labos.Mat, t: *const labos.Mat, _: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.semulAdd(n, r, e, t);
}

fn benchEsmulSemul(r: *const labos.Mat, t: *const labos.Mat, _: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.esmulSemul(n, e, r, t);
}

fn benchEsmulSemulAdd(r: *const labos.Mat, t: *const labos.Mat, c: *const labos.Mat, e: *const labos.Vec) labos.Mat {
    return labos.esmulSemulAdd(n, e, r, t, c);
}

fn benchPhaseFill(
    phase_coefs: *const [labos.max_phase_coef]f64,
    geo: *const labos.Geometry,
    plm_basis: *const labos.FourierPlmBasis,
) labos.PhaseKernel {
    return labos.fillZplusZminFromBasisLimited(
        0,
        phase_coefs,
        phase_scan_max,
        geo,
        plm_basis,
    );
}

fn benchBetaScanDiv(phase_coefs: *const [labos.max_phase_coef]f64) f64 {
    var max_beta_eff: f64 = 0.0;
    for (0..phase_scan_max + 1) |ic| {
        const icf: f64 = @floatFromInt(ic);
        const beta_eff = @abs(phase_coefs[ic]) / (2.0 * icf + 1.0);
        if (beta_eff > max_beta_eff) max_beta_eff = beta_eff;
    }
    return max_beta_eff;
}

fn benchBetaScanRecip(phase_coefs: *const [labos.max_phase_coef]f64) f64 {
    var max_beta_eff: f64 = 0.0;
    for (0..phase_scan_max + 1) |ic| {
        const beta_eff = @abs(phase_coefs[ic]) * beta_reciprocal[ic];
        if (beta_eff > max_beta_eff) max_beta_eff = beta_eff;
    }
    return max_beta_eff;
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
    var vec = labos.Vec{ .data = undefined };
    for (0..n) |i| {
        vec.data[i] = 0.77 + 0.01 * @as(f64, @floatFromInt(i));
    }
    return vec;
}

fn phaseCoeffSeed() [labos.max_phase_coef]f64 {
    var coefs = [_]f64{0.0} ** labos.max_phase_coef;
    for (0..16) |idx| {
        const i: f64 = @floatFromInt(idx);
        coefs[idx] = 1.0 / (1.0 + 0.17 * i);
    }
    return coefs;
}

fn traceGauss12x10(mat: *const labos.Mat) f64 {
    var trace = mat.data[0];
    trace += mat.data[13];
    trace += mat.data[26];
    trace += mat.data[39];
    trace += mat.data[52];
    trace += mat.data[65];
    trace += mat.data[78];
    trace += mat.data[91];
    trace += mat.data[104];
    trace += mat.data[117];
    return trace;
}

fn checksum(mat: *const labos.Mat) f64 {
    var sum: f64 = 0.0;
    for (mat.data[0 .. n * n], 0..) |value, idx| {
        sum += value * @as(f64, @floatFromInt(idx + 1));
    }
    return sum;
}

fn checksumPhase(kernel: *const labos.PhaseKernel) f64 {
    return checksum(&kernel.Zplus) + 1.7 * checksum(&kernel.Zmin);
}
