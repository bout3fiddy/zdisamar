const std = @import("std");
const builtin = @import("builtin");

const n = 12;
const n_gauss = 10;
const threshold_mul = 1.0e-12;
const threshold_q = 1.0e-14;

const Mat = struct {
    data: [n * n]f64,
};

const Vec = struct {
    data: [n]f64,
};

const DotPair = struct {
    col0: f64,
    col1: f64,
};

const Kernel = *const fn () callconv(.c) void;
const Checksum = *const fn () f64;

const bench_names = [_][]const u8{
    "smul_12x10",
    "smul_add_semul3_12",
    "smul_add_semul3_known_right_trace_12",
    "qseries_nonzero_12x10",
    "dot_gauss_pair",
};

const bench_iterations = [_]usize{
    1_000_000,
    1_000_000,
    1_000_000,
    200_000,
    20_000_000,
};

var kernels = [_]Kernel{
    codegen_smul12x10,
    codegen_smul_add_semul3_12,
    codegen_smul_add_semul3_known_right_trace_12,
    codegen_qseries_nonzero_12x10,
    codegen_dot_gauss_pair,
};

var checksums = [_]Checksum{
    checksumMatrix,
    checksumMatrix,
    checksumMatrix,
    checksumMatrix,
    checksumPair,
};

var matrix_a: Mat = undefined;
var matrix_b: Mat = undefined;
var matrix_c: Mat = undefined;
var matrix_c_trace: f64 = undefined;
var vector_e: Vec = undefined;
var vector_u0: Vec = undefined;
var vector_u1: Vec = undefined;
var matrix_out: Mat = undefined;
var pair_out: DotPair = undefined;

pub fn main(init: std.process.Init) !void {
    seedInputs();

    std.debug.print(
        "# zig={s} optimize=ReleaseFast arch={s} os={s}\n",
        .{
            builtin.zig_version_string,
            @tagName(builtin.cpu.arch),
            @tagName(builtin.os.tag),
        },
    );
    std.debug.print("operation,iterations,elapsed_ns,ns_per_call,checksum\n", .{});

    for (bench_names, bench_iterations, kernels, checksums) |name, iterations, kernel, checksum| {
        try runBench(init.io, name, iterations, kernel, checksum);
    }
}

fn runBench(
    io: std.Io,
    name: []const u8,
    iterations: usize,
    kernel: Kernel,
    checksum: Checksum,
) !void {
    var warm_sum: f64 = 0.0;
    for (0..2_000) |_| {
        kernel();
        warm_sum += checksum();
    }
    std.mem.doNotOptimizeAway(warm_sum);

    const start = std.Io.Clock.boot.now(io);
    var sum: f64 = 0.0;
    for (0..iterations) |_| {
        kernel();
        sum += checksum();
    }
    const elapsed_raw_ns = start.durationTo(std.Io.Clock.boot.now(io)).toNanoseconds();
    const elapsed_ns = if (elapsed_raw_ns <= 0)
        0
    else
        std.math.cast(u64, elapsed_raw_ns) orelse std.math.maxInt(u64);
    std.mem.doNotOptimizeAway(sum);

    const ns_per_call =
        @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations));
    std.debug.print(
        "{s},{},{},{d:.6},{d:.12}\n",
        .{ name, iterations, elapsed_ns, ns_per_call, sum },
    );
}

pub export fn codegen_smul12x10() void {
    smul12x10Into(&matrix_out, &matrix_a, &matrix_b);
}

pub export fn codegen_smul_add_semul3_12() void {
    matrix_out = smulAddSemul3_12(&matrix_a, &vector_e, &matrix_c);
}

pub export fn codegen_smul_add_semul3_known_right_trace_12() void {
    matrix_out = smulAddSemul3_12KnownRightTrace(&matrix_a, &vector_e, &matrix_c, matrix_c_trace);
}

pub export fn codegen_qseries_nonzero_12x10() void {
    const ab = smul12x10(&matrix_a, &matrix_b);
    matrix_out = qseriesFromProduct(&ab);
}

pub export fn codegen_dot_gauss_pair() void {
    pair_out = dotGaussPair(&matrix_a, 5, &vector_u0, &vector_u1);
}

