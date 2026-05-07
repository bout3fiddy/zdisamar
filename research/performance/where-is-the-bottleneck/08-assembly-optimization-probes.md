# 08. Assembly Optimization Probes

This pass looked for instruction-level changes that preserve the exact LABOS recurrence and improve speed. The retained changes are intentionally small: reuse each LU pivot reciprocal inside q-series instead of dividing by the same pivot repeatedly, dispatch the common 12x10 q-series path to a fixed-shape helper, compute 12x10 products in two-column vector lanes, keep row-major access in the elementwise 12x12 update helpers where it improves the production kernel bench, reuse the shared phase coefficient-column product in the fixed-12 phase fill, replace the effective-scattering odd-denominator divide with a reciprocal-table multiply, update doubled attenuation with squaring instead of repeated exponentials, specialize the fixed-12 attenuation squaring path, reuse the known `T` trace in the D update, reuse known traces inside the post-D products, avoid materializing threshold-skipped post-D products, specialize fixed 12-stream orders transport/accumulation loops, and avoid repeated zero stores for orders layers that were already initialized inactive.

## Optimization Summary

Maintain this section when a probe is retained or a retained artifact is regenerated. "Before" is the baseline trace at the start of this assembly-probe pass; "current retained" is the latest regenerated artifact with only accepted changes.

The currently regenerated retained artifact moves the main LABOS bottlenecks by:

| scope | before | current retained | saved | reduction |
| --- | ---: | ---: | ---: | ---: |
| forward wall | `1.912424833 s` | `1.724581500 s` | `0.187843 s` | `9.82%` |
| LABOS worker CPU | `10.918452 s` | `9.450074 s` | `1.468378 s` | `13.45%` |
| RT-layer construction | `7.868855 s` | `6.497375 s` | `1.371480 s` | `17.43%` |
| layer doubling | `5.849351 s` | `4.536551 s` | `1.312800 s` | `22.44%` |
| scattering orders | `2.904469 s` | `2.308949 s` | `0.595520 s` | `20.50%` |

A faster layer-doubling sample also occurred during the pass at `labos.rt_layer.doubling=4.517765 s`. The table above is the current regenerated artifact evidence.

Accuracy guardrail: the retained state passes `zig build check`, and `zig build test-validation-o2a-vendor` reports no significant residual movement versus the prior retained run. That lane still has its known allowed `fail_regression` status against the committed vendor baseline, but the residual snapshot did not materially change, so the speedups above are not being bought by accuracy loss. Probes that move checked residual or tangent tolerances are rejected rather than retained.

Accepted instruction-level wins:

| retained change | main measured win |
| --- | --- |
| q-series pivot reciprocal reuse | `qseries_nonzero_12x10` codegen `486.366 -> 479.056 ns/call` (`1.50%`), static FP divides `11 -> 1` |
| fixed 12x10 q-series helper | q-series production bench `546.484 -> 503.628 ns/call` (`7.84%`); layer doubling `5.849351 -> 5.779235 s` (`1.20%`) |
| two-lane 12x10 product | same-binary scratch codegen `smul_12x10` scalar `171.245 -> 152.700 ns/call` (`10.83%`); retained full trace LABOS worker CPU `9.740110 -> 9.450074 s` (`2.98%`) and layer doubling `4.748282 -> 4.536551 s` (`4.46%`) |
| row-major winning 12x12 updates | `matAddEsmul3_12` `90.744 -> 86.204 ns/call` (`5.00%`); `esmulSemulAdd_12` `93.381 -> 92.887 ns/call` (`0.53%`) |
| fixed-12 phase coefficient-column reuse | phase matrix construction `1.124197 -> 1.029042 s` (`8.46%`); full wall `1.907507125 -> 1.892693667 s` (`0.78%`) |
| effective-scattering reciprocal table | beta scan `8.591 -> 3.524 ns/call` (`58.98%`) |
| squared attenuation during doubling | removed `46,229,532` doubling-loop exponentials; layer doubling `5.689105 -> 5.515518 s` (`3.05%`) |
| fixed-12 attenuation squaring | layer doubling `5.515518 -> 5.429431 s` (`1.56%`) |
| known-right-trace D update | layer doubling `5.429431 -> 4.706511 s` (`13.31%`); LABOS worker CPU `10.545842 -> 9.690431 s` (`8.11%`) |
| known traces in post-D products | layer doubling `6.036863 -> 5.812329 s` (`3.72%`) in the retained trace sample for that probe |
| zero-aware post-D updates | skipped materializing millions of below-threshold `R*D`, `T*U`, and `T*D` products; retained current counters show `14,237,502` skipped product slots |
| lazy inactive orders local fields | scattering orders `2.407124 -> 2.335709 s` (`2.97%`); LABOS worker CPU `9.784209 -> 9.740110 s` (`0.45%`) |

Rejected probes are kept in this file because they are useful negative evidence. The main rejects were: bit-seeded Newton reciprocal (`470.210 -> 516.338 ns/call`, slower despite no static `fdiv`), direct result-as-inverse q-series workspace (larger code and no clear speedup), fully unrolled q-series LU (isolated bench improved, full trace regressed), single-operand q-series square product, two-lane q-series extra blocks, returning `Q` with its trace, two-accumulator trace scans, FMA/vector/batched/fused dot-pair variants, hoisted dot-pair `n_gauss` branch, four-lane 12x10 product, two-lane row-major `matAddEsmul`, two-lane row-major `esmulSemul`, row-major single scatter, reflectance reciprocal scale, two-lane dynamic orders transport, row-major `semul12`, no-pivot q-series, symmetric phase fill, scalarized phase-fill columns, returning `D`/`U` with traces, folded q-series product trace, fused `R*D` U update, fused `T*D` T update, fused `T*U` R update, two-lane D update, activity-aware orders transport, fixed-12 initial source fill, selective inactive local initialization, fixed-12 initial exponential fill, removing duplicate fixed-qseries pivot bookkeeping, and precomputing the initial-exponential reciprocal.

## Kept: Q-Series Pivot Reciprocals

The q-series solve factors the 10x10 Gauss block of `I - R*R`. Before this pass, elimination and back-substitution both divided by pivot diagonal values:

```zig
const factor = one_minus_ab_gg[row_offset + col] / diag;
x[ii] = s / one_minus_ab_gg[row_offset + ii];
```

The retained version computes the reciprocal once after the singular-pivot guard:

```zig
const inv_diag = 1.0 / diag;
inverse_diag[col] = inv_diag;
const factor = one_minus_ab_gg[row_offset + col] * inv_diag;
x[ii] = s * inverse_diag[ii];
```

This keeps the same pivot choices and solve structure. It changes rounding from repeated division to reciprocal-then-multiply, so it must remain covered by O2 A validation.

Same-probe codegen evidence:

| operation | before | after |
| --- | ---: | ---: |
| `qseries_nonzero_12x10` isolated timing | `486.366 ns/call` | `479.056 ns/call` |
| static floating-point divides | `11` | `1` |
| static instructions | `4,022` | `4,035` |

The isolated speedup is modest because the q-series path still has the matrix product, pivot search, triangular solves, and block products. Removing divide instructions does not remove the surrounding recurrence.

## Rejected: Bit-Seeded Newton Reciprocal In Q-Series

The retained q-series solve still executes one hardware divide per pivot to form `1.0 / diag`. A research-only variant replaced that divide with a bit-level reciprocal seed followed by four Newton refinements:

```zig
var y: f64 = @bitCast(@as(u64, 0x7fe0000000000000) - @as(u64, @bitCast(@abs(diag))));
inline for (0..4) |_| y *= 2.0 - @abs(diag) * y;
```

That variant removed the remaining static `fdiv` from the extracted q-series disassembly and matched the deterministic harness checksum, but it was slower in the same run: retained hardware reciprocal formation was `470.210 ns/call`; the Newton variant was `516.338 ns/call`. Static q-series instructions also moved from `4,035` to `4,047`. The hardware divide stays because replacing it added more dependent floating-point work than it removed on the retained target.

## Rejected: Direct Result Matrix As Q-Series Inverse Workspace

The q-series solve computes the 10x10 inverse of the Gauss block, copies that inverse into the result's Gauss block as `inverse - I`, then uses the inverse for the two extra rows and columns. A probe wrote the solved inverse columns directly into the 12x12 result matrix, used that as the inverse workspace for the extra blocks, and subtracted the identity at the end.

The deterministic checksum stayed the same, but code shape got worse: extracted q-series instructions moved from `4,035` to `4,046`, and the isolated timing landed at `469.588 ns/call`, inside the retained q-series run-to-run band rather than a clear speedup. Because this expands the machine code and does not produce a measured win, the dense 10x10 inverse workspace stays.

## Rejected: Fully Unrolled Q-Series LU

The fixed 12x10 q-series helper still uses runtime loops for the pivot columns and trailing LU updates. A probe changed those loops to `inline for` while preserving partial pivoting, singular-pivot checks, reciprocal reuse, triangular solves, and block writes.

The isolated production bench looked attractive in one A/B: `qseries_nonzero_12x10` moved from `496.655 ns/call` without the unroll to `444.220 ns/call` with it. That did not survive the full trace. A retained-code repeat with the unroll regressed to `forward_wall_s=1.837271959`, `labos_execute_cpu_s=10.298741`, and `labos.rt_layer.doubling=5.006188 s`. The unrolled helper also expanded the extracted q-series disassembly to `5,699` static instructions and `10` static floating-point divides when the helper was included in the summary. The looped pivoted helper stays.

## Rejected: Removing Duplicate Fixed-Qseries Pivot Bookkeeping

The fixed 12x10 q-series LU stores both the pivoted original row index and the pivoted row offset. Since `pivot_offset / 10` identifies the same original row, a probe removed the `pivot` array and tested right-hand-side identity rows with `pivot_offset[i] == rhs_col * 10`.

The solve and residuals stayed unchanged, but the code shape got worse. In the full trace, `qseries_nonzero_12x10` moved from the retained artifact sample's `492.218 ns/call` to `498.278 ns/call`, `labos_execute_cpu_s` moved from `9.639948` to `9.720218`, and `labos.rt_layer.doubling` moved from `4.672972 s` to `4.704685 s`. Keeping the explicit `pivot` array gives LLVM a better fixed-helper shape.

## Rejected: Folded Q-Series Product Trace

The fixed q-series path builds the 12x10 `R*R` product and then scans the ten Gauss diagonal entries of that product before deciding whether the q-series solve is needed. A probe accumulated that Gauss trace while writing the fixed 12x10 product and passed it directly into the q-series solver.

This removed the separate diagonal scan, but it made the product code shape worse. Against the retained regenerated artifact, `qseries_nonzero_12x10` moved from `502.570 ns/call` to `507.803 ns/call`, `labos_execute_cpu_s` from `9.813451` to `10.044588`, `rt_layer_build_cpu_s` from `6.750284` to `7.013396`, and `labos.rt_layer.doubling` from `4.779916 s` to `4.995814 s`. The separate product-trace scan stays.

## Rejected: Single-Operand Q-Series Square Product

The q-series product in layer doubling is always `R*R`, so a probe specialized the fixed 12x10 product to one input pointer when `qseriesKnownNonzeroProduct` sees `a == b`. The goal was to give LLVM a simpler alias/load model than the two-pointer `smul12x10` shape while keeping the same multiply-add order for every output cell.

The deterministic result stayed unchanged, but the full trace rejected it. The isolated `qseries_nonzero_12x10` bench did not prove a win (`504.094 ns/call` retained artifact sample versus `495.508 ns/call` in a noisy probe), and the real recurrence regressed: `labos_execute_cpu_s` moved to `10.206952`, `rt_layer_build_cpu_s` to `7.121154`, and `labos.rt_layer.doubling` to `5.152091 s`. The two-pointer product stays.

## Rejected: Two-Lane Q-Series Extra Blocks

After the fixed 10x10 inverse is solved, q-series fills the two extra rows and columns with small ten-term dot products. A probe packed the two extra columns and the two extra rows into two-lane vectors while leaving the pivoted LU solve unchanged.

The fast gate passed and the deterministic bench checksum stayed unchanged, but the production kernel bench rejected the code shape. In the same turn, retained code measured `qseries_nonzero_12x10=466.574 ns/call`; the extra-block vector probe moved it to `484.703 ns/call`, and `qseries_12x10` also worsened sharply. The scalar extra-block dot products stay.

