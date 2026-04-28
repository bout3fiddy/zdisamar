pub const Rule = struct {
    count: u32,
    nodes: [10]f64,
    weights: [10]f64,
};

pub fn fillNodesAndWeights(
    order: u32,
    nodes_out: []f64,
    weights_out: []f64,
) error{InvalidOrder}!void {
    if (order == 0 or nodes_out.len < order or weights_out.len < order) {
        return error.InvalidOrder;
    }

    const order_usize: usize = @intCast(order);
    const half_count = (order_usize + 1) / 2;
    const tolerance = 1.0e-14;

    for (0..half_count) |index| {
        var root = std.math.cos(std.math.pi * (@as(f64, @floatFromInt(index)) + 0.75) / (@as(f64, @floatFromInt(order)) + 0.5));
        while (true) {
            const polynomial = legendrePolynomial(order, root);
            const derivative = legendreDerivative(order, root, polynomial.value, polynomial.previous_value);
            const next_root = root - (polynomial.value / derivative);
            if (@abs(next_root - root) <= tolerance) {
                root = next_root;
                break;
            }
            root = next_root;
        }

        const polynomial = legendrePolynomial(order, root);
        const derivative = legendreDerivative(order, root, polynomial.value, polynomial.previous_value);
        const weight = 2.0 / ((1.0 - (root * root)) * derivative * derivative);

        nodes_out[index] = -root;
        weights_out[index] = weight;
        const mirrored_index = order_usize - 1 - index;
        nodes_out[mirrored_index] = root;
        weights_out[mirrored_index] = weight;
    }
}

const max_disamar_division_points: usize = 256;

pub fn fillDisamarDivPoints01(
    order: u32,
    nodes_out: []f64,
    weights_out: []f64,
) error{InvalidOrder}!void {
    if (order == 0 or
        nodes_out.len < order or
        weights_out.len < order or
        order > max_disamar_division_points)
    {
        return error.InvalidOrder;
    }

    const order_usize: usize = @intCast(order);
    var diagonal: [max_disamar_division_points]f64 = undefined;
    var off_diagonal: [max_disamar_division_points]f64 = undefined;
    var first_row: [max_disamar_division_points]f64 = undefined;

    if (order_usize > 1) {
        for (0..order_usize - 1) |index| {
            const abi: f64 = @floatFromInt(index + 1);
            diagonal[index] = 0.0;
            off_diagonal[index] = abi / @sqrt(4.0 * abi * abi - 1.0);
        }
    }
    diagonal[order_usize - 1] = 0.0;
    off_diagonal[order_usize - 1] = 0.0;
    first_row[0] = 1.0;
    if (order_usize > 1) @memset(first_row[1..order_usize], 0.0);

    try gausq2Disamar(
        diagonal[0..order_usize],
        off_diagonal[0..order_usize],
        first_row[0..order_usize],
    );

    for (0..order_usize) |index| {
        nodes_out[index] = (diagonal[index] + 1.0) * 0.5;
        weights_out[index] = first_row[index] * first_row[index];
    }
}

pub fn fillDisamarDivPointsInterval(
    order: u32,
    a0: f64,
    b0: f64,
    nodes_out: []f64,
    weights_out: []f64,
) error{InvalidOrder}!void {
    if (order == 0 or
        nodes_out.len < order or
        weights_out.len < order or
        order > max_disamar_division_points)
    {
        return error.InvalidOrder;
    }

    const order_usize: usize = @intCast(order);
    var diagonal: [max_disamar_division_points]f64 = undefined;
    var off_diagonal: [max_disamar_division_points]f64 = undefined;
    var first_row: [max_disamar_division_points]f64 = undefined;

    if (order_usize > 1) {
        for (0..order_usize - 1) |index| {
            const abi: f64 = @floatFromInt(index + 1);
            diagonal[index] = 0.0;
            off_diagonal[index] = abi / @sqrt(4.0 * abi * abi - 1.0);
        }
    }
    diagonal[order_usize - 1] = 0.0;
    off_diagonal[order_usize - 1] = 0.0;
    first_row[0] = 1.0;
    if (order_usize > 1) @memset(first_row[1..order_usize], 0.0);

    try gausq2Disamar(
        diagonal[0..order_usize],
        off_diagonal[0..order_usize],
        first_row[0..order_usize],
    );

    const span = b0 - a0;
    for (0..order_usize) |index| {
        weights_out[index] = first_row[index] * first_row[index] / 2.0 * span;
        nodes_out[index] = (diagonal[index] + 1.0) / 2.0 * span + a0;
    }
}