inline fn smul12x10(a: *const Mat, b: *const Mat) Mat {
    var result: Mat = undefined;
    smul12x10Into(&result, a, b);
    return result;
}

inline fn smul12x10Into(noalias result: *Mat, a: *const Mat, b: *const Mat) void {
    inline for (0..12) |i| {
        const row = i * 12;
        const a0: @Vector(2, f64) = @splat(a.data[row]);
        const a1: @Vector(2, f64) = @splat(a.data[row + 1]);
        const a2: @Vector(2, f64) = @splat(a.data[row + 2]);
        const a3: @Vector(2, f64) = @splat(a.data[row + 3]);
        const a4: @Vector(2, f64) = @splat(a.data[row + 4]);
        const a5: @Vector(2, f64) = @splat(a.data[row + 5]);
        const a6: @Vector(2, f64) = @splat(a.data[row + 6]);
        const a7: @Vector(2, f64) = @splat(a.data[row + 7]);
        const a8: @Vector(2, f64) = @splat(a.data[row + 8]);
        const a9: @Vector(2, f64) = @splat(a.data[row + 9]);
        const b0 = b.data[0..12];
        const b1 = b.data[12..24];
        const b2 = b.data[24..36];
        const b3 = b.data[36..48];
        const b4 = b.data[48..60];
        const b5 = b.data[60..72];
        const b6 = b.data[72..84];
        const b7 = b.data[84..96];
        const b8 = b.data[96..108];
        const b9 = b.data[108..120];
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;
            var s = a0 * loadPair(b0, j);
            s += a1 * loadPair(b1, j);
            s += a2 * loadPair(b2, j);
            s += a3 * loadPair(b3, j);
            s += a4 * loadPair(b4, j);
            s += a5 * loadPair(b5, j);
            s += a6 * loadPair(b6, j);
            s += a7 * loadPair(b7, j);
            s += a8 * loadPair(b8, j);
            s += a9 * loadPair(b9, j);
            result.data[row + j] = s[0];
            result.data[row + j + 1] = s[1];
        }
    }
}

inline fn loadPair(row: []const f64, comptime j: usize) @Vector(2, f64) {
    return .{ row[j], row[j + 1] };
}

fn smulAddSemul3_12(a: *const Mat, e: *const Vec, c: *const Mat) Mat {
    var tra = a.data[0];
    tra += a.data[13];
    tra += a.data[26];
    tra += a.data[39];
    tra += a.data[52];
    tra += a.data[65];
    tra += a.data[78];
    tra += a.data[91];
    tra += a.data[104];
    tra += a.data[117];

    var trc = c.data[0];
    trc += c.data[13];
    trc += c.data[26];
    trc += c.data[39];
    trc += c.data[52];
    trc += c.data[65];
    trc += c.data[78];
    trc += c.data[91];
    trc += c.data[104];
    trc += c.data[117];

    return smulAddSemul3_12KnownTraces(a, e, c, tra, trc);
}

fn smulAddSemul3_12KnownRightTrace(a: *const Mat, e: *const Vec, c: *const Mat, trc: f64) Mat {
    var tra = a.data[0];
    tra += a.data[13];
    tra += a.data[26];
    tra += a.data[39];
    tra += a.data[52];
    tra += a.data[65];
    tra += a.data[78];
    tra += a.data[91];
    tra += a.data[104];
    tra += a.data[117];

    return smulAddSemul3_12KnownTraces(a, e, c, tra, trc);
}