## Rejected: Returning `Q` With Its Trace

The q-series branch immediately uses the q-series result `Q` in the D update, and the D update scans the Gauss trace of `Q` to decide whether `Q*T` is below threshold. A probe accumulated that trace while writing the q-series result and passed it into the known-trace D update.

The fast gate passed and mean reflectance stayed unchanged. The first full trace looked slightly better (`labos.rt_layer.doubling=4.517743 s`, `labos_execute_cpu_s=9.437647`), but the repeat rejected it (`labos.rt_layer.doubling=4.550235 s`, `labos_execute_cpu_s=9.531073`). The q-series result writer stays scalar and the D update keeps its separate `Q` trace scan.

## Rejected: Two-Accumulator Trace Scans

The fixed `gaussTrace` helper used in layer doubling sums ten Gauss diagonal entries in a single dependency chain. A probe split that into even and odd accumulators, then added those two partial sums at the end.

The fast gate passed and mean reflectance stayed unchanged, but the full trace rejected the math ordering: `labos.rt_layer.doubling` moved from `4.536551 s` to `4.662084 s`, `rt_layer_build_cpu_s` moved from `6.497375` to `6.642285`, and `labos_execute_cpu_s` moved from `9.450074` to `9.610294`. The serial trace sum stays.

## Kept: Fixed 12x10 Q-Series Helper

The generic `qseriesFromProduct` accepted runtime `n` and `n_gauss` values even though the retained O2 A scene uses the common `12x10` LABOS shape. The kept helper dispatches that shape to `qseriesFromProduct12x10`, where the trace, Gauss-block setup, result blocks, and extra-row/column products use fixed loop bounds.

The helper preserves the same q-series contract: it still computes `I - R*R`, keeps the same pivot search and singular-pivot guard, uses the reciprocal-reuse solve above, and writes the same result blocks. The change is code shape, not a change in the layer-doubling recurrence.

The q-series-only retained trace kept the win before the later zero-aware product update:

| metric | before | after |
| --- | ---: | ---: |
| forward wall | `1.912424833 s` | `1.907103833 s` |
| LABOS worker CPU | `10.918452 s` | `10.783698 s` |
| RT-layer construction | `7.868855 s` | `7.779656 s` |
| layer doubling | `5.849351 s` | `5.779235 s` |
| `qseries_nonzero_12x10` production bench | `546.484 ns/call` | `503.628 ns/call` |

The mean reflectance stayed at `1.69299446204588800e-1`.

## Kept: Two-Lane 12x10 Product

The retained 12x10 product still computes every output cell with the same ten-term multiply-add chain. The change is that adjacent output columns are evaluated as a two-lane vector:

```zig
const a0: @Vector(2, f64) = @splat(a.data[row]);
var s = a0 * loadPair(b0, j);
s += a1 * loadPair(b1, j);
result.data[row + j] = s[0];
result.data[row + j + 1] = s[1];
```

The scratch codegen A/B kept the deterministic checksum and moved `smul_12x10` from `171.245 ns/call` in the scalar shape to `152.700 ns/call` in the two-lane shape. The retained codegen artifact now measures the production `smul_12x10` shape at `169.672 ns/call` with `2,195` static instructions, `1,368` floating-point arithmetic instructions, and no floating-point divides. The q-series package gets larger in static codegen because it includes the product shape (`4,035 -> 4,450` extracted instructions in the retained harness), but the full trace retained the production change: LABOS worker CPU moved from `9.740110 s` to `9.450074 s`, RT-layer construction from `6.747290 s` to `6.497375 s`, and layer doubling from `4.748282 s` to `4.536551 s`. A faster accepted layer-doubling repeat hit `labos.rt_layer.doubling=4.517765 s`.

Accuracy stayed on the current guardrail: `zig build check` passed, the trace mean reflectance stayed at `1.69299446204591420e-1`, and `zig build test-validation-o2a-vendor` reported the same current residual snapshot as the prior retained run.

## Rejected: Four-Lane 12x10 Product

The retained two-lane product suggested trying four adjacent output columns at once with `@Vector(4, f64)`. In the standalone same-binary probe, that looked promising: the two-lane product measured `185.081 ns/call` in that noisy run and the four-lane variant measured `170.171 ns/call`, with the same checksum.

The full trace rejected it. The production four-lane probe passed `zig build check` and kept the trace mean reflectance at `1.69299446204591420e-1`, but it moved `forward_wall_s` to `1.780515583`, `labos_execute_cpu_s` to `9.876031`, `rt_layer_build_cpu_s` to `6.945820`, and `labos.rt_layer.doubling` to `4.979174 s`. The retained two-lane shape stays because the wider vector shape increased pressure in the actual recurrence even though it looked good in the isolated harness.

## Rejected: Two-Lane D Update

The same two-column vector shape was tested inside the nonzero `D = T + Q*diag(E) + Q*T` update. That kept the same per-cell product order and only packed adjacent output columns into vector lanes, but it also needed a local comptime branch-quota bump for the fixed helper.

The fast gate passed and the trace mean reflectance stayed unchanged. One trace looked slightly better (`labos_execute_cpu_s=9.508355`, `labos.rt_layer.doubling=4.527815 s`), but the repeat rejected it: `labos_execute_cpu_s=9.678544`, `rt_layer_build_cpu_s=6.653535`, `labos.rt_layer.doubling=4.638905 s`, and `orders_cpu_s=2.362374`. Since the retained scalar D update is simpler and the vector version did not produce robust end-to-end speed, only the standalone 12x10 product keeps the two-lane shape.

## Kept: Row-Major Elementwise Updates

Several 12x12 update helpers used column-major loop order over row-major storage. Reordering the winning helpers to row-major keeps each element formula unchanged while making the hot loads and stores contiguous:

```zig
const row = i * 12;
const idx = row + j;
result.data[idx] = (a.data[idx] + ei * b.data[idx]) + c.data[idx];
```

The retained production bench sample moved `matAddEsmul3_12` from the original `90.744 ns/call` retained baseline to `86.204 ns/call`, and `esmulSemulAdd_12` from `93.381 ns/call` to `92.887 ns/call`. A direct A/B also showed `semulAdd_12` as neutral to slightly worse, so it kept the original column-major layout.

