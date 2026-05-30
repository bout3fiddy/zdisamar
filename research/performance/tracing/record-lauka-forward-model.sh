#!/usr/bin/env bash
set -euo pipefail

# Record Apple Silicon PMU counters around the O2 A LABOS forward model.
# The run shape is intentionally fixed: one serial pass for clean per-kernel
# ratios and one threaded pass for the real forward workload.

serial_runs=3
threaded_runs=7
warmup=1
measurements="fixed_cycles,fixed_instructions,arm_l1d_cache_refill,arm_l1d_cache,arm_br_mis_pred,arm_br_pred"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
out_dir="$repo_root/research/performance/tracing/output/lauka-forward"
serial_run_dir="$out_dir/serial-run"
threaded_run_dir="$out_dir/threaded-run"
serial_report="$out_dir/lauka-serial.txt"
threaded_report="$out_dir/lauka-threaded.txt"
summary_json="$out_dir/pmu-summary.json"

lauka_bin="$("$script_dir/bootstrap-lauka.sh")"

mkdir -p "$serial_run_dir" "$threaded_run_dir"
rm -f "$serial_report" "$threaded_report" "$summary_json"

(
  cd "$repo_root"
  zig build labos-bottleneck-trace-bin -Doptimize=ReleaseFast
)
forward_exe="$repo_root/zig-out/bin/labos-bottleneck-trace"
if [[ ! -x "$forward_exe" ]]; then
  echo "expected executable not found: $forward_exe" >&2
  exit 1
fi

# Lauka treats each token after `--` as a separate benchmark command, so each
# measured child command is passed as one string.
serial_command="env ZDISAMAR_WORKER_LIMIT=1 $forward_exe --output-dir $serial_run_dir"
threaded_command="$forward_exe --output-dir $threaded_run_dir"

echo "[1/2] serial PMU pass: ZDISAMAR_WORKER_LIMIT=1"
sudo "$lauka_bin" record --color never --runs "$serial_runs" --warmup "$warmup" \
  --measurements "$measurements" \
  -- "$serial_command" | tee "$serial_report"

echo
echo "[2/2] threaded PMU pass: default worker count"
sudo "$lauka_bin" record --color never --runs "$threaded_runs" --warmup "$warmup" \
  --measurements "$measurements" \
  -- "$threaded_command" | tee "$threaded_report"

python3 - "$summary_json" "$serial_report" "$threaded_report" \
  "$serial_run_dir/summary.json" "$threaded_run_dir/summary.json" \
  "$serial_runs" "$threaded_runs" "$warmup" "$measurements" <<'PY'
import json
import re
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
serial_report = Path(sys.argv[2])
threaded_report = Path(sys.argv[3])
serial_forward_summary = Path(sys.argv[4])
threaded_forward_summary = Path(sys.argv[5])
serial_runs = int(sys.argv[6])
threaded_runs = int(sys.argv[7])
warmup = int(sys.argv[8])
measurements = sys.argv[9]

SCALE = {
    "": 1.0,
    "K": 1.0e3,
    "M": 1.0e6,
    "G": 1.0e9,
    "T": 1.0e12,
    "s": 1.0,
    "ms": 1.0e-3,
    "us": 1.0e-6,
    "ns": 1.0e-9,
    "KB": 1.0e3,
    "MB": 1.0e6,
    "GB": 1.0e9,
}


def parse_lauka_report(path: Path) -> dict[str, float]:
    values: dict[str, float] = {}
    pattern = re.compile(
        r"^\s*(wall_time|peak_rss|fixed_cycles|fixed_instructions|"
        r"arm_l1d_cache_refill|arm_l1d_cache|arm_br_mis_pred|arm_br_pred)"
        r"\s+([0-9.]+)([A-Za-z]*)\b"
    )
    for line in path.read_text().splitlines():
        match = pattern.match(line)
        if not match:
            continue
        name, number, unit = match.groups()
        values[name] = float(number) * SCALE[unit]
    return values


def load_forward_summary(path: Path) -> dict[str, object]:
    with path.open() as handle:
        return json.load(handle)


