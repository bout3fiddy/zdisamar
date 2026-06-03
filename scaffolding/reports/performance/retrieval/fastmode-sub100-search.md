# Fastmode Sub-100 ms Search

Goal: find fastmode control settings that bring O2 A optimal-estimation
retrieval below 0.1 s on a 10-worker CPU cap without increasing the retained
fastmode accuracy loss against fullmode.

Boundary:

- Public Python `o2a_oe.retrieve(...)` call with `case.optimisation.fastmode.enabled = True`.
- `ZDISAMAR_WORKER_LIMIT=10`.
- Timing includes native sparse fast-stage prepare/load, fast-stage OE,
  sparse full-physics correction when enabled, and Python result copying.
- Timing excludes scene construction, measurement construction, plotting, and
  lazy final full-band evaluation.

Accuracy contract:

- Existing retained fastmode summary:
  - median fastmode retrieval: `0.5384249375201762 s`
  - max absolute AOD delta vs fullmode: `5.284810296529996e-4`
  - max absolute aerosol mid-pressure delta vs fullmode: `0.6678536844146379 hPa`
- Candidate defaults cannot exceed those full-sweep deltas, and should also
  keep the retained spectra fastmode residual envelope at or below the existing
  setup.

## 2026-05-27 Setup

- Fresh sibling worktree for the fastmode sub-100 search
- Branch: `codex/fastmode-sub100`
- Base: `66f2b4b56f211e163f241ea4774a928e8406bdf1`
- Scratch harness: `out/fastmode_sub100/search.py`

Baseline canary with the production fast benchmark path and 10-worker cap:

```text
command: uv run python - <<'PY'
import sys
sys.path.insert(0, "benchmark")
import run_benchmark_fast as fast
fast.WORKER_LIMIT = 10
raise SystemExit(fast.main())
PY

worker_cap: 10
oe single fastmode retrieval median: 0.304682 s
oe sweep fastmode retrieval total: 1.113476 s for cases 1 and 3
oe sweep fastmode per-case retrievals: 0.547 s, 0.566 s
forward cached median: 0.096110 s
```

Interpretation: the forward cached path is already near 0.1 s, but fastmode OE
is not. The sub-100 ms target needs to remove whole OE evaluations/correction
work or materially shrink the sparse RTM/Jacobian grids without increasing the
current fastmode error envelope.

## Experiment Notes

Append each run with:

- candidate name and changed knobs;
- case subset;
- median/min/max retrieval time;
- max AOD and pressure deltas vs fullmode;
- convergence count;
- whether it stays inside the existing retained fastmode envelope;
- reason accepted or rejected.

## 2026-05-27 Results

Exploratory subset: retained stress cases `1, 2, 3, 8, 20, 48, 74, 86, 93`
with `ZDISAMAR_WORKER_LIMIT=10`.

Rejected paths:

- `final_correction.enabled = False`: median `0.334 s`, but max deltas grew to
  `8.824e-03` AOD and `5.940 hPa`.
- `max_iterations = 1`, no correction, 8-38 fast wavelengths: median
  `0.170-0.176 s`, still above 0.1 s and with `~2e-2` AOD / `>11 hPa` pressure
  deltas.
- `max_iterations = 2`: median `0.453 s`; full 100-case follow-up with 24 fast
  wavelengths and 4 correction wavelengths had median `0.411 s`, but only
  `23/100` fast stages converged.
- Lower stream counts, spherical/source/renormalization switches, matrix
  threshold, phase truncation, and multiple-scattering order caps either failed
  as unsupported, got slower, or exceeded the retained accuracy envelope.

Accepted partial win:

- `fastmode.oe.final_correction.wavelength_count = 4`
- retained 100-case sweep command:
  `ZDISAMAR_WORKER_LIMIT=10 uv run validation/optimal_estimation/sweep_fast_mode_optimal_estimation.py`
- convergence: `100/100` fastmode and `100/100` fast-stage convergence
- fastmode median/mean retrieval: `0.500 s` / `0.483 s`
- speedup median/mean versus same-run fullmode: `+1.351 s` / `+1.292 s`
- max deltas versus fullmode: `5.165e-04` AOD and `0.609 hPa`

