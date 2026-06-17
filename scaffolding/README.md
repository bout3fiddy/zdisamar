# Scaffolding

`scaffolding/` holds retained construction tooling: instrumentation harnesses,
capture scripts, exploratory kernels, and performance notes. It is not a
contract gate.

First-class gates stay in their own roots:

- `benchmark/`: retained performance truth and the fast production-path canary.
- `validation/`: tracked DISAMAR/zdisamar evidence and validation scripts.
- `tests/`: asserting unit, integration, and validation-lane tests.
- `scripts/`: repo-wide automation, packaging, linting, bootstrap, and smoke helpers.

## Instrumentation

- `instrumentation/trace/zig/` builds trace-enabled harnesses.
- `instrumentation/trace/capture/` holds Tracy and Lauka capture scripts.
- `instrumentation/trace/evidence/` holds intentionally retained compact trace summaries.
- `instrumentation/telemetry/zig/` builds calculation telemetry sinks and CLIs.
- `instrumentation/telemetry/capture/`, `analysis/`, and `schema/` hold the telemetry data pipeline.
- `instrumentation/perturbation/zig/`, `sweep/`, and `analysis/` hold perturbation-sensitivity tooling.

## Experiments

- `experiments/kernels/` holds isolated kernel benchmarks.
- `experiments/primitive-codegen/` holds primitive codegen probes and retained outputs.

## Reports

`reports/performance/` holds performance notes and historical measurements. These
documents can cite benchmark or validation evidence, but they do not replace the
benchmark and validation gates.
