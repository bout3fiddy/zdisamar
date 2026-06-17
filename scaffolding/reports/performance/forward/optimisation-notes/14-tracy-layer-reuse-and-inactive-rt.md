# 14. Reuse Layer Scattering Decisions

Checkpoint: worktree `codex/tracy-forward-model-investigation` after
`beb0aa1`, where the LABOS bottleneck trace moved from roughly `1.33-1.39 s`
to `1.31 s`.

In short: carry layer-level decisions across Fourier work and avoid writing
inactive RT matrices that the orders path will not read.

Source links:

- DISAMAR
  - No direct Fortran shortcut is used here. This is a zdisamar workspace reuse
    optimization around the existing LABOS equations.
- zdisamar
  - `src/forward_model/radiative_transfer/labos/layers.zig`: computes
    per-layer effective-scattering suffixes and uses the active-layer mask to
    skip inactive `LayerRT` writes.
  - `src/forward_model/radiative_transfer/labos/execute.zig`: prepares the
    suffix table once per forward sample.
  - `src/forward_model/radiative_transfer/labos/workspace.zig`: owns the
    reusable suffix storage.

Tracy showed repeated `labos.rt_layer.effective_scattering` scans and many
inactive layer/Fourier visits. The effective-scattering scan only depends on the
layer phase coefficients and the current Fourier index, so each layer can build
a reverse suffix table once and look up the maximum for each Fourier term.

```python
# Broad route: each Fourier order rescans the layer tail.
for fourier in fourier_orders:
    for layer in layers:
        max_beta_eff = max(beta_eff(layer, i) for i in range(fourier, max_i + 1))
        build_rt_layer(max_beta_eff)

# Narrow route: scan each layer once, then index the suffix.
for layer in layers:
    suffix_max[layer] = reverse_suffix_max(beta_eff(layer, i))

for fourier in fourier_orders:
    for layer in layers:
        build_rt_layer(suffix_max[layer][fourier])
```

The active-layer mask was already the contract used by scattering orders. When
that mask is available, an inactive RT layer does not need a freshly zeroed
matrix pair; it only needs `active[layer] = false`.

```python
# Broad route: skipped layers still rewrite matrix storage.
if layer_cannot_contribute:
    rt[layer] = zero_layer_rt()
    active[layer] = False

# Narrow route: the following orders pass consults active before reading rt.
if layer_cannot_contribute:
    active[layer] = False
```

The generic helper path still writes zero matrices when no active mask is
provided. The retained workspace route is residual-clean: the validation
lanes passed, and the vendor-shaped residual stayed at numerical zero.
