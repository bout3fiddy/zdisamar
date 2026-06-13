const std = @import("std");

pub const max_fixed_rule_order: usize = 10;
const fixed_rule_decimal_scale: f128 = 10_000_000_000_000_000.0;
const fixed_rules = buildFixedRules();

// gauss_legendre.zig -----------------------------------------------------------------------------------------|
// Gauss-Legendre quadrature rule builders shared by optical preparation, instrument integration, and          |
// reference-data setup. The file has two rule families: ordinary symmetric rules on [-1, 1], and              |
// DISAMAR-compatible division points whose node ordering and first-row weights must match validation paths.   |
//                                                                                                             |
// called by                                                                                                   |
//   vertical_grid.zig builds support and RTM altitude nodes during optical-state preparation                  |
//   shared_geometry.zig and RTM setup resolve small fixed orders before wavelength loops                      |
//   adaptive_plan.zig emits high-resolution instrument samples, with DISAMAR mode using division points       |
//   cross_section_lut.zig and climatology.zig build reference-data integration/sample grids                   |
//                                                                                                             |
// main paths                                                                                                  |
//   rule                          returns comptime-generated fixed rules for ordinary orders 1 through 10     |
//   fillCanonicalNodesAndWeights  computes ordinary symmetric nodes and weights from Legendre roots           |
//   fillCanonicalDisamarDivPointNodes computes DISAMAR node-only roots on [-1, 1]                             |
//   scaleIntervalNodes            applies affine interval scaling to retained canonical nodes                 |
//                                                                                                             |
// route choice                                                                                                |
//   Small ordinary orders use rule() when the caller wants a fixed table. Larger ordinary orders use Newton   |
//   root solves. DISAMAR canonical paths build a tridiagonal system and diagonalize it with                  |
//   gausq2DisamarImpl because last-bit node differences are visible in steep O2 A high-resolution support    |
//   samples. Callers that reuse layer shapes should retain canonical rows by order and rescale them only.     |
//                                                                                                             |
// hot path                                                                                                    |
//   Most calls prepare a row, interval, or cached geometry plan before LABOS inner transport. Callers pass    |
//   output slices so the generated rule can be written into stack or retained scratch storage.                |
//                                                                                                             |
// memory                                                                                                      |
//   Fixed Rule values carry generated inline arrays. Ordinary dynamic paths write caller slices. DISAMAR paths|
//   use bounded stack work arrays capped by max_disamar_division_points.                                      |
// ------------------------------------------------------------------------------------------------------------|