## Rejected: Two-Lane Row-Major `matAddEsmul`

A follow-up probe packed adjacent row-major cells into two-lane vectors for `matAddEsmul3_12` and `matAddEsmul12`. The arithmetic grouping stayed the same and `zig build check` passed, but the same-turn production bench rejected it: `matAddEsmul3_12` moved from `89.506` to `90.819 ns/call`, and `matAddEsmul_12` moved from `67.324` to `72.787 ns/call`, with unchanged checksums. The retained scalar row-major helpers stay because LLVM's scalar shape is faster for these simple elementwise updates.

## Rejected: Two-Lane Row-Major `esmulSemul`

The same adjacent-cell vector shape was tested for `esmulSemul12` and `esmulSemulAdd12`, where each result cell uses both the row attenuation `e[i]` and column attenuation `e[j]`. The fast gate passed and checksums stayed unchanged, but the production bench worsened: `esmulSemul_12` moved from `81.142` to `87.495 ns/call`, and `esmulSemulAdd_12` moved from `92.888` to `96.615 ns/call`. These helpers keep the scalar row-major shape.

## Kept: Fixed-12 Phase Coefficient-Column Reuse

The phase fill computes:

```text
Zplus[i,j] += alpha * plus[i] * plus[j]
Zmin[i,j]  += alpha * minus[i] * plus[j]
```

The old fixed-12 fill multiplied `alpha * plus[i]` and `alpha * minus[i]` once per row, then multiplied by `plus[j]` for every matrix cell. The retained fill instead computes `alpha * plus[j]` once per column and reuses that column value for both `Zplus` and `Zmin`:

```zig
scaled_plus_col[j] = alpha1 * plus_l[j];
zplus.data[idx] += plus_i * scaled_plus_col[j];
zmin.data[idx] += minus_i * scaled_plus_col[j];
```

This changes floating-point association, so it was retained only after the O2 A trace kept the same mean reflectance.

| metric | before | after |
| --- | ---: | ---: |
| `phase_fill_12x16` microbench | `588.032 ns/call` | `568.699 ns/call` |
| forward wall trace sample | `1.907507125 s` | `1.892693667 s` |
| LABOS worker CPU | `10.807012 s` | `10.762460 s` |
| RT-layer construction | `7.738703 s` | `7.691103 s` |
| phase matrix construction | `1.124197 s` | `1.029042 s` |

The mean reflectance stayed at `1.69299446204588800e-1`.

## Kept: Effective-Scattering Odd Reciprocal Table

The RT-layer effective-scattering scan computes:

```zig
abs(phase_coefs[l]) / (2*l + 1)
```

for every active phase coefficient. The denominator only depends on the coefficient index, so the retained code precomputes `1 / (2*l + 1)` once at comptime and uses a multiply in the scan:

```zig
const beta_eff = @abs(phase_coefs[ic]) * phase_odd_reciprocal[ic];
```

This is a narrow divide-removal probe. It is too small to move the full wall reliably, but the same-run scalar benchmark isolates the exact scan shape:

| operation | ns/call |
| --- | ---: |
| `phase_beta_scan_div_16` | `8.591` |
| `phase_beta_scan_recip_16` | `3.524` |

The retained trace mean reflectance stayed at `1.69299446204588800e-1`.

## Rejected: Row-Major Single Scatter

The fixed 12-stream single-scatter builders still write `Rsingle` and `Tsingle` in column order because the formula reuses the column attenuation `E[j]`. A probe rewrote both fixed helpers to row-major loops, keeping the same per-cell formulas but making matrix writes contiguous.

The fast gate passed and the temporary trace kept the same mean reflectance, but the section timing rejected it. Against the retained artifact, `labos.rt_layer.single_scatter` moved from `0.185008 s` to `0.311450 s`, `labos_execute_cpu_s` moved from `9.450074` to `9.592553`, and `rt_layer_build_cpu_s` moved from `6.497375` to `6.614713`. The fixed single-scatter helpers keep their column-major loop shape.

## Rejected: Reflectance Reciprocal Scale

The integrated reflectance reduction repeatedly computes `(0.25 * phase / view_mu) / mu` for the Gauss streams and solar stream. A probe precomputed the per-stream reciprocal scale once per reflectance call and multiplied each phase row entry by that scale inside the level loop.

The first temporary trace looked slightly better (`labos.reflectance_integral=0.187729 s`, `labos_execute_cpu_s=9.430072`), but the repeat rejected it (`labos.reflectance_integral=0.191426 s`, `labos_execute_cpu_s=9.962353`). Because the speedup was not repeatable and the probe changes floating-point association, the direct divide form stays.

## Kept: Squared Attenuation In Doubling

Layer doubling doubles the optical thickness after each recurrence step. The attenuation vector is:

```text
E(mu) = exp(-b / mu)
```

After a doubling step, the new thickness is `2*b`, so the next attenuation is:

```text
exp(-2*b / mu) = exp(-b / mu) * exp(-b / mu)
```

The previous implementation recomputed `exp(-b/mu)` while the doubled thickness was still below `0.001`, then switched to squaring later. The retained implementation squares every doubling update:

```zig
const e = E.data[imu];
E.data[imu] = e * e;
```

This removes `46,229,532` traced exponential evaluations from the doubling loop in the retained spectrum. The current trace counts only the initial layer exponentials and the `100,675,992` squared attenuation updates inside doubling.

| metric | before | after |
| --- | ---: | ---: |
| forward wall trace sample | `1.892693667 s` | `1.874757250 s` |
| LABOS worker CPU | `10.762460 s` | `10.679694 s` |
| RT-layer construction | `7.691103 s` | `7.588468 s` |
| layer doubling | `5.689105 s` | `5.515518 s` |

The vendor validation lane still exits with its known allowed `fail_regression` status. Its current residuals stayed at the same scale: mean absolute difference `0.009099922227437973`, RMS `0.01833690112331791`, and max absolute difference `0.09712867446722206`.

## Kept: Fixed-12 Attenuation Squaring

After the full-squaring change, the doubling loop still squared the attenuation vector through a tiny runtime loop:

```zig
for (0..n) |imu| {
    const e = E.data[imu];
    E.data[imu] = e * e;
}
```