fn smulAddSemul3_12KnownTraces(a: *const Mat, e: *const Vec, c: *const Mat, tra: f64, trc: f64) Mat {
    var result: Mat = undefined;
    if (@abs(tra * trc) <= threshold_mul) {
        inline for (0..12) |j| {
            const ej = e.data[j];
            var idx = j;
            inline for (0..12) |_| {
                result.data[idx] = c.data[idx] + a.data[idx] * ej;
                idx += 12;
            }
        }
        return result;
    }

    inline for (0..12) |i| {
        const row = i * 12;
        const a0 = a.data[row];
        const a1 = a.data[row + 1];
        const a2 = a.data[row + 2];
        const a3 = a.data[row + 3];
        const a4 = a.data[row + 4];
        const a5 = a.data[row + 5];
        const a6 = a.data[row + 6];
        const a7 = a.data[row + 7];
        const a8 = a.data[row + 8];
        const a9 = a.data[row + 9];
        const c0 = c.data[0..12];
        const c1 = c.data[12..24];
        const c2 = c.data[24..36];
        const c3 = c.data[36..48];
        const c4 = c.data[48..60];
        const c5 = c.data[60..72];
        const c6 = c.data[72..84];
        const c7 = c.data[84..96];
        const c8 = c.data[96..108];
        const c9 = c.data[108..120];
        inline for (0..12) |j| {
            var s = a0 * c0[j];
            s += a1 * c1[j];
            s += a2 * c2[j];
            s += a3 * c3[j];
            s += a4 * c4[j];
            s += a5 * c5[j];
            s += a6 * c6[j];
            s += a7 * c7[j];
            s += a8 * c8[j];
            s += a9 * c9[j];
            const idx = row + j;
            result.data[idx] = (c.data[idx] + a.data[idx] * e.data[j]) + s;
        }
    }
    return result;
}

fn qseriesFromProduct(ab: *const Mat) Mat {
    var trace = ab.data[0];
    trace += ab.data[13];
    trace += ab.data[26];
    trace += ab.data[39];
    trace += ab.data[52];
    trace += ab.data[65];
    trace += ab.data[78];
    trace += ab.data[91];
    trace += ab.data[104];
    trace += ab.data[117];
    if (@abs(trace) < threshold_q) return ab.*;

    var one_minus_ab_gg: [n_gauss * n_gauss]f64 = undefined;
    inline for (0..n_gauss) |i| {
        inline for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            one_minus_ab_gg[i * n_gauss + j] = delta - ab.data[i * n + j];
        }
    }

    var pivot: [n_gauss]usize = undefined;
    var pivot_offset: [n_gauss]usize = undefined;
    var inverse_diag: [n_gauss]f64 = undefined;
    inline for (0..n_gauss) |i| {
        pivot[i] = i;
        pivot_offset[i] = i * n_gauss;
    }

    for (0..n_gauss) |col| {
        var max_val: f64 = @abs(one_minus_ab_gg[pivot_offset[col] + col]);
        var max_row: usize = col;
        for (col + 1..n_gauss) |row| {
            const val = @abs(one_minus_ab_gg[pivot_offset[row] + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }
        if (max_row != col) {
            const tmp = pivot[col];
            pivot[col] = pivot[max_row];
            pivot[max_row] = tmp;
            const tmp_offset = pivot_offset[col];
            pivot_offset[col] = pivot_offset[max_row];
            pivot_offset[max_row] = tmp_offset;
        }
        const diag = one_minus_ab_gg[pivot_offset[col] + col];
        if (@abs(diag) < 1.0e-30) return ab.*;
        const inv_diag = 1.0 / diag;
        inverse_diag[col] = inv_diag;
        for (col + 1..n_gauss) |row| {
            const row_offset = pivot_offset[row];
            const col_offset = pivot_offset[col];
            const factor = one_minus_ab_gg[row_offset + col] * inv_diag;
            one_minus_ab_gg[row_offset + col] = factor;
            for (col + 1..n_gauss) |k| {
                one_minus_ab_gg[row_offset + k] -=
                    factor * one_minus_ab_gg[col_offset + k];
            }
        }
    }

    var inverse: [n_gauss * n_gauss]f64 = undefined;
    for (0..n_gauss) |rhs_col| {
        var y: [n_gauss]f64 = undefined;
        for (0..n_gauss) |i| {
            var s: f64 = if (pivot[i] == rhs_col) 1.0 else 0.0;
            const row_offset = pivot_offset[i];
            for (0..i) |j| s -= one_minus_ab_gg[row_offset + j] * y[j];
            y[i] = s;
        }

        var x: [n_gauss]f64 = undefined;
        var ii: usize = n_gauss;
        while (ii > 0) {
            ii -= 1;
            var s: f64 = y[ii];
            const row_offset = pivot_offset[ii];
            for (ii + 1..n_gauss) |j| s -= one_minus_ab_gg[row_offset + j] * x[j];
            x[ii] = s * inverse_diag[ii];
        }
        for (0..n_gauss) |i| inverse[i * n_gauss + rhs_col] = x[i];
    }

    var result: Mat = undefined;
    inline for (0..n_gauss) |i| {
        inline for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            result.data[i * n + j] = inverse[i * n_gauss + j] - delta;
        }
    }

    inline for (0..2) |ja| {
        const j = n_gauss + ja;
        inline for (0..n_gauss) |i| {
            var s: f64 = 0.0;
            inline for (0..n_gauss) |k| {
                s += inverse[i * n_gauss + k] * ab.data[k * n + j];
            }
            result.data[i * n + j] = s;
        }
    }

    var tmp: [2 * n_gauss]f64 = undefined;
    inline for (0..2) |ia| {
        inline for (0..n_gauss) |j| {
            var s: f64 = 0.0;
            inline for (0..n_gauss) |k| {
                s += ab.data[(n_gauss + ia) * n + k] * inverse[k * n_gauss + j];
            }
            tmp[ia * n_gauss + j] = s;
            result.data[(n_gauss + ia) * n + j] = s;
        }
    }

    inline for (0..2) |ia| {
        const i = n_gauss + ia;
        inline for (0..2) |ja| {
            const j = n_gauss + ja;
            var s: f64 = 0.0;
            inline for (0..n_gauss) |k| {
                s += tmp[ia * n_gauss + k] * ab.data[k * n + j];
            }
            result.data[i * n + j] = s + ab.data[i * n + j];
        }
    }

    return result;
}

