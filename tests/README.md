# Test Suite Layout

The `tests/` tree contains executable checks that run quickly in CI and local
development.

- `tests/unit/`: lifecycle and contract-level checks with tight scope.
- `tests/integration/`: end-to-end API flow checks through the scaffold runtime.
- `tests/golden/`: assertions against golden fixtures in `validation/golden/`.
- `tests/perf/`: repeatable performance smoke checks with bounded loops.
- `tests/validation/`: schema and evidence-asset integrity checks for validation data.

Use `zig build check` for the fast local loop.
Use `zig build test-fast` for the fast presubmit lane.
Use `zig build bench` for the non-gating benchmark summary lane.
Use `zig build tidy` for architecture and policy checks.
Python-backed harness helpers are run through `uv run ...` behind the build steps; do not add `python3 ...` wrappers.
Use `zig build test-transport` for the focused transport/parity loop, including the operational measured-input compatibility classification proof.
Use `zig build test-validation-compatibility` for fast compatibility smoke checks.
Use `zig build test-validation-o2a-vendor` only for the opt-in O2A vendor trend assessment lane.
Use `zig build test-validation-o2a-plot-bundle` for the tracked O2A plot-bundle harness smoke test.
Use `zig build o2a-forward-profile-bin` to install the O2A forward profiling binary.
Use `zig build o2a-forward-profile` to emit `out/analysis/o2a/profile/summary.json`.
Use `zig build o2a-plot-bundle` to regenerate the tracked O2A comparison bundle under `validation/compatibility/o2a_plots/`.
Use `zig build o2a-vendor-reference-refresh` only when you explicitly want to rerun vendored DISAMAR and refresh `validation/reference/o2a_with_cia_disamar_reference.csv`.

Run all suites with `zig build test`, or targeted suites with:

- `zig build fmt-check`
- `zig build test-unit`
- `zig build test-integration`
- `zig build test-integration-forward-model`
- `zig build test-golden`
- `zig build test-perf`
- `zig build test-validation`
- `zig build test-validation-compatibility`
- `zig build test-validation-compatibility-transport-measurement`
- `zig build test-validation-compatibility-retrieval`
- `zig build test-validation-compatibility-optics`
- `zig build test-validation-compatibility-rtm-controls`
- `zig build test-validation-compatibility-asciihdf`
- `zig build test-validation-compatibility-operational-measured-input`
- `zig build test-validation-compatibility-full`
- `zig build test-validation-o2a`
- `zig build test-validation-o2a-vendor`
- `zig build test-validation-o2a-plot-bundle`

## O2A Profiling

The O2A speed workflow is opt-in and stays outside the default local lanes.

- Build the profiling binary: `zig build o2a-forward-profile-bin -Doptimize=ReleaseFast`
- Run the coarse timing report: `zig build o2a-forward-profile -Doptimize=ReleaseFast`
- Installed binary path: `zig-out/bin/zdisamar-o2a-forward-profile`
- Summary artifact: `out/analysis/o2a/profile/summary.json`
- Optional generated spectrum: `out/analysis/o2a/profile/generated_spectrum.csv` when `--write-spectrum` is used

## Tracked O2A Plot Bundle

- Canonical regeneration command: `zig build o2a-plot-bundle`
- Tracked output directory: `validation/compatibility/o2a_plots/`
- Default vendor input: `validation/reference/o2a_with_cia_disamar_reference.csv`
- Default refresh policy: use the committed vendor reference and do not rerun vendored DISAMAR

On macOS, capture a flame graph with Time Profiler against the installed binary.
This requires full Xcode, not just Command Line Tools. If `xctrace` reports that
the active developer directory is a Command Line Tools instance, switch to Xcode
first with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

```bash
xctrace record \
  --template 'Time Profiler' \
  --output out/analysis/o2a/profile/o2a-forward.trace \
  --launch -- \
  ./zig-out/bin/zdisamar-o2a-forward-profile \
  --output-dir out/analysis/o2a/profile
```

Keep raw `.trace` bundles under `out/analysis/o2a/profile/`.