Conclusion: sub-100 ms was not reachable through the tested control knobs while
preserving the current accuracy/convergence contract. Even the deliberately
inaccurate one-iteration, no-correction lower bound stayed around `0.17 s`.

## 2026-05-27 Jacobian-Row Sparsity Search

Question: how many wavelength rows does the two-state Jacobian need in the
fast-stage retrieval and final correction?

Scratch harness:
`out/fastmode_sub100/jacobian_sparse_search.py`.

Method:

- keep the public `o2a_oe.retrieve(...)` fastmode boundary;
- treat the fast-stage and correction wavelength sets as the Jacobian-row
  sparsity knobs;
- compute weighted two-column Jacobian rows on the full measurement grid for
  retained stress cases;
- greedily select rows by a small Fisher-information objective;
- validate each candidate by running real fastmode retrievals against fullmode
  references, not by trusting the information metric.

Stress subset: retained cases `1, 2, 3, 8, 20, 48, 74, 86, 93`.

Previous 38-row default on the same stress run:

- samples: `38` fast-stage rows + `4` final-correction rows
- median retrieval: `0.526919 s`
- max deltas versus fullmode: `5.165e-04` AOD and `0.609 hPa`
- fast-stage convergence: `9/9`

Best stress candidate:

- name: `stress_greedy_fast12_final_default`
- fast-stage wavelengths:
  `758.00, 758.08, 758.20, 758.28, 758.36, 758.48, 765.20, 765.32, 765.44, 765.68, 766.24, 766.84 nm`
- final-correction wavelengths: existing default
  `765.20, 766.12, 767.08, 768.00 nm`
- samples: `12` fast-stage rows + `4` final-correction rows
- median retrieval: `0.428861 s`
- max deltas versus fullmode: `4.182e-04` AOD and `0.374 hPa`
- fast-stage convergence: `9/9`

Interpretation so far: the 38-row fast-stage grid is not the minimum useful
Jacobian-row set. A sensitivity-selected 12-row set preserved the retained
stress-case envelope and reduced the stress median by about `19%`. This is a
real lead.

Other stress observations:

- greedy full-band fast-stage rows were accurate but slower because they widen
  the prepared correction/RTM span;
- two-row final correction was not enough (`~8.8e-03` AOD / `~9.6 hPa` on the
  default fast-stage run);
- three-row and greedy four-row final-correction sets could stay accurate on
  stress cases, but were slower than the existing four-row correction in this
  noisy run, likely because the selected endpoints widened expensive O2 A
  structure rather than just reducing sample count;
- evenly spaced 12-row fast-stage sampling was accurate on stress cases but
  slower than the greedy 12-row set, so row placement matters more than count
  alone.

Retained 100-case follow-up after promoting the 12-row set as the default:

- command:
  `ZDISAMAR_WORKER_LIMIT=10 uv run validation/optimal_estimation/sweep_fast_mode_optimal_estimation.py`
- convergence: `100/100` fastmode and `100/100` fast-stage convergence
- samples: `12` fast-stage rows + `4` final-correction rows
- fastmode median/mean retrieval: `0.420 s` / `0.411 s`
- speedup median/mean versus same-run fullmode: `+1.393 s` / `+1.352 s`
- max deltas versus fullmode: `4.182e-04` AOD and `0.551 hPa`
- spectra gate:
  `uv run validation/spectra/validate_fast_mode_spectra.py` kept the worst
  scene at `4.963e-04`, unchanged in practice because the RTM fastmode
  thresholds did not change.
- retained benchmark:
  `uv run benchmark/run_benchmark.py` reported fastmode sweep retrieval total
  `4.421 s` versus session fullmode sweep retrieval total `15.794 s` at the
  normal two-worker benchmark cap; fastmode sweep median retrieval was
  `0.815 s`.

Conclusion: the fast-stage Jacobian does not need the old 38 rows for the
retained two-state O2 A retrieval.  A 12-row sensitivity-selected set is a
validated default improvement: it is faster and stays inside the existing
retrieval accuracy envelope.