fn gausq2Disamar(
    diagonal: []f64,
    off_diagonal: []f64,
    first_row: []f64,
) error{InvalidOrder}!void {
    const n = diagonal.len;
    if (n == 0 or off_diagonal.len != n or first_row.len != n) return error.InvalidOrder;
    if (n == 1) return;

    const machep = 2.0e-16;
    off_diagonal[n - 1] = 0.0;

    var l: usize = 0;
    while (l < n) : (l += 1) {
        var iteration_count: usize = 0;
        while (true) {
            var m = l;
            while (m < n) : (m += 1) {
                if (m == n - 1) break;
                if (@abs(off_diagonal[m]) <= machep * (@abs(diagonal[m]) + @abs(diagonal[m + 1]))) break;
            }

            var p = diagonal[l];
            if (m == l) break;
            if (iteration_count == 30) return error.InvalidOrder;
            iteration_count += 1;

            var g = (diagonal[l + 1] - p) / (2.0 * off_diagonal[l]);
            var r = @sqrt(g * g + 1.0);
            g = diagonal[m] - p + off_diagonal[l] / (g + disamarSign(r, g));
            var s: f64 = 1.0;
            var c: f64 = 1.0;
            p = 0.0;

            var ii: usize = 1;
            while (ii <= m - l) : (ii += 1) {
                const i = m - ii;
                const f = s * off_diagonal[i];
                const b = c * off_diagonal[i];
                if (@abs(f) >= @abs(g)) {
                    c = g / f;
                    r = @sqrt(c * c + 1.0);
                    off_diagonal[i + 1] = f * r;
                    s = 1.0 / r;
                    c *= s;
                } else {
                    s = f / g;
                    r = @sqrt(s * s + 1.0);
                    off_diagonal[i + 1] = g * r;
                    c = 1.0 / r;
                    s *= c;
                }
                g = diagonal[i + 1] - p;
                r = (diagonal[i] - g) * s + 2.0 * c * b;
                p = s * r;
                diagonal[i + 1] = g + p;
                g = c * r - b;

                const f_component = first_row[i + 1];
                first_row[i + 1] = s * first_row[i] + c * f_component;
                first_row[i] = c * first_row[i] - s * f_component;
            }

            diagonal[l] -= p;
            off_diagonal[l] = g;
            off_diagonal[m] = 0.0;
        }
    }

    var sort_start: usize = 1;
    while (sort_start < n) : (sort_start += 1) {
        const i = sort_start - 1;
        var k = i;
        var p = diagonal[i];
        var j = sort_start;
        while (j < n) : (j += 1) {
            if (diagonal[j] >= p) continue;
            k = j;
            p = diagonal[j];
        }
        if (k == i) continue;
        diagonal[k] = diagonal[i];
        diagonal[i] = p;
        const first_row_i = first_row[i];
        first_row[i] = first_row[k];
        first_row[k] = first_row_i;
    }
}

fn disamarSign(magnitude: f64, sign_source: f64) f64 {
    return if (sign_source >= 0.0) @abs(magnitude) else -@abs(magnitude);
}

