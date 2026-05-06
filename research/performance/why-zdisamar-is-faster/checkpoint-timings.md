# Checkpoint Timings

## Measurement Environment

```text
date        2026-05-06
machine     Mac mini, Mac16,10
chip        Apple M4
cores       10 total, 4 performance + 6 efficiency
memory      24 GB
os          macOS 26.3.1, Darwin 25.3.0, arm64
zig         0.15.2
```

## Run

```sh
MODE=all OUT=/tmp/zdisamar-perf-checkpoints.tsv \
  research/performance/why-zdisamar-is-faster/run-checkpoint-timings.sh
```

The script writes this shape:

```text
checkpoint  prepare_s  forward_s  total_s
```

## Timings

```text
checkpoint                             prepare_s  forward_s  total_s
511061b first_split_timer              -          79.767901  -
e23035b shared_grid_fast_intermediate  -          11.890893  -
56ec761 rtm_prep_tightened             -          34.762931  -
f8f495d tracked_plot_bundle            -          35.342751  -
207034e spectroscopy_partition         -          13.910915  -
163db7e python_validation_baseline     2.480369   35.364130  37.844499
5ef6c71 line_spectroscopy_and_grid     2.609367   8.357542   10.966909
b0a9e0f reusable_storage               2.671112   7.057182   9.728294
97088cf fused_doubling_math            2.666137   6.006493   8.672630
0ae1cad direct_matrix_math             2.667607   2.503199   5.170806
f42445d skip_empty_layers              2.701918   2.261732   4.963650
c423f4a fourier_tail                   0.436024   2.058945   2.494969
862511b final_checkpoint               0.440775   1.936090   2.376865
```

`-` in `prepare_s` means the old timing command did not measure the same `prepare_o2a` step.
`-` in `total_s` means no `prepare_s + forward_s` total is available for that row.