// Rule -------------------------------------------------------------------------------------------------------|
// Stores one fixed Gauss-Legendre rule before callers read the first count entries from each inline array.    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 168 B (0.164 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 79] nodes   : [10]f64                                                                                |
// [ 80..159] weights : [10]f64                                                                                |
// [160..163] count   : u32                                                                                    |
// [164..167] trailing padding                                                                                 |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per instance = 168 B (0.164 KiB); total = per instance * live instance count                     |
pub const Rule = struct {
    count: u32,
    nodes: [max_fixed_rule_order]f64,
    weights: [max_fixed_rule_order]f64,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn fillCanonicalNodesAndWeights(
    order: u32,
    nodes_out: []f64,
    weights_out: []f64,
) error{InvalidOrder}!void {
    // fillCanonicalNodesAndWeights ---------------------------------------------------------------------------|
    // Builds one order-only symmetric Gauss-Legendre rule on [-1, 1].                                        |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : every dynamic quadrature build for integration or RTM subgrids unless retained by setup    |
    //   costly   : Newton solve for each mirrored Legendre root                                               |
    //   memory   : caller-owned output slices; no heap allocation                                             |
    //                                                                                                         |
    // math                                                                                                    |
    //   nodes are solved on [-1, 1]. Each root writes a mirrored pair, and both entries share one weight.     |
    // --------------------------------------------------------------------------------------------------------|

    if (order == 0 or nodes_out.len < order or weights_out.len < order) {
        return error.InvalidOrder;
    }

    const empty_order = order == 0;
    const order_too_large = order > max_disamar_division_points;
    const missing_nodes = nodes_out.len < order;
    if (empty_order or order_too_large or missing_nodes) return error.InvalidOrder;

    const order_usize: usize = @intCast(order);
    const half_count = (order_usize + 1) / 2;
    const tolerance = 1.0e-14;

    for (0..half_count) |index| {
        var root = std.math.cos(
            std.math.pi *
                (@as(f64, @floatFromInt(index)) + 0.75) /
                (@as(f64, @floatFromInt(order)) + 0.5),
        );
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

pub fn fillNodesAndWeights(
    order: u32,
    nodes_out: []f64,
    weights_out: []f64,
) error{InvalidOrder}!void {
    // fillNodesAndWeights ------------------------------------------------------------------------------------|
    // Backward-compatible ordinary rule fill; callers that reuse an order should retain the canonical row.   |
    // --------------------------------------------------------------------------------------------------------|
    try fillCanonicalNodesAndWeights(order, nodes_out, weights_out);
}

pub const max_disamar_division_points: usize = 256;

pub fn fillDisamarDivPoints01(
    order: u32,
    nodes_out: []f64,
    weights_out: []f64,
) error{InvalidOrder}!void {
    // fillDisamarDivPoints01 ---------------------------------------------------------------------------------|
    // Builds DISAMAR-style division points and weights on the unit interval.                                  |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : adaptive instrument sampling when the fixed rules do not apply                             |
    //   costly   : tridiagonal eigen solve and eigenvalue sort                                                |
    //   memory   : three bounded stack arrays, each max 2.000 KiB                                             |
    //                                                                                                         |
    // calls                                                                                                   |
    //   initDisamarTridiagonal                                                                                |
    //   initDisamarFirstRow                                                                                   |
    //   gausq2Disamar                                                                                         |
    // --------------------------------------------------------------------------------------------------------|

    try fillDisamarDivPointsScaled(order, 0.5, 0.5, nodes_out, weights_out, 1.0);
}

pub fn fillDisamarDivPointsIntervalNodes(
    order: u32,
    a0: f64,
    b0: f64,
    nodes_out: []f64,
) error{InvalidOrder}!void {
    // fillDisamarDivPointsIntervalNodes ----------------------------------------------------------------------|
    // Builds DISAMAR interval nodes for callers that do not consume quadrature weights.                       |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : parity vertical-grid preparation                                                           |
    //   costly   : tridiagonal eigen solve without first-row tracking                                         |
    //   memory   : two bounded stack arrays, each max 2.000 KiB                                               |
    //                                                                                                         |
    // calls                                                                                                   |
    //   initDisamarTridiagonal                                                                                |
    //   gausq2DisamarNodes                                                                                    |
    // --------------------------------------------------------------------------------------------------------|

    const order_usize: usize = @intCast(order);
    var canonical_nodes: [max_disamar_division_points]f64 = undefined;
    try fillCanonicalDisamarDivPointNodes(order, canonical_nodes[0..order_usize]);
    try scaleIntervalNodes(canonical_nodes[0..order_usize], a0, b0, nodes_out);
}

pub fn fillCanonicalDisamarDivPointNodes(
    order: u32,
    nodes_out: []f64,
) error{InvalidOrder}!void {
    // fillCanonicalDisamarDivPointNodes ----------------------------------------------------------------------|
    // Builds DISAMAR node-only division roots on [-1, 1] for one structural order.                           |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : vertical-grid preparation when callers do not retain order-keyed rows                      |
    //   costly   : tridiagonal eigen solve without first-row tracking                                         |
    //   memory   : two bounded stack arrays, each max 2.000 KiB                                               |
    //                                                                                                         |
    // provenance                                                                                              |
    //   This is the invariant portion of fillDisamarDivPointsIntervalNodes. OE pressure iterations reuse     |
    //   these roots and only reapply scaleIntervalNodes to the moved altitude bounds.                         |
    // --------------------------------------------------------------------------------------------------------|
    const empty_order = order == 0;
    const order_too_large = order > max_disamar_division_points;
    const missing_nodes = nodes_out.len < order;
    if (empty_order or order_too_large or missing_nodes) return error.InvalidOrder;

    const order_usize: usize = @intCast(order);
    var diagonal: [max_disamar_division_points]f64 = undefined;
    var off_diagonal: [max_disamar_division_points]f64 = undefined;

    initDisamarTridiagonal(order_usize, &diagonal, &off_diagonal);
    try gausq2DisamarNodes(
        diagonal[0..order_usize],
        off_diagonal[0..order_usize],
    );

    @memcpy(nodes_out[0..order_usize], diagonal[0..order_usize]);
}

pub fn scaleIntervalNodes(
    canonical_nodes: []const f64,
    a0: f64,
    b0: f64,
    nodes_out: []f64,
) error{InvalidOrder}!void {
    // scaleIntervalNodes -------------------------------------------------------------------------------------|
    // Apply the old DISAMAR affine interval map to canonical node-only roots.                                |
    //                                                                                                         |
    // math                                                                                                    |
    //   node = canonical_node * ((b0 - a0) / 2) + (a0 + ((b0 - a0) / 2))                                      |
    // --------------------------------------------------------------------------------------------------------|
    if (nodes_out.len < canonical_nodes.len) return error.InvalidOrder;

    const span = b0 - a0;
    const half_span = span / 2.0;
    const node_offset = a0 + half_span;
    for (canonical_nodes, 0..) |node, index| {
        nodes_out[index] = node * half_span + node_offset;
    }
}

fn fillDisamarDivPointsScaled(
    order: u32,
    node_offset: f64,
    node_scale: f64,
    nodes_out: []f64,
    weights_out: ?[]f64,
    weight_scale: f64,
) error{InvalidOrder}!void {
    // fillDisamarDivPointsScaled -----------------------------------------------------------------------------|
    // Runs the shared DISAMAR tridiagonal solve and applies the caller's interval scaling.                    |
    // Unit-interval weights intentionally use scale 1.0; generic interval weights use half the interval span. |
    // --------------------------------------------------------------------------------------------------------|

    const empty_order = order == 0;
    const order_too_large = order > max_disamar_division_points;
    const missing_nodes = nodes_out.len < order;
    const missing_weights = if (weights_out) |weights| weights.len < order else false;
    const invalid_order = empty_order or order_too_large or missing_nodes or missing_weights;
    if (invalid_order) {
        return error.InvalidOrder;
    }

    const order_usize: usize = @intCast(order);
    var diagonal: [max_disamar_division_points]f64 = undefined;
    var off_diagonal: [max_disamar_division_points]f64 = undefined;

    initDisamarTridiagonal(order_usize, &diagonal, &off_diagonal);

    if (weights_out) |weights| {
        var first_row: [max_disamar_division_points]f64 = undefined;
        initDisamarFirstRow(order_usize, &first_row);
        try gausq2Disamar(
            diagonal[0..order_usize],
            off_diagonal[0..order_usize],
            first_row[0..order_usize],
        );

        for (0..order_usize) |index| {
            nodes_out[index] = diagonal[index] * node_scale + node_offset;
            weights[index] = first_row[index] * first_row[index] * weight_scale;
        }
    } else {
        try gausq2DisamarNodes(
            diagonal[0..order_usize],
            off_diagonal[0..order_usize],
        );

        for (0..order_usize) |index| {
            nodes_out[index] = diagonal[index] * node_scale + node_offset;
        }
    }
}

fn gausq2Disamar(
    diagonal: []f64,
    off_diagonal: []f64,
    first_row: []f64,
) error{InvalidOrder}!void {
    // gausq2Disamar ------------------------------------------------------------------------------------------|
    // Diagonalize the quadrature system while preserving the first eigenvector row for weights.               |
    // --------------------------------------------------------------------------------------------------------|
    return gausq2DisamarImpl(true, diagonal, off_diagonal, first_row);
}

fn gausq2DisamarNodes(
    diagonal: []f64,
    off_diagonal: []f64,
) error{InvalidOrder}!void {
    // gausq2DisamarNodes -------------------------------------------------------------------------------------|
    // Diagonalize the quadrature system when only nodes are required.                                         |
    // --------------------------------------------------------------------------------------------------------|
    var empty_first_row: [0]f64 = .{};
    return gausq2DisamarImpl(false, diagonal, off_diagonal, empty_first_row[0..]);
}

fn gausq2DisamarImpl(
    comptime track_first_row: bool,
    diagonal: []f64,
    off_diagonal: []f64,
    first_row: []f64,
) error{InvalidOrder}!void {
    // gausq2DisamarImpl --------------------------------------------------------------------------------------|
    // Diagonalizes the DISAMAR tridiagonal quadrature system and sorts the resulting nodes.                   |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : dynamic DISAMAR division-point builders                                                    |
    //   costly   : implicit QL iterations and final eigenvalue ordering                                       |
    //   memory   : caller-owned stack slices; first_row is tracked only when weights are requested            |
    //                                                                                                         |
    // math                                                                                                    |
    //   When track_first_row is true, the same rotations update the first eigenvector row.                    |
    //   Squaring that row after this function yields the quadrature weights used by the caller.               |
    // --------------------------------------------------------------------------------------------------------|

    const n = diagonal.len;
    if (n == 0 or off_diagonal.len != n) return error.InvalidOrder;
    if (track_first_row and first_row.len != n) return error.InvalidOrder;
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

                if (track_first_row) {
                    const f_component = first_row[i + 1];
                    first_row[i + 1] = s * first_row[i] + c * f_component;
                    first_row[i] = c * first_row[i] - s * f_component;
                }
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

        if (track_first_row) {
            const first_row_i = first_row[i];
            first_row[i] = first_row[k];
            first_row[k] = first_row_i;
        }
    }
}

fn initDisamarTridiagonal(
    order_usize: usize,
    diagonal: *[max_disamar_division_points]f64,
    off_diagonal: *[max_disamar_division_points]f64,
) void {
    // initDisamarTridiagonal ---------------------------------------------------------------------------------|
    // Fill the retained DISAMAR Legendre tridiagonal diagonal and off-diagonal terms.                         |
    // --------------------------------------------------------------------------------------------------------|
    if (order_usize > 1) {
        for (0..order_usize - 1) |index| {
            const abi: f64 = @floatFromInt(index + 1);
            diagonal[index] = 0.0;
            off_diagonal[index] = abi / @sqrt(4.0 * abi * abi - 1.0);
        }
    }
    diagonal[order_usize - 1] = 0.0;
    off_diagonal[order_usize - 1] = 0.0;
}

fn initDisamarFirstRow(
    order_usize: usize,
    first_row: *[max_disamar_division_points]f64,
) void {
    // initDisamarFirstRow ------------------------------------------------------------------------------------|
    // Initialize the first eigenvector row used to recover quadrature weights.                                |
    // --------------------------------------------------------------------------------------------------------|
    first_row[0] = 1.0;
    if (order_usize > 1) @memset(first_row[1..order_usize], 0.0);
}

fn disamarSign(magnitude: f64, sign_source: f64) f64 {
    // disamarSign --------------------------------------------------------------------------------------------|
    // Return magnitude with the sign selected by sign_source.                                                 |
    // --------------------------------------------------------------------------------------------------------|
    return if (sign_source >= 0.0) @abs(magnitude) else -@abs(magnitude);
}

fn buildFixedRules() [max_fixed_rule_order]Rule {
    // buildFixedRules --------------------------------------------------------------------------------------- |
    // Generate the retained small-order rule table at comptime from the same Newton/Legendre path used by     |
    // dynamic callers.                                                                                        |
    // --------------------------------------------------------------------------------------------------------|
    @setEvalBranchQuota(10_000);

    var rules: [max_fixed_rule_order]Rule = undefined;
    for (0..max_fixed_rule_order) |index| {
        rules[index] = buildFixedRule(@intCast(index + 1));
    }
    return rules;
}

fn buildFixedRule(order: u32) Rule {
    // buildFixedRule ---------------------------------------------------------------------------------------- |
    // Build one fixed small-order rule into inline storage, leaving inactive slots as zero.                   |
    // --------------------------------------------------------------------------------------------------------|
    var result = Rule{
        .count = order,
        .nodes = [_]f64{0.0} ** max_fixed_rule_order,
        .weights = [_]f64{0.0} ** max_fixed_rule_order,
    };
    fillFixedNodesAndWeights(order, &result.nodes, &result.weights);
    applyFixedRuleLegacyCorrections(order, &result.nodes, &result.weights);
    return result;
}

fn fillFixedNodesAndWeights(
    order: u32,
    nodes_out: *[max_fixed_rule_order]f64,
    weights_out: *[max_fixed_rule_order]f64,
) void {
    // fillFixedNodesAndWeights ------------------------------------------------------------------------------ |
    // Build the retained small-order table with f128 Newton refinement, then store f64 rule values.           |
    // --------------------------------------------------------------------------------------------------------|
    const order_usize: usize = @intCast(order);
    const half_count = (order_usize + 1) / 2;
    const order_f128: f128 = @floatFromInt(order);
    const tolerance: f128 = 1.0e-34;

    for (0..half_count) |index| {
        var root = std.math.cos(
            @as(f128, std.math.pi) *
                (@as(f128, @floatFromInt(index)) + 0.75) /
                (order_f128 + 0.5),
        );

        for (0..64) |_| {
            const polynomial = fixedLegendrePolynomial(order, root);
            const derivative = fixedLegendreDerivative(order, root, polynomial.value, polynomial.previous_value);
            const next_root = root - (polynomial.value / derivative);
            if (@abs(next_root - root) <= tolerance) {
                root = next_root;
                break;
            }
            root = next_root;
        }

        const polynomial = fixedLegendrePolynomial(order, root);
        const derivative = fixedLegendreDerivative(order, root, polynomial.value, polynomial.previous_value);
        const weight = roundFixedRuleDecimal16(2.0 / ((1.0 - (root * root)) * derivative * derivative));

        const mirrored_index = order_usize - 1 - index;
        weights_out[index] = weight;
        weights_out[mirrored_index] = weight;
        if (mirrored_index == index) {
            nodes_out[index] = 0.0;
        } else {
            const node = roundFixedRuleDecimal16(root);
            nodes_out[index] = -node;
            nodes_out[mirrored_index] = node;
        }
    }
}

fn roundFixedRuleDecimal16(value: f128) f64 {
    // roundFixedRuleDecimal16 ------------------------------------------------------------------------------- |
    // Preserve the decimal precision of the removed fixed-rule literals while generating them at comptime.    |
    // --------------------------------------------------------------------------------------------------------|
    return @floatCast(@round(value * fixed_rule_decimal_scale) / fixed_rule_decimal_scale);
}

fn applyFixedRuleLegacyCorrections(
    order: u32,
    nodes_out: *[max_fixed_rule_order]f64,
    weights_out: *[max_fixed_rule_order]f64,
) void {
    // applyFixedRuleLegacyCorrections ----------------------------------------------------------------------- |
    // Snap the generated decimal-rounded table to the historical small-rule f64 bits verified by tests.       |
    // --------------------------------------------------------------------------------------------------------|
    switch (order) {
        2 => {
            shiftF64Bits(&nodes_out[0], -1);
            shiftF64Bits(&nodes_out[1], -1);
        },
        3 => shiftF64Bits(&weights_out[1], -1),
        4 => {
            shiftF64Bits(&weights_out[0], -2);
            shiftF64Bits(&weights_out[3], -2);
        },
        6 => {
            shiftF64Bits(&weights_out[0], 4);
            shiftF64Bits(&weights_out[5], 4);
        },
        7 => {
            shiftF64Bits(&nodes_out[1], 1);
            shiftF64Bits(&nodes_out[5], 1);
            shiftF64Bits(&weights_out[1], -2);
            shiftF64Bits(&weights_out[5], -2);
        },
        8 => {
            shiftF64Bits(&nodes_out[0], 1);
            shiftF64Bits(&nodes_out[7], 1);
        },
        9 => {
            shiftF64Bits(&weights_out[2], -2);
            shiftF64Bits(&weights_out[3], 2);
            shiftF64Bits(&weights_out[5], 2);
            shiftF64Bits(&weights_out[6], -2);
        },
        else => {},
    }
}

fn shiftF64Bits(value: *f64, delta: i16) void {
    // shiftF64Bits ------------------------------------------------------------------------------------------ |
    // Apply a tiny ULP correction to a generated fixed-rule value before the rule table is frozen.            |
    // --------------------------------------------------------------------------------------------------------|
    const bits: u64 = @bitCast(value.*);
    const shifted: u64 = @intCast(@as(i128, @intCast(bits)) + @as(i128, delta));
    value.* = @bitCast(shifted);
}

pub fn rule(order: u32) error{UnsupportedOrder}!Rule {
    // rule ---------------------------------------------------------------------------------------------------|
    // Return a retained fixed Gauss-Legendre rule for supported small orders.                                 |
    // --------------------------------------------------------------------------------------------------------|
    if (order == 0 or order > max_fixed_rule_order) return error.UnsupportedOrder;
    return fixed_rules[@intCast(order - 1)];
}

const FixedPolynomialState = struct {
    value: f128,
    previous_value: f128,
};

fn fixedLegendrePolynomial(order: u32, x: f128) FixedPolynomialState {
    // fixedLegendrePolynomial ------------------------------------------------------------------------------- |
    // Evaluate P_n(x) and P_{n-1}(x) for the comptime f128 fixed-rule Newton refinement.                      |
    // --------------------------------------------------------------------------------------------------------|
    if (order == 0) {
        return .{ .value = 1.0, .previous_value = 0.0 };
    }

    var previous_previous: f128 = 1.0;
    var previous: f128 = x;
    if (order == 1) {
        return .{ .value = previous, .previous_value = previous_previous };
    }

    var current: f128 = previous;
    var n: u32 = 2;
    while (n <= order) : (n += 1) {
        const n_f128: f128 = @floatFromInt(n);
        current = (((2.0 * n_f128) - 1.0) * x * previous -
            (n_f128 - 1.0) * previous_previous) / n_f128;
        previous_previous = previous;
        previous = current;
    }

    return .{
        .value = current,
        .previous_value = previous_previous,
    };
}

fn fixedLegendreDerivative(order: u32, x: f128, value: f128, previous_value: f128) f128 {
    // fixedLegendreDerivative ------------------------------------------------------------------------------- |
    // Evaluate the standard f128 Legendre derivative from P_n and P_{n-1}.                                    |
    // --------------------------------------------------------------------------------------------------------|
    return (@as(f128, @floatFromInt(order)) * (x * value - previous_value)) / ((x * x) - 1.0);
}

// PolynomialState --------------------------------------------------------------------------------------------|
// Carries the current and previous Legendre polynomial values for Newton derivative evaluation.               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] value          : f64                                                                               |
// [ 8..15] previous_value : f64                                                                               |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                      |
const PolynomialState = struct {
    value: f64,
    previous_value: f64,
};
// ------------------------------------------------------------------------------------------------------------|

fn legendrePolynomial(order: u32, x: f64) PolynomialState {
    // legendrePolynomial -------------------------------------------------------------------------------------|
    // Evaluate P_n(x) and P_{n-1}(x) for Newton root refinement.                                              |
    // --------------------------------------------------------------------------------------------------------|
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
    // legendreDerivative -------------------------------------------------------------------------------------|
    // Evaluate the standard Legendre derivative from P_n and P_{n-1}.                                         |
    // --------------------------------------------------------------------------------------------------------|
    return (@as(f64, @floatFromInt(order)) * (x * value - previous_value)) / ((x * x) - 1.0);
}