def derived(values: dict[str, float]) -> dict[str, float]:
    cycles = values["fixed_cycles"]
    instructions = values["fixed_instructions"]
    l1d = values["arm_l1d_cache"]
    l1d_refill = values["arm_l1d_cache_refill"]
    branch_pred = values["arm_br_pred"]
    branch_miss = values["arm_br_mis_pred"]
    return {
        "ipc": instructions / cycles,
        "l1d_miss_rate": l1d_refill / l1d,
        "l1d_mpki": 1000.0 * l1d_refill / instructions,
        "branch_mispredict_rate": branch_miss / branch_pred,
        "branch_mpki": 1000.0 * branch_miss / instructions,
    }


serial = parse_lauka_report(serial_report)
threaded = parse_lauka_report(threaded_report)
serial_forward = load_forward_summary(serial_forward_summary)
threaded_forward = load_forward_summary(threaded_forward_summary)

serial_instructions = serial["fixed_instructions"]
threaded_instructions = threaded["fixed_instructions"]
scope_ratio = threaded_instructions / serial_instructions
scope_ok = serial_instructions >= 1.0e9 and scope_ratio >= 0.5

summary = {
    "schema": 1,
    "tool": "lauka",
    "boundary": "o2a_forward_model",
    "build": "zig build labos-bottleneck-trace-bin -Doptimize=ReleaseFast",
    "measurements": measurements.split(","),
    "warmup": warmup,
    "serial": {
        "runs": serial_runs,
        "command": "env ZDISAMAR_WORKER_LIMIT=1 labos-bottleneck-trace",
        "forward_summary": str(serial_forward_summary),
        "forward_wall_s": serial_forward["forward_wall_s"],
        "counters": serial,
        "derived": derived(serial),
    },
    "threaded": {
        "runs": threaded_runs,
        "command": "labos-bottleneck-trace",
        "forward_summary": str(threaded_forward_summary),
        "forward_wall_s": threaded_forward["forward_wall_s"],
        "counters": threaded,
        "derived": derived(threaded),
    },
    "scope_check": {
        "serial_instruction_floor": 1.0e9,
        "threaded_to_serial_instruction_ratio": scope_ratio,
        "ok": scope_ok,
    },
}

summary_path.parent.mkdir(parents=True, exist_ok=True)
summary_path.write_text(json.dumps(summary, indent=2) + "\n")

print()
print("================ O2 A forward PMU: serial vs threaded ================")
print(f"{'metric':24s} {'serial (1 worker)':>18s} {'threaded':>18s}")
print(f"{'forward_wall_s':24s} {serial_forward['forward_wall_s']:18.3f} {threaded_forward['forward_wall_s']:18.3f}")
print(f"{'fixed_cycles':24s} {serial['fixed_cycles'] / 1e9:17.2f}G {threaded['fixed_cycles'] / 1e9:17.2f}G")
print(f"{'fixed_instructions':24s} {serial_instructions / 1e9:17.2f}G {threaded_instructions / 1e9:17.2f}G")
print(f"{'IPC':24s} {derived(serial)['ipc']:18.3f} {derived(threaded)['ipc']:18.3f}")
print(f"{'L1D miss rate':24s} {100 * derived(serial)['l1d_miss_rate']:17.2f}% {100 * derived(threaded)['l1d_miss_rate']:17.2f}%")
print(f"{'L1D MPKI':24s} {derived(serial)['l1d_mpki']:18.2f} {derived(threaded)['l1d_mpki']:18.2f}")
print(f"{'branch miss rate':24s} {100 * derived(serial)['branch_mispredict_rate']:17.2f}% {100 * derived(threaded)['branch_mispredict_rate']:17.2f}%")
print(f"{'branch MPKI':24s} {derived(serial)['branch_mpki']:18.2f} {derived(threaded)['branch_mpki']:18.2f}")
print("=====================================================================")
print(f"wrote compact PMU summary to {summary_path}")

if not scope_ok:
    print("PMU scope check failed: Lauka did not capture the workload process/thread set.", file=sys.stderr)
    sys.exit(1)
PY