The retained O2 A shape has `nmutot = 12`, so the current implementation dispatches that common case to an `inline for` helper:

```zig
inline for (0..basis.max_nmutot) |imu| {
    const e = E.data[imu];
    E.data[imu] = e * e;
}
```

This is a code-shape change only. It keeps the same per-stream squaring order and the same `100,675,992` traced square evaluations, but removes the runtime loop branch from the common path.

| metric | before | after |
| --- | ---: | ---: |
| forward wall trace sample | `1.874757250 s` | `1.868990042 s` |
| LABOS worker CPU | `10.679694 s` | `10.545842 s` |
| RT-layer construction | `7.588468 s` | `7.463416 s` |
| layer doubling | `5.515518 s` | `5.429431 s` |

The mean reflectance stayed at `1.69299446204591420e-1`.

## Kept: Known Right Trace In D Update

The nonzero q-series branch builds:

```zig
const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
const D = basis.smulAddSemul3(n, n_gauss, threshold_mul, &Q, E, T);
const trace_t = gaussTrace(n, n_gauss, T);
```

The fused `D` update needs the Gauss trace of `T` to decide whether `Q*T` is below threshold, and the doubling loop needs the same trace immediately afterward for `T*U` and `T*D`. The retained version computes it once before the branch and passes it into a known-right-trace D update:

```zig
const trace_t = gaussTrace(n, n_gauss, T);
const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
const D = basis.smulAddSemul3KnownRightTrace(n, n_gauss, threshold_mul, &Q, E, T, trace_t);
```

The threshold decision and product arithmetic are unchanged. The current production bench isolates the new entrypoint at `175.172 ns/call` for the retained seed versus `186.555 ns/call` for the self-tracing D helper. The standalone codegen harness shows the same shape: `smul_add_semul3_known_right_trace_12` is `2,842` static instructions versus `2,851` for the self-tracing helper. The main evidence is the repeated full trace:

| metric | before | after |
| --- | ---: | ---: |
| forward wall trace sample | `1.868990042 s` | `1.741731291 s` |
| LABOS worker CPU | `10.545842 s` | `9.690431 s` |
| RT-layer construction | `7.463416 s` | `6.681360 s` |
| layer doubling | `5.429431 s` | `4.706511 s` |

The mean reflectance stayed at `1.69299446204591420e-1`.

## Kept: Known Traces In Doubling Products

The three post-D matrix products use `smul` threshold guards based on Gauss-block traces. The doubling loop already knows `trace_r`, can reuse one `trace_t`, and can reuse one `trace_d` across both `R*D` and `T*D`:

```zig
const trace_t = gaussTrace(n, n_gauss, T);
const trace_d = if (q_is_zero) trace_t else gaussTrace(n, n_gauss, &D);
basis.smulIntoKnownTraces(&rd, n, n_gauss, threshold_mul, trace_r, trace_d, R, &D);
```

This preserves the same threshold decisions and product arithmetic, but avoids recomputing duplicate traces inside each product call. The retained trace sample moved `labos.rt_layer.doubling` from the original `6.036863 s` retained baseline to `5.812329 s`.

## Kept: Zero-Aware Post-D Product Updates

The post-D products already use threshold guards. In the retained scene, those guards skip millions of products:

| product slot | attempted | nonzero | skipped |
| --- | ---: | ---: | ---: |
| `R*D` | `8,389,666` | `3,608,073` | `4,781,593` |
| `T*U` | `8,389,666` | `3,523,139` | `4,866,527` |
| `T*D` | `8,389,666` | `3,800,284` | `4,589,382` |

Before this probe, a skipped product still wrote a zero matrix and the following elementwise update still added that zero matrix. The retained version lets the trace-known product helper return whether a product was nonzero. If the product is below threshold, the following update uses the corresponding two-term helper:

```zig
const U = if (rd_nonzero)
    basis.semulAdd(n, R, E, &rd)
else
    basis.semul(n, R, E);
```

The threshold decision is unchanged; the zero contribution is just not materialized. The retained trace moved the key metrics:

| metric | before | after |
| --- | ---: | ---: |
| forward wall | `1.907103833 s` | `1.846722292 s` |
| LABOS worker CPU | `10.783698 s` | `10.631653 s` |
| RT-layer construction | `7.779656 s` | `7.611183 s` |
| layer doubling | `5.779235 s` | `5.617321 s` |
| primitive estimate | `8.927998 s` | `6.105430 s` |

The mean reflectance stayed at `1.69299446204588800e-1`.

## Rejected: Fused `R*D` U Update

After zero-aware product updates, the nonzero `R*D` path still materializes the product matrix and then immediately computes `U = R*diag(E) + R*D`. A probe fused those two steps into one helper so each output cell used the same ten-term `R*D` product sum and then added the `R*diag(E)` term without writing and rereading the product matrix.

The deterministic result stayed unchanged, but the full trace rejected the larger helper. Against the retained artifact, `labos_execute_cpu_s` moved from `9.688637` to `9.967110`, `rt_layer_build_cpu_s` from `6.668302` to `6.910673`, and `labos.rt_layer.doubling` from `4.704148 s` to `4.886777 s`. The materialized `R*D` product plus separate `semulAdd` stays.

## Rejected: Fused `T*D` T Update

The matching nonzero `T*D` path was also tested as a fused helper for `T_next = diag(E)*D + T*diag(E) + T*D`. The helper kept the same threshold decision and formed the same ten-term `T*D` product for each cell before adding the two attenuation-scaled terms, avoiding the materialized product matrix in the nonzero path.

This variant was rejected before a full trace because it failed the fast correctness gate. `zig build check` moved the semi-analytical surface-albedo tangent to `0.7229812902384871` versus the finite-difference expected value `0.7229843792394552`, just outside the existing `3.0e-6` absolute tolerance. Since the assembly-probe rule is to avoid residual/tangent regressions while improving speed, the materialized `T*D` product plus separate `esmulSemulAdd` stays.

## Rejected: Fused `T*U` R Update

The remaining post-D materialization boundary is `R_next = R + diag(E)*U + T*U`. A probe fused the nonzero `T*U` product into the `R_next` update so the ten-term product sum was added directly to the two-term attenuated update, while the skipped-product path still used `R + diag(E)*U`.

