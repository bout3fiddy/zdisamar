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
- `order_index` for multiple-scattering order rows, doubling steps, or other
  expression-local order coordinates;
- `state_index` for Jacobian state rows, phase-count coordinates, or other
  expression-local state coordinates;
- `branch` for expression-local labels.

Absent coordinates are written as numeric sentinels (`-1` for integer
coordinates and `NaN` for floating coordinates). Convert them to nulls in
analysis when the distinction matters.

Document every expression-specific coordinate overload in `schema.md`. For
example, the q-series downstream product gates use `branch = qseries_is_zero`,
`order_index = doubling_step_index`, and `state_index = phase_max_index`, while
the layer-doubling trigger uses `branch = phase_max_index`.

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

If a hook captures several related threshold decisions, prefer one facade call
that passes the already-available operands once and lets the sink write multiple
decision rows. This keeps the product path compact while still giving the
analysis enough data to distinguish a base skip decision from its downstream
work gates.

The sink must remain outside product `src/` modules. File I/O, row buffering, and
run manifests belong to validation or research code.

## Writer Boundary

The retained writer is `scaffolding/instrumentation/telemetry/zig/parquet_lite.zig`. Keep it
minimal:

- flat fixed schemas only;
- PLAIN encoding only;
- row-group compression and footer work outside the row hook path;
- no reader, nested schema support, dictionary encoding, or product API.

If a new capture shape needs another column, add it deliberately to the fixed
schema and document the meaning here and in `schema.md`.

## Analysis Questions

For every new expression, write down which question it supports:

- Can this branch be tightened, removed, or made data-dependent?
- Is the result often small enough to approximate or skip?
- Is the active term density low enough to warrant sparse or prepared storage?
- Are there coordinates where the expression is always irrelevant?
- Does a threshold have a wide safety margin or sit near a decision boundary?
