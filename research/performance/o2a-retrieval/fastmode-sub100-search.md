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

- Fresh worktree: `/Users/swadhinnanda/Projects/git/zdisamar-fastmode-sub100`
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