This probe passed `zig build check` and kept the trace mean reflectance at `1.69299446204591420e-1`, but the full trace rejected it on speed. Against the regenerated retained artifact, the fused probe moved `forward_wall_s` from `1.773066917` to `1.796283958`, `labos_execute_cpu_s` from `9.784209` to `9.881391`, `rt_layer_build_cpu_s` from `6.712392` to `6.862394`, and `labos.rt_layer.doubling` from `4.731957 s` to `4.892065 s`. The materialized `T*U` product plus separate `matAddEsmul3` stays.

## Kept: Fixed 12-Stream Orders Transport And Accumulation

The O2 A validation scene uses the common LABOS shape `n_gauss = 10` and `nmutot = 12`. The scattering-order transport and accumulation sections were still running tiny runtime loops over those 12 streams. The retained version keeps the generic loops for other shapes, but dispatches the common shape to fixed-width helpers:

```zig
if (nmutot == basis.max_nmutot) {
    transportToOtherLevels12(start_level, end_level, atten, ud_local, ud_orde);
    return;
}
```

Inside the fixed helper, `inline for (0..basis.max_nmutot)` removes the runtime loop branch and lets the compiler see each stream index directly. The arithmetic order for each output element is unchanged:

```zig
out_u0[imu] = local_u0[imu] + att * prev_u0[imu];
out_u1[imu] = local_u1[imu] + att * prev_u1[imu];
```

This is a useful instruction-level win because the transport helper is called after every multiple-scattering order, and accumulation visits the same 12-stream fields for every retained order contribution. The retained tracked trace moved the targeted sections as follows:

| section | before | after |
| --- | ---: | ---: |
| `labos.orders.initial_transport` | `0.337520 s` | `0.242214 s` |
| `labos.orders.transport` | `0.680312 s` | `0.483029 s` |
| `labos.orders.accumulate` | `0.281094 s` | `0.130923 s` |
| `labos.orders.total` | `2.904469 s` | `2.447930 s` |

The retained mean reflectance stayed at `1.69299446204588800e-1`; this change only unrolls fixed-size per-stream recurrence updates and does not change convergence thresholds or dot-product ordering.

## Kept: Dynamic Attenuation Indexing In Fixed Orders Transport

The retained forward path passes a `DynamicAttenArray` into orders. Its generic `get` method computes:

```zig
(imu * nlevel + from) * nlevel + to
```

for every stream load. The fixed 12-stream transport helper now has a `DynamicAttenArray` path that precomputes `nlevel * nlevel` and the per-level `(from, to)` offset once per level:

```zig
const stream_stride = nlevel * nlevel;
const level_offset = (ilevel - 1) * nlevel + ilevel;
const att = atten.data[imu * stream_stride + level_offset];
```

This keeps the same attenuation values and recurrence arithmetic. Two temporary traces kept the win: `labos.orders.transport` moved from the fixed-12 retained `0.483029 s` to `0.421700 s` and `0.418163 s`; total orders moved from `2.447930 s` to `2.373844 s` and `2.406741 s`. The tracked retained trace after later doubling, phase-fill, beta-scan, and attenuation-squaring updates has `labos.orders.transport = 0.448110 s` and `labos.orders.total = 2.426293 s`.

## Rejected: Two-Lane Dynamic Orders Transport

The dynamic-attenuation transport helper updates two source columns for each stream with the same attenuation value. A probe packed those two column updates into a two-lane vector while keeping the direct dynamic attenuation index and the same recurrence.

The fast gate passed and mean reflectance stayed unchanged, but the temporary trace rejected it. Against the retained artifact, `labos.orders.transport` moved from `0.439610 s` to `0.440710 s`, `labos.orders.total` stayed effectively flat at `2.308891 s`, and `labos_execute_cpu_s` worsened from `9.450074` to `9.565956`. The scalar two-column stores stay.

## Kept: Lazy Inactive Orders Local Fields

Inactive orders layers are known from the RT-layer activity mask before scattering orders run. The orders workspace already initializes every local `U` and `D` vector to zero at the start of each orders call, so repeatedly writing zeros for the same inactive local fields inside every scattering-order iteration was redundant store traffic. The retained version leaves those initialized zeros in place and skips the per-iteration inactive zero stores.

This does not change the active dot-product recurrence or the activity decision. It only relies on the existing invariant that inactive local fields are zero after workspace initialization and are never written by the active-layer path. The retained trace kept the mean reflectance at `1.69299446204591420e-1`, and `zig build test-validation-o2a-vendor` reported the same current residual snapshot as the prior retained state: mean abs `0.009099922227437973`, RMS `0.01833690112331791`, max abs `0.09712867446722206`.

The measured win is concentrated in the orders sections:

| section | before | after |
| --- | ---: | ---: |
| `labos.orders.initial_sources` | `0.136804 s` | `0.104437 s` |
| `labos.orders.local_down` | `0.639451 s` | `0.608480 s` |
| `labos.orders.local_up` | `0.617313 s` | `0.612293 s` |
| `labos.orders.total` | `2.407124 s` | `2.335709 s` |
| LABOS worker CPU | `9.784209 s` | `9.740110 s` |

## Rejected: Activity-Aware Orders Transport

After lazy inactive local fields, transport still read the initialized zero local vectors for inactive layers and computed `local + attenuation * previous`. A probe passed the RT-layer activity mask into transport and used `attenuation * previous` directly for inactive local fields, removing the zero add and local-vector load in those branches.

The fast gate passed and the trace mean reflectance stayed at `1.69299446204591420e-1`, but the full-trace result was not robust enough to retain. Three probe traces improved `labos.orders.total` to `2.256758 s`, `2.279318 s`, and `2.278624 s`, but aggregate LABOS worker CPU was mixed: `9.576272 s`, `9.739226 s`, and `9.605078 s`. Because the objective is retained end-to-end speed, not just a local section improvement with unstable aggregate behavior, the simpler transport recurrence stays.

## Rejected: Fixed-12 Initial Source Fill

The initial orders source fill still uses runtime loops over `nmutot` even though the retained O2 A shape has 12 streams. A probe added fixed-12 `inline for` paths for the initial `E`, local `D`, and local `U` source writes while keeping the same `atten.get` calls and the same matrix-column products.

