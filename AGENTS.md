# Repo Notes

- `zdisamar` is an O2 A forward-model lab. Treat DISAMAR as the bundled reference family used for parity checks, not as the codebase architecture.
- `vendor/disamar-fortran/` is a local, gitignored reference clone. Use it for source comparison, but do not build new features around its global-state or file-driven structure.
- `docs/specs/` and `docs/workpackages/` are local scratch spaces and stay gitignored.
- Keep `src/kernels` free of file I/O, text parsing, CLI wiring, and global mutable state.
- Keep the public surface small and literal around `Case -> Data -> Optics -> Spectrum -> Report`.
- Do not reintroduce engine/planner/plugin/ABI scaffolding or string-keyed mutation APIs.
- No parsed control may be silently ignored. Every new config/input field must be consumed, rejected with a typed error, or explicitly documented as inert with a covering test.
- Do not silently drop enabled physics on unmatched identifiers, interval placements, or unsupported combinations. Fail fast when a nonzero or enabled control cannot be applied.
- Preserve retained O2 A semantics unless the change is an intentional compatibility break called out in the work package, PR summary, and focused regression coverage.

## Router

- Start in [src/AGENTS.md](src/AGENTS.md) for source-tree work.
- Use [tests/AGENTS.md](tests/AGENTS.md) and [validation/AGENTS.md](validation/AGENTS.md) for verification work.
- Use [scripts/AGENTS.md](scripts/AGENTS.md) for repo automation and testing-harness helper scripts.
- Use [vendor/AGENTS.md](vendor/AGENTS.md) before touching any vendored reference assets.
- Deep repo context lives in [.agents/repo-context/index.md](.agents/repo-context/index.md).

## Testing Harness

- The verification harness is layered; keep the current suite split and validation assets as the base layer instead of replacing them with one monolithic runner.
- `zig build` is the front door for local verification. Prefer adding or changing build steps before adding ad hoc shell commands.
- Python helper scripts in this repo are invoked with `uv run ...`, not `python3 ...`.
- When the user asks to "update O2A plots", run `zig build o2a-plot-bundle` and stage the changed tracked files under `validation/`.
- The default O2A plot refresh uses the committed vendor reference in `validation/o2a_with_cia_disamar_reference.csv` and does not rerun vendored DISAMAR.
- `zig build check` is the fast baseline: format check, compile the shipped O2A artifacts and suite roots, then run the root smoke tests.
- `zig build test-fast` is the broader presubmit lane for the retained O2A fast suites.
- `./scripts/clean-zig-caches.sh` removes accumulated repo-local Zig caches (`.zig-cache`, `.zig-cache-int`, and `zig-cache/`) after a run has finished.
- `./scripts/zig-build-ephemeral.sh ...` runs `zig build` with temporary local and global caches and deletes them on exit; use it for low-disk or one-shot verification, but keep plain `zig build ...` as the default front door.
- Keep heavier lanes like vendor differential runs and plot-bundle refreshes out of the default local loop unless the changed surface needs them.
- Aggregate build steps must have explicit coverage for composition. When a new focused lane or proof is added, tests or harness checks should prove that aggregate steps include it when required and omit it when intentionally opt-in.
- When a change adds both exact and alternate O2 A paths, add the smallest focused verification that proves intended semantic parity or intentional divergence across those paths.

## Current O2 A Radiance Residual Notes

