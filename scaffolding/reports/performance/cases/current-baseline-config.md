# Current Baseline Config

The validation baseline is the DISAMAR-style aerosol scene used by the
current scripts and tracked outputs.

Rules:

- `aerosolLayerHeight` must stay `0`. We are not trying to compare against the
  older DISAMAR shortcut path.
- Validation thresholds are guardrails. Do not change residual or tangent
  thresholds without explicit approval.
- Surface albedo is varied across scenes but fixed inside the current
  aerosol-only retrieval.
- The current retrieval state vector is aerosol optical depth plus aerosol layer
  mid pressure.
- Python validation helpers should use `uv run ...`.

The baseline config itself is retained under validation so scripts can point to
a stable DISAMAR-style configuration rather than an ad hoc local file.