pub fn rule(order: u32) error{UnsupportedOrder}!Rule {
    return switch (order) {
        1 => .{
            .count = 1,
            .nodes = .{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        2 => .{
            .count = 2,
            .nodes = .{ -0.5773502691896257, 0.5773502691896257, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        3 => .{
            .count = 3,
            .nodes = .{ -0.7745966692414834, 0.0, 0.7745966692414834, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 0.5555555555555556, 0.8888888888888888, 0.5555555555555556, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        4 => .{
            .count = 4,
            .nodes = .{ -0.8611363115940526, -0.3399810435848563, 0.3399810435848563, 0.8611363115940526, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 0.3478548451374538, 0.6521451548625461, 0.6521451548625461, 0.3478548451374538, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        5 => .{
            .count = 5,
            .nodes = .{ -0.9061798459386640, -0.5384693101056831, 0.0, 0.5384693101056831, 0.9061798459386640, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        6 => .{
            .count = 6,
            .nodes = .{ -0.9324695142031521, -0.6612093864662645, -0.2386191860831969, 0.2386191860831969, 0.6612093864662645, 0.9324695142031521, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 0.1713244923791704, 0.3607615730481386, 0.4679139345726910, 0.4679139345726910, 0.3607615730481386, 0.1713244923791704, 0.0, 0.0, 0.0, 0.0 },
        },
        7 => .{
            .count = 7,
            .nodes = .{ -0.9491079123427585, -0.7415311855993945, -0.4058451513773972, 0.0, 0.4058451513773972, 0.7415311855993945, 0.9491079123427585, 0.0, 0.0, 0.0 },
            .weights = .{ 0.1294849661688697, 0.2797053914892766, 0.3818300505051189, 0.4179591836734694, 0.3818300505051189, 0.2797053914892766, 0.1294849661688697, 0.0, 0.0, 0.0 },
        },
        8 => .{
            .count = 8,
            .nodes = .{
                -0.9602898564975363,
                -0.7966664774136267,
                -0.5255324099163290,
                -0.1834346424956498,
                0.1834346424956498,
                0.5255324099163290,
                0.7966664774136267,
                0.9602898564975363,
                0.0,
                0.0,
            },
            .weights = .{
                0.1012285362903763,
                0.2223810344533745,
                0.3137066458778873,
                0.3626837833783620,
                0.3626837833783620,
                0.3137066458778873,
                0.2223810344533745,
                0.1012285362903763,
                0.0,
                0.0,
            },
        },
        9 => .{
            .count = 9,
            .nodes = .{
                -0.9681602395076261,
                -0.8360311073266358,
                -0.6133714327005904,
                -0.3242534234038089,
                0.0,
                0.3242534234038089,
                0.6133714327005904,
                0.8360311073266358,
                0.9681602395076261,
                0.0,
            },
            .weights = .{
                0.0812743883615744,
                0.1806481606948574,
                0.2606106964029354,
                0.3123470770400029,
                0.3302393550012598,
                0.3123470770400029,
                0.2606106964029354,
                0.1806481606948574,
                0.0812743883615744,
                0.0,
            },
        },
        10 => .{
            .count = 10,
            .nodes = .{
                -0.9739065285171717,
                -0.8650633666889845,
                -0.6794095682990244,
                -0.4333953941292472,
                -0.1488743389816312,
                0.1488743389816312,
                0.4333953941292472,
                0.6794095682990244,
                0.8650633666889845,
                0.9739065285171717,
            },
            .weights = .{
                0.0666713443086881,
                0.1494513491505806,
                0.2190863625159820,
                0.2692667193099964,
                0.2955242247147529,
                0.2955242247147529,
                0.2692667193099964,
                0.2190863625159820,
                0.1494513491505806,
                0.0666713443086881,
            },
        },
        else => error.UnsupportedOrder,
    };
}

const PolynomialState = struct {
    value: f64,
    previous_value: f64,
};

fn legendrePolynomial(order: u32, x: f64) PolynomialState {
    if (order == 0) {
        return .{ .value = 1.0, .previous_value = 0.0 };
    }

    var previous_previous: f64 = 1.0;
    var previous: f64 = x;
    if (order == 1) {
        return .{ .value = previous, .previous_value = previous_previous };
    }

    var current: f64 = previous;
    var n: u32 = 2;
    while (n <= order) : (n += 1) {
        current =
            (((2.0 * @as(f64, @floatFromInt(n))) - 1.0) * x * previous -
                (@as(f64, @floatFromInt(n)) - 1.0) * previous_previous) /
            @as(f64, @floatFromInt(n));
        previous_previous = previous;
        previous = current;
    }

    return .{
        .value = current,
        .previous_value = previous_previous,
    };
}

fn legendreDerivative(order: u32, x: f64, value: f64, previous_value: f64) f64 {
    return (@as(f64, @floatFromInt(order)) * (x * value - previous_value)) / ((x * x) - 1.0);
}

const std = @import("std");
