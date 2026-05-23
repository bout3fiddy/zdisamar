# Capture Template

Use this template when adding another expression hook. The goal is to capture the
numerical relationship, not a timing point.

## Required Catalog Fields

Each expression needs a catalog row with:

- stable `expr_id`;
- `expr_name`;
- row table: scalar, decision, or reduction;
- subsystem;
- equation;
- result name and units;
- input names mapped to `input_*` and `param_*`;
- source file and function;
- capture reason tied to pruning, cheaper math, or scientific interpretation.

## Row Type Selection

Use `scalar_expression_rows` when the expression has one result:

```text
result = f(input_0, input_1, input_2, input_3, param_0, param_1)
```

Use `decision_rows` when the expression gates work:

```text
taken = lhs compare threshold
margin = lhs - threshold
```

Use `reduction_expression_rows` when the expression summarizes many terms:

```text
result = reduce(terms)
term_count, nonzero_count, zero_count, min_term, max_term, sum, mean
```

## Coordinates

Fill only coordinates that are meaningful:

- `wavelength_nm` for spectral rows;
- `layer_index` for atmospheric layer rows;
- `fourier_index` for Fourier expansion rows;
- `order_index` for multiple-scattering order rows;
- `state_index` for Jacobian state rows;
- `branch` for expression-local labels.

Absent coordinates stay null in Parquet.

## Product Boundary

New hooks must keep this shape:

```zig
if (Telemetry.enabled) {
    Telemetry.someExpression(...);
}
```

or:

```zig
pub inline fn someExpression(...) void {
    if (comptime !enabled) return;
    sink.someExpression(...);
}
```

The hook may pass values that were already computed by the model. Avoid
computing expensive extra terms for telemetry unless the computation is inside a
`Telemetry.enabled` guard.

The sink must remain outside `src/forward_model/`. File I/O, row buffering, and
run manifests belong to validation or research code.

## Analysis Questions

For every new expression, write down which question it supports:

- Can this branch be tightened, removed, or made data-dependent?
- Is the result often small enough to approximate or skip?
- Is the active term density low enough to warrant sparse or prepared storage?
- Are there coordinates where the expression is always irrelevant?
- Does a threshold have a wide safety margin or sit near a decision boundary?
