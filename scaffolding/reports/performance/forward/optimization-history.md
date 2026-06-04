# Optimization History

This is historical evidence. It explains the speedup path across commits and
older cases; it is not the current forward elapsed time.

Retained checkpoint source:

```text
scaffolding/reports/performance/forward/checkpoint-timings.md
```

The main historical moves were:

| Area | What changed | Historical evidence |
| --- | --- | ---: |
| Wavelength work and layer geometry | Calculate each exact high-resolution radiance sample once and build stable vertical geometry once. | `79.767901 s -> 11.890893 s` |
| Spectroscopy preparation | Move pressure/temperature line state work into preparation. | `35.364130 s -> 8.432518 s` forward elapsed time in the checkpoint table |
| LABOS storage | Reuse LABOS arrays across repeated Fourier and wavelength work. | `8.432518 s -> 7.020602 s` |
| Fused doubling math | Reduce repeated matrix traffic inside layer doubling. | `7.020602 s -> 5.911137 s` |
| Fixed-shape matrix math | Use the O2 A 20-stream shapes directly: common matrices are 12x10 and 12x12. | `5.911137 s -> 2.460360 s` |
| Layer and Fourier skips | Skip layers and terms that cannot contribute. | `2.460360 s -> 2.266849 s` |
| Fourier tail reuse | Reuse Fourier basis work and stop tiny tails. | `2.266849 s -> 2.025331 s` |
| Orders activity | Carry inactive-layer knowledge into scattering orders. | `2.025331 s -> 1.980342 s` |
| Q-series and D-update refinements | Skip empty q-series work, avoid redundant matrix outputs, and combine the D update. | final historical checkpoint around `1.9 s` forward elapsed time |
| Traced setup parallelism | Parallelize wavelength sampling, optical absorber setup, and layer accumulation in the trace harness. | `prepare_o2a 0.177154 s -> 0.044454 s`; trace forward `1.799918 s -> 1.538076 s` |

These changes are mostly data-handling and exact arithmetic-shape changes. They
do not change the retrieval math or the O2 A physical model.

Detailed mechanism notes are in [optimisation-notes](optimisation-notes/). Those
notes keep source links and Python-shaped explanations without copying long
Fortran or Zig excerpts.

The current remaining elapsed time is the exact repeated LABOS transport work described
in [remaining bottlenecks](remaining-bottlenecks.md).
