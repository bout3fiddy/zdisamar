# Checkpoint Timings

## Measurement Environment

```
date        2026-05-06
machine     Mac mini, Mac16,10
chip        Apple M4
cores       10 total, 4 performance + 6 efficiency
memory      24 GB
os          macOS 26.3.1, Darwin 25.3.0, arm64
```

## Run

The checkpoint script was tied to the retired source-specific build surface and
was removed during the Rust port cleanup. The rows below remain historical
measurement evidence.

The retained table uses this shape:

```text
checkpoint  prepare_s  forward_s  total_s
```

The earliest split-timing rows came from historical branch commits. The script
reruns those rows only when the commit objects are present in the local checkout;
otherwise it prints a skip message and continues with the reachable checkpoints.

## Timings

```text
checkpoint                             prepare_s  forward_s  total_s
511061b first_split_timer              -          79.767901  -
e23035b shared_grid_fast_intermediate  -          11.890893  -
56ec761 rtm_prep_tightened             -          34.762931  -
f8f495d tracked_plot_bundle            -          35.342751  -
207034e spectroscopy_partition         -          13.910915  -
163db7e python_validation_baseline     2.480369   35.364130  37.844499
5ef6c71 line_spectroscopy_and_grid     2.475131   8.432518   10.907649
b0a9e0f reusable_storage               2.517755   7.020602   9.538357
97088cf fused_doubling_math            2.472634   5.911137   8.383772
0ae1cad direct_matrix_math             2.512803   2.460360   4.973163
f42445d skip_empty_layers              2.508870   2.266849   4.775719
c423f4a fourier_tail                   0.495153   2.025331   2.520484
f295ace layer_activity_orders          0.425659   1.980342   2.406001
07b19f3 zero_scatter_layers            0.476143   1.981844   2.457987
9138e6a pre_qseries_skips              0.436940   2.224609   2.661549
286c5b8 skip_zero_qseries              0.463377   2.147029   2.610406
63df87e qseries_precheck_reuse         0.439748   2.136820   2.576567
4791c22 separate_matrix_outputs        0.440496   1.915826   2.356323
baf0b4f fused_d_update                 0.408498   1.889351   2.297848
862511b final_checkpoint               0.509849   1.919895   2.429744
```

`-` in `prepare_s` means the old timing command did not measure the same `prepare_o2a` step.
`-` in `total_s` means no `prepare_s + forward_s` total is available for that row.
Rows are checkpoints. Accuracy changes can add work before later performance changes remove it again.