The fast gate passed and mean reflectance stayed unchanged, but the full trace rejected the code shape. `labos.orders.initial_sources` moved from the retained `0.100438 s` artifact to `0.105041 s`, `labos.orders.total` from `2.307039 s` to `2.313068 s`, and `labos_execute_cpu_s` from `9.617986` to `9.761228`. The compact runtime loops stay.

## Rejected: Selective Inactive Local Initialization

After retaining lazy inactive local fields, a follow-up probe tried to avoid the broad `ud_local` zero initialization at the start of each orders call. It initialized only vector metadata first, waited until the activity mask was known, then zeroed only inactive local fields plus the boundary `D` field.

The fast gate passed, but repeat traces rejected it. One run looked neutral (`labos_execute_cpu_s=9.590085`, `labos.orders.total=2.308765 s`), while the repeat worsened to `labos_execute_cpu_s=9.775277` and `labos.orders.total=2.342637 s`. The broad local zero initialization remains because the selective version adds extra branching and did not produce a robust retained speedup.

## Rejected: Broad Fused Multiply-Add

Replacing the 10-term matrix products and q-series reductions with explicit `@mulAdd` did generate `fmadd` instructions, but it slowed the important primitives in the same temporary probe run:

| operation | reciprocal-only | broad FMA probe |
| --- | ---: | ---: |
| `smul_12x10` | `162.527 ns/call` | `213.923 ns/call` |
| `smul_add_semul3_12` | `182.122 ns/call` | `281.426 ns/call` |
| `qseries_nonzero_12x10` | `458.423 ns/call` | `607.168 ns/call` |

The likely reason is code shape: scalar FMA disrupted the vectorized multiply/add code that LLVM was already producing for the fixed 12x10 matrix kernels.

## Rejected: Dot-Pair FMA

Applying `@mulAdd` only to `dotGaussPair` improved the isolated harness from about `4.302 ns/call` to `3.817 ns/call`, but repeat full-trace runs did not improve the orders section. The candidate was rejected because the objective requires speed improvement in the real bottleneck, not only in an isolated mock-data primitive.

An explicit two-lane vector `dotGaussPair` was also rejected. It improved the standalone harness more strongly (`4.274 ns/call` to `3.263 ns/call`), but the full trace worsened the orders section (`2.796190 s` retained sample to `3.104619 s` in the probe), so the scalar dot-pair implementation remains.

A batched two-matrix dot-pair helper was rejected for the same reason. It preserved separate dot accumulations and only moved the final addition into one helper, but the full trace worsened the orders section to `3.119371 s`.

## Rejected: Hoisted Dot-Pair `n_gauss` Branch

The local orders propagation calls `dotGaussPair` at high volume. A narrower probe than the earlier fixed-call-site specialization added a `dotGaussPair10` helper and hoisted the `n_gauss == 10` branch outside the per-row dot calls, while keeping the runtime row loop shape.

The fast gate passed and the mean reflectance stayed unchanged, but the full trace rejected it: `labos.orders.total` moved from `2.308949 s` to `2.579721 s`, with `labos.orders.local_down` at `0.735016 s` and `labos.orders.local_up` at `0.718782 s`. The original in-helper branch shape stays.

## Rejected: Fixed 12-Stream Local Dot-Pair Call Sites

The local up/down propagation loops still call `dotGaussPair` at very high volume. A temporary call-site specialization removed the `n_gauss == 10` branch from those calls and unrolled the 12 output rows around the same ten-term dot products. The real trace rejected it: `labos.orders.local_down` worsened from `0.630390 s` to `0.716115 s`, `labos.orders.local_up` worsened from `0.621791 s` to `0.720501 s`, and total orders moved from `2.447930 s` to `2.673397 s`. LLVM's retained generic-loop shape is better here.

## Rejected: Fused Local-Source Dot Pairs

The local down and local up loops each compute a sum of two paired Gauss-row dot products:

```text
local_d = R * previous_up + T * previous_down
local_u = R * previous_down + T * previous_up
```

A probe fused those two adjacent `dotGaussPair` calls into one helper so one loop body loaded both matrix rows and all four vectors. The arithmetic result was unchanged, but the larger helper hurt the actual orders section. The full trace moved `labos.orders.local_down` from the retained `0.642073 s` artifact sample to `0.693607 s`, `labos.orders.local_up` from `0.616417 s` to `0.686717 s`, and total orders from `2.359611 s` to `2.496766 s`. The separate `dotGaussPair` calls stay.

## Rejected: Source-Level Load Hoisting

Moving the fixed right-hand matrix slices outside the unrolled source loops did not change the static instruction mix and did not produce a reliable timing win. LLVM was already finding the same code shape for the retained 12x10 kernels.

## Rejected: Fused Q-Series/D Update

The fused q-series/D update was tested as a direct computation of:

```text
D = T + Q * (diag(E) + T)
```

That shorthand is not the exact current data contract: `Q*T` only sums over the Gauss block, while `Q*diag(E)` scales every output column. A contract-preserving fused prototype matched the standalone checksum, but it was slower in the temporary harness (`601.529 ns/call` current chain, `612.661 ns/call` fused), so it was rejected.

## Rejected: Looped 12x10 Product Shape

A less-unrolled 12x10 product reduced static code in the standalone harness, but the production kernel bench rejected it in the actual `labos.smul` call shape: `smul_12x10` worsened from about `159 ns/call` to about `173 ns/call`, and `qseries_nonzero_12x10` also worsened. The retained fully unrolled product stays in place.

## Rejected: Known-Nonzero Doubling Products

A temporary trace probe measured whether the three hot post-D products could skip the `smul` threshold guard. They cannot: the retained scene skipped `4,781,593` of `8,389,666` `R*D` products, `4,866,527` of `8,389,666` `T*U` products, and `4,589,382` of `8,389,666` `T*D` products. A known-nonzero path would compute millions of products the current scientific threshold intentionally drops.

## Rejected: Fixed Zero Helper For Inactive Orders Layers

Inactive orders layers zero two 12-stream vectors millions of times, so a fixed-width zero helper looked plausible. The temporary trace did not retain: local-down time moved slightly, but total orders worsened from `2.447930 s` to `2.453527 s`, and accumulation worsened from `0.130923 s` to `0.135680 s`. The explicit zero loops stay in place.

