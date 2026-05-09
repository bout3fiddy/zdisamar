# Rejected Ideas

Rejected ideas are kept because they prevent repeat work. The rule is simple:
latency wins are not retained if they move checked residuals or tangents beyond
the retained validation guardrails.

## Always-Square Attenuation

Squaring attenuation at every doubling step was slightly faster, but it changed
residuals. The forward-reflectance max residual moved to about `1.36e-13`, and
the surface-albedo Jacobian max residual moved to `7.898e-13`, beyond the
retained `1e-13` guardrail. The parity-safe recompute-then-square path stays.

## No-Pivot Q-Series

Dropping pivoting improved isolated q-series timings in probes, but the tracked
full trace did not clearly improve elapsed time or aggregate LABOS CPU. It also
weakens the numerical safety margin for future scenes. The pivoted fixed helper
stays.

## FMA and Vector Dot-Pair Probes

FMA and vectorized `dotGaussPair` variants improved isolated mock-data harnesses
but worsened the real scattering-orders trace. The current scalar dot-pair shape
stays.

## Larger Fused Post-D Updates

Fusing `R*D`, `T*U`, or `T*D` into larger helpers either failed a fast tangent
gate or worsened the full trace. The materialized product plus focused update
shape remains better for the real kernel.

## Symmetric Phase Fill

`Zplus` is symmetric, so filling half the matrix looked plausible. The full trace
worsened because the triangular code shape was less friendly to the compiler and
memory access pattern. The rectangular fixed-12 phase fill stays.

## Selective Orders Initialization

Reducing zero initialization in orders looked plausible, but repeat traces were
mixed or worse. The broader local initialization remains because it is simpler
and robust.
