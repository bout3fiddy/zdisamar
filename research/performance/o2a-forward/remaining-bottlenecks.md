# Remaining Bottlenecks

Current retained trace source:

```text
research/performance/tracing/output/labos-bottleneck/
```

The current ztracy JSON summary is intentionally coarse. It records the
instrumented forward wall time, while the detailed child-zone costs live in the
`.tracy` capture opened in Tracy profiler. The detailed operation counts below
come from the last pre-ztracy retained trace and are still the useful shape of
the remaining work.

## LABOS Fourier Transport

The forward route still expands one spectrum into `120,390` LABOS Fourier terms.
This is expected: O2 A reflectance is azimuth dependent, so the model evaluates
many Fourier terms before the tail is small enough.

## RT-Layer Construction

RT-layer construction visits `5,417,550` layer/Fourier combinations. Most visits
are cheap skips, but the active subset still builds phase matrices and runs
`8,389,666` doubling steps.

## Layer Doubling

Layer doubling costs `4.777200 s`. The recurrence updates layer reflection,
transmission, and attenuation until the split layer represents the original
optical thickness.

The repeated primitive counts are the reason this remains expensive:

```text
q-series calls             3,408,299
nonzero R*D/T*U/T*D       10,931,496
attempted product slots   25,168,998
```

Current primitive estimates:

```text
qseries_nonzero_12x10       482.858 ns/call  1.645724 s CPU
smul_12x10                  166.327 ns/call  1.818203 s CPU
known-trace D update        170.862 ns/call  0.582349 s CPU
```

## Scattering Orders

The scattering-order loop performs `295,581,240` `dotGaussPair` calls,
representing `2,955,812,400` multiply-add terms. The primitive is small; the
count is large.

## Phase Matrices

Phase matrix construction costs `1.040362 s`. The PLM basis cost is only
`0.008432 s`; the remaining cost is the repeated layer-specific fill of `Zplus`
and `Zmin`.

The next large gain probably needs to reduce one of these counts, or introduce a
new reuse boundary that preserves the same O2 A result.