## Rejected: Fixed Convergence Tail Max

For the retained geometry, each scattering-order convergence check only scans the two non-Gauss streams for two columns. An inline fixed-shape helper removed the runtime nested loop, but the full trace worsened: `labos.orders.total` moved from `2.447930 s` to `2.495604 s`, with local-down and transport both worse. The generic loop remains.

## Rejected: Row-Major `semul12`

After zero-aware product updates, `semul_12` became visible in the retained primitive estimate for the skipped `R*D` path. A row-major rewrite made the matrix access contiguous, but it reloaded the column attenuation factor inside the inner loop and did not retain. The temporary full trace worsened `forward_wall_s` from `1.867171916` to `1.897892042`, `labos.rt_layer.doubling` from `5.626077 s` to `5.659333 s`, and `labos_execute_cpu_s` from `10.650208 s` to `10.734714 s`. The original column-major helper stays in place.

## Rejected: No-Pivot Fixed Q-Series Solve

The fixed `12x10` q-series solve was also tested without partial pivot search. The isolated q-series bench improved strongly (`qseries_nonzero_12x10` around `511 ns/call` retained to `466-475 ns/call` in probes), and two temporary traces improved `labos.rt_layer.doubling` to `5.596446 s` and `5.587692 s`. It was still rejected because the tracked run did not clearly improve wall or aggregate LABOS CPU (`forward_wall_s = 1.889574417`, `labos_execute_cpu_s = 10.655715`) and because dropping pivoting weakens the solve's numerical safety margin for future scenes. The pivoted fixed helper stays in place.

## Rejected: Dynamic Attenuation Indexing In Initial Source Fill

The same direct-index idea was tested on the initial `E` source fill. It did not retain: compared with the DynamicAtten transport-only probe, total orders worsened from `2.406741 s` to `2.455252 s`, and initial sources moved from `0.140579 s` to `0.143467 s`. The generic source-fill loop stays in place.

## Rejected: Precomputed Reciprocal For Initial Exponentials

The initial layer attenuation fill computes `exp(-b_start / max(mu, 1.0e-12))` for each active stream before doubling begins. A divide-removal probe stored `1 / max(mu, 1.0e-12)` in `Geometry` and changed the fill to `exp(-b_start * inv_mu)`.

This changed only the arithmetic ordering of the exponent argument and kept the mean reflectance unchanged, but the full-trace evidence was mixed and did not improve the relevant aggregate sections. Two probe traces produced `labos.rt_layer.initial_exponential = 0.069254 s` and `0.073252 s`, but aggregate `labos_execute_cpu_s` was `9.806776` and `9.864134`, and `rt_layer_build_cpu_s` was `6.764248` and `6.793234`. The retained path keeps the direct divide because the section is small and the reciprocal field did not give a reliable full-trace win.

## Rejected: Fixed-12 Initial Exponential Fill

A smaller initial-exponential probe kept the exact `exp(-b_start / max(mu, 1.0e-12))` expression and only changed the loop shape to a fixed 12-stream `inline for` helper. This avoided changing the exponent argument or adding a reciprocal field.

The fast gate passed and mean reflectance stayed unchanged, but the full trace rejected the code shape. `labos.rt_layer.initial_exponential` was essentially unchanged at `0.074454 s`, while aggregate `labos_execute_cpu_s` worsened to `9.792658` and `rt_layer_build_cpu_s` worsened to `6.820353`. The compact runtime loop stays.

## Rejected: Symmetric Zplus Triangle Fill

`Zplus` is a symmetric outer product, so a triangular fill can reduce multiplications by computing one half and mirroring it. The full trace rejected that code shape: `labos.rt_layer.phase_matrix` worsened from `1.065962 s` to `1.512848 s`, and total RT-layer construction worsened from `7.868855 s` to `8.133676 s`. The retained rectangular fixed-12 phase fill stays in place because LLVM handles it better.

## Rejected: Scalarized Phase-Fill Columns

The retained fixed-12 phase fill stores the twelve `alpha * plus[j]` column values in a small stack array and reuses them across all rows. A probe replaced that array with twelve scalar constants and a comptime `switch` at each column, aiming to keep the column factors in registers and remove stack traffic.

The deterministic result was unchanged, but the full trace rejected the code shape. One run looked better at the aggregate level, but the repeat moved `labos.rt_layer.phase_matrix` to `1.053523 s`, `rt_layer_build_cpu_s` to `6.889389`, and `labos_execute_cpu_s` to `9.985604`. The isolated `phase_fill_12x16` benchmark also stayed in the retained band rather than proving a win. The compact column array stays.

## Rejected: Returning D With Its Trace

After retaining the known-right-trace D update, another probe accumulated the Gauss trace of `D` while writing the `D` matrix and returned both values together. That removed a separate 10-element trace scan after nonzero q-series updates, but the extra conditional accumulation inside the 12x12 write loop hurt the real code shape. The temporary trace printed `forward_s=1.942343`, worse than the accepted known-right-trace path, so the separate `gaussTrace(D)` scan stays.

## Rejected: Returning U With Its Trace

The doubling loop builds `U = R*diag(E) + R*D` or `U = R*diag(E)`, then immediately scans the Gauss diagonal of `U` to gate the following `T*U` product. A probe returned the `U` matrix and its Gauss trace from trace-aware `semulAdd`/`semul` helpers, removing that separate `gaussTrace(U)` scan.

The arithmetic result was unchanged, but the trace accumulation inside the 12x12 write helpers worsened the real CPU sections. Against the retained regenerated artifact, `labos_execute_cpu_s` moved from `9.590697` to `9.693628`, `labos.rt_layer.doubling` from `4.660178 s` to `4.694371 s`, and `labos.orders.total` from `2.320164 s` to `2.369228 s`. The same probe's wall time was lower (`1.760656792 -> 1.746089084 s`), but that contradicted the targeted worker CPU sections and was treated as wall-clock noise. The separate `gaussTrace(U)` scan stays.

## Next Candidate

The remaining assembly-level candidates are narrower: target the scattering-order local up/down dot-pair call volume with a real full-trace win, or find a valid reuse boundary that reduces repeated 12x10 products without bypassing threshold skips. More local instruction substitutions are unlikely to produce an order-of-magnitude gain on this exact recurrence.
