# 07. Stop Tiny Fourier Tails

Historical checkpoint: `f42445d -> c423f4a`, where forward elapsed time moved
from `2.266849 s` to `2.025331 s`.

In short: reuse Fourier basis values and stop once the retained tail is
negligible.

Source links:

- DISAMAR
  - [Fourier storage shape](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L268-L304): supports general Fourier storage, but the narrow path can reuse basis work more directly.
- zdisamar
  - [Fourier basis workspace](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/workspace.zig#L155-L180): caches basis values across repeated terms.
  - [Fourier tail stop](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/execute.zig#L406-L414): exits once later Fourier terms are below the retained convergence scale.

The Fourier basis depends on geometry and Fourier order. It can be reused. The
series also has a numerical tail: once later terms are below the configured
scale, continuing the sum does not change the retained result.

```python
# Broad route: rebuild basis and sum every configured term.
for m in range(max_fourier + 1):
    basis = build_plm_basis(geometry, m)
    reflectance += fourier_term(m, basis)

# Narrow route: cache basis and stop the tiny tail.
basis_cache = {}
for m in range(max_fourier + 1):
    basis = basis_cache.setdefault(m, build_plm_basis(geometry, m))
    term = fourier_term(m, basis)
    reflectance += term
    if abs(term) < fourier_tail_threshold:
        break
```

This is not an approximation beyond the configured convergence rule. It stops
work after the retained threshold says the remaining tail is negligible.