fn dotGaussPair(
    mat: *const Mat,
    row: usize,
    vec_col0: *const Vec,
    vec_col1: *const Vec,
) DotPair {
    const data = mat.data[row * n ..];
    const vec0 = vec_col0.data;
    const vec1 = vec_col1.data;
    var s0 = data[0] * vec0[0];
    var s1 = data[0] * vec1[0];
    s0 += data[1] * vec0[1];
    s1 += data[1] * vec1[1];
    s0 += data[2] * vec0[2];
    s1 += data[2] * vec1[2];
    s0 += data[3] * vec0[3];
    s1 += data[3] * vec1[3];
    s0 += data[4] * vec0[4];
    s1 += data[4] * vec1[4];
    s0 += data[5] * vec0[5];
    s1 += data[5] * vec1[5];
    s0 += data[6] * vec0[6];
    s1 += data[6] * vec1[6];
    s0 += data[7] * vec0[7];
    s1 += data[7] * vec1[7];
    s0 += data[8] * vec0[8];
    s1 += data[8] * vec1[8];
    s0 += data[9] * vec0[9];
    s1 += data[9] * vec1[9];
    return .{ .col0 = s0, .col1 = s1 };
}

fn seedInputs() void {
    matrix_a = matrixSeed(0.008, 0.0003);
    matrix_b = matrixSeed(0.17, 0.0005);
    matrix_c = matrixSeed(0.41, 0.0008);
    matrix_c_trace = traceGauss12x10(&matrix_c);
    vector_e = vectorSeed(0.77, 0.010);
    vector_u0 = vectorSeed(0.19, 0.007);
    vector_u1 = vectorSeed(0.31, 0.009);
}

fn traceGauss12x10(mat: *const Mat) f64 {
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

fn matrixSeed(base: f64, delta: f64) Mat {
    var mat: Mat = undefined;
    inline for (0..n) |i| {
        inline for (0..n) |j| {
            const linear = @as(f64, @floatFromInt(i * n + j + 1));
            const diagonal: f64 = if (i == j and i < n_gauss) base else 0.0;
            mat.data[i * n + j] = diagonal + delta * linear;
        }
    }
    return mat;
}

fn vectorSeed(base: f64, delta: f64) Vec {
    var vec: Vec = undefined;
    inline for (0..n) |i| {
        vec.data[i] = base + delta * @as(f64, @floatFromInt(i));
    }
    return vec;
}

fn checksumMatrix() f64 {
    var sum: f64 = 0.0;
    inline for (0..n * n) |idx| {
        sum += matrix_out.data[idx] * @as(f64, @floatFromInt(idx + 1));
    }
    return sum;
}

fn checksumPair() f64 {
    return pair_out.col0 + 13.0 * pair_out.col1;
}
