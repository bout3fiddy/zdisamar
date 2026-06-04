# Codegen Study Benchmark Results

Source: [`dod_codegen_bench.zig`](dod_codegen_bench.zig)

Command:

```sh
zig run study/data_oriented_design_r_fabian_zdisamar/dod_book/codegen/dod_codegen_bench.zig -OReleaseFast
```

Run context:

- Zig `0.15.2`
- Darwin `arm64`
- `ReleaseFast`
- Single local run on 2026-06-04

These are microbenchmarks for the study examples. They prove a local source
shape on this machine, not a full `zdisamar` workload speedup.

## Results

| Pair | Result | Matching checksum |
|---|---:|---:|
| Optical depth column vs full layer rows | `1.49x` faster | yes |
| Caller-owned reflectance output vs allocate output every run | `1.50x` faster | yes |
| Prepared result indexes vs linear search | `803.65x` faster | yes |
| Dirty index list vs scanning all flags | `4.18x` faster elapsed time | yes |
| Grouped values vs branch on every flag | `33.56x` faster | yes |
| Worker-local sum vs write shared slot every item | `4.22x` faster | yes |
| Prepared prefix starts vs re-summing counts per query | `2039.62x` faster | yes |

Raw output:

```text
bench sum_optical_depth_aos items=262144 iterations=800 elapsed_ns=152716709 ns_per_item=0.728 checksum=10275104.800
bench sum_optical_depth_column items=262144 iterations=800 elapsed_ns=102669334 ns_per_item=0.490 checksum=10275104.800
ratio sum_optical_depth_column_vs_aos 1.49x
bench fill_reflectance_caller_output items=131072 iterations=300 elapsed_ns=26615500 ns_per_item=0.677 checksum=127247609.700
bench fill_reflectance_allocate_output items=131072 iterations=300 elapsed_ns=39982000 ns_per_item=1.017 checksum=127247609.700
ratio caller_output_vs_allocate_output 1.50x
bench integrate_prepared_indexes items=512 iterations=30 elapsed_ns=34917 ns_per_item=2.273 checksum=3113100.000
bench integrate_linear_search items=512 iterations=30 elapsed_ns=28061000 ns_per_item=1826.888 checksum=3113100.000
ratio prepared_indexes_vs_linear_search 803.65x
bench refresh_scan_all_flags items=262144 iterations=500 elapsed_ns=40637708 ns_per_item=0.310 checksum=14443544576.000
bench refresh_dirty_index_list items=16384 iterations=500 elapsed_ns=9724250 ns_per_item=1.187 checksum=14443544576.000
ratio dirty_index_list_vs_scan_all 4.18x
bench sum_selected_branchy items=262144 iterations=1000 elapsed_ns=146827667 ns_per_item=0.560 checksum=8387918000
bench sum_grouped_values items=131072 iterations=1000 elapsed_ns=4374958 ns_per_item=0.033 checksum=8387918000
ratio grouped_values_vs_branchy 33.56x
bench worker_local_sum items=262144 iterations=1000 elapsed_ns=129109250 ns_per_item=0.493 checksum=16776328000.000
bench worker_write_every_item items=262144 iterations=1000 elapsed_ns=544266666 ns_per_item=2.076 checksum=16776328000.000
ratio worker_local_vs_write_every_item 4.22x
bench query_prepared_starts items=262144 iterations=30 elapsed_ns=1105833 ns_per_item=0.141 checksum=257650852800
bench query_resum_counts items=262144 iterations=30 elapsed_ns=2255482042 ns_per_item=286.799 checksum=257650852800
ratio prepared_starts_vs_resum_counts 2039.62x
```

## Reading The Numbers

- Matching checksum means both sides produced the same observed result for the
  benchmark input.
- For dirty lists, compare elapsed time, not `ns_per_item`, because the list
  version intentionally processes fewer items.
- For grouped values, grouping setup is excluded. If grouping must happen every
  call, measure setup plus grouped execution together.
- For prefix starts, the prepared version assumes the starts were built once and
  reused across many queries.