- As of the 756.77 nm focused diff, the remaining radiance residual is carried by support sample 121 at 756.7749788772569 nm, with the top weighted radiance contribution delta about 4.408 and final focused radiance delta about 4.422.
- Upstream optics, support irradiance, and reflectance are not the active issue. Irradiance residuals are a few ULPs at very large scale and have been confirmed as summation noise.
- LABOS order recursion is an amplifier, not the seed. The fixed probe at Fourier 0, layer 14, row angle 4, solar column shows `Tsingle` already differs before doubling. Doubling grows that seed to `RT.T`/`UD.D` deltas around 1.9e-11.
- Already tested with no net improvement: Fortran-style whole-RHS assignment ordering in `double`; Fortran-style `Qseries` LU/solve ordering; strict float mode in matrix helpers; strict float mode in phase-basis and `Zplus` summation; layer optical-depth regrouping as `babs + bsca`; DISAMAR-style row-level grouping of support-row `babs`/`bsca` accumulation.
- The initial large `transport_layer_accumulation.csv` gas/scattering discrepancy was a trace alignment artifact caused by stale vendor `active_wavelength_nm`. Passing the actual `propAtmosphere` wavelength into the trace makes vendor accumulation equal vendor `transport_layers.csv`, and Zig matches DISAMAR layer `babs`/`bsca` to about 1e-15.
- The support-row summand check for sample 121, layer 14 shows global support rows 56-59 account for the full layer optical-depth delta. Their per-row extinction (`optical_depth / support_weight_km`) deltas partially cancel, while `support_weight_km` path-length deltas dominate the positive cumulative layer delta. Switching the parity vertical grid to the repo's DISAMAR `[0,1]` Gauss rule did not improve radiance and was backed out; the active seed is vertical-grid path-length/span ULP noise, not the Gauss-rule family.
- A narrower mirror of DISAMAR's RTM level-boundary construction, using DISAMAR-compatible `[0,1]` Gauss division points only for interval interior RTM boundaries while leaving sublayer support nodes unchanged, gives a small net improvement. The 756.77 focused residual moved from 4.421875 to 4.41796875, and the full plot bundle radiance max_abs moved from 4.42578125 to 4.421875. It does not eliminate the sample-121/layer-14 `b_start` seed.
- `transport_zplus_terms.csv` shows per-coefficient `Zplus` terms are not the main seed. For the dominant sample, pre-renormalization cumulative `Zplus` is effectively aligned; post-renorm `Zplus` differs only at a few ULPs.
- The strongest current seed is the near-canceling `Tsingle` factor `eet = E(row) - E(col)`: the row attenuation differs by one ULP while the column attenuation matches. This appears to originate in layer optical-depth / `b_start` roundoff and is then amplified by doubling.
- Next useful inquiry: if exact bit parity is still required, continue mirroring DISAMAR's vertical-grid altitude/span arithmetic at the temporary-expression level. Otherwise treat the remaining radiance residual as amplified floating-point path-length noise. Do not repeat the eliminated LABOS `double`, `Qseries`, `Zplus`, `babs`/`bsca` grouping, or full sublayer-support Gauss-rule-family diagnostics unless new evidence changes the hotspot.

## Before Push

- There is no repo CI workflow. Run the necessary checks locally before pushing larger changes.
- Minimum baseline: `zig build check`.
- If you touched runtime behavior, optics preparation, spectrum assembly, report generation, or validation fixtures, also run the relevant focused lanes such as `zig build test-fast`, `zig build test-transport`, `zig build test-validation-o2a`, `zig build test-validation-o2a-vendor`, `zig build o2a-forward-profile`, and `zig build o2a-plot-bundle` when warranted.
- Do not blindly run every retained scientific lane for every push. Pick the smallest set of lanes that actually covers the changed surface area.
- If you changed control propagation, interval ordering, placement semantics, or wavelength-dependent behavior, include at least one focused test that would fail if a stale fallback or reference-only path were still being used.

## Commands

- `zig build check` is the fast local verification command.
- `zig build test-fast` is the fast presubmit verification command.
- `zig build o2a-plot-bundle` regenerates the tracked O2A comparison bundle under `validation/`.
- The tracked O2 A validation bundle uses the committed vendor reference at `validation/o2a_with_cia_disamar_reference.csv`.
- `zig build test-transport` is the focused transport/parity verification command.
- `zig build test-validation-o2a` runs the retained O2A forward-shape validation lane.
- `zig build test-validation-o2a-vendor` runs the opt-in O2A vendor trend assessment lane.
- `zig build test-validation-o2a-vendor-profile` runs the profiled/unprofiled O2A report smoke lane.
- `zig build test-validation-o2a-vendor-line-list` runs the O2A vendor line-list helper smoke lane.
- `zig build test-validation-o2a-plot-bundle` runs the O2A plot bundle harness smoke test.
- `zig build test` is the full verification command.
- `zig build` builds the O2A library and the O2A forward-profile CLI.
- `./scripts/clean-zig-caches.sh` removes repo-local Zig caches after a run.
- `./scripts/zig-build-ephemeral.sh ...` is the zero-persistence wrapper when cache reuse is less important than disk pressure.
