#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  research/performance/tracing/record-lauka-forward-model.sh [options]

Options:
  --runs N             Measured Lauka runs. Default: 7.
  --warmup N           Lauka warmup runs before measurement. Default: 1.
  --measurements LIST  Comma-separated Lauka counters.
  --output-dir DIR     Output directory. Default: research/performance/tracing/output/lauka-forward.
  --no-sudo            Run Lauka without sudo.
  -h, --help           Show this help.

The measured child command is the ReleaseFast O2 A LABOS forward-model harness
built without ztracy. That keeps the PMU counters focused on the forward path,
not Tracy instrumentation or the optimal-estimation retrieval loop. The default
measurements use supported Apple/ARM counters:
fixed_cycles,fixed_instructions,arm_l1d_cache_refill,arm_l1d_cache,
arm_br_mis_pred,arm_br_pred.
USAGE
}

quote_command() {
  local quoted=()
  local arg
  for arg in "$@"; do
    quoted+=("$(printf '%q' "$arg")")
  done
  printf '%s' "${quoted[*]}"
}

json_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "$value"
}

require_positive_int() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "$name must be a positive integer" >&2
      exit 2
      ;;
    0)
      echo "$name must be greater than zero" >&2
      exit 2
      ;;
  esac
}

default_measurements="fixed_cycles,fixed_instructions,arm_l1d_cache_refill,arm_l1d_cache,arm_br_mis_pred,arm_br_pred"

runs="${RUNS:-7}"
warmup="${WARMUP:-1}"
measurements="${MEASUREMENTS:-$default_measurements}"
output_dir=""
use_sudo=1

while (($#)); do
  case "$1" in
    --runs)
      if (($# < 2)); then
        echo "missing value for --runs" >&2
        exit 2
      fi
      runs="$2"
      shift 2
      ;;
    --warmup)
      if (($# < 2)); then
        echo "missing value for --warmup" >&2
        exit 2
      fi
      warmup="$2"
      shift 2
      ;;
    --measurements)
      if (($# < 2)); then
        echo "missing value for --measurements" >&2
        exit 2
      fi
      measurements="$2"
      shift 2
      ;;
    --output-dir)
      if (($# < 2)); then
        echo "missing value for --output-dir" >&2
        exit 2
      fi
      output_dir="$2"
      shift 2
      ;;
    --no-sudo)
      use_sudo=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unsupported argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_positive_int "--runs" "$runs"
case "$warmup" in
  ''|*[!0-9]*)
    echo "--warmup must be a non-negative integer" >&2
    exit 2
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
if [[ -z "$output_dir" ]]; then
  output_dir="$repo_root/research/performance/tracing/output/lauka-forward"
elif [[ "$output_dir" != /* ]]; then
  output_dir="$repo_root/$output_dir"
fi

lauka_bin="${LAUKA:-lauka}"
if ! lauka_path="$(command -v "$lauka_bin")"; then
  echo "lauka is not on PATH. Build/install https://github.com/verte-zerg/lauka or set LAUKA=/path/to/lauka." >&2
  exit 127
fi

if ((use_sudo)) && ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required by Lauka for Apple Silicon PMU counters. Pass --no-sudo only if your Lauka setup does not need it." >&2
  exit 127
fi

mkdir -p "$output_dir"
forward_output_dir="$output_dir/forward-run"
mkdir -p "$forward_output_dir"

report_path="$output_dir/lauka-forward.txt"
manifest_path="$output_dir/manifest.json"
command_path="$output_dir/command.txt"
rm -f "$report_path" "$manifest_path" "$command_path"

(
  cd "$repo_root"
  zig build labos-bottleneck-trace-bin -Dtrace-optimize=ReleaseFast
)

forward_exe="$repo_root/zig-out/bin/labos-bottleneck-trace"
if [[ ! -x "$forward_exe" ]]; then
  echo "expected executable not found: $forward_exe" >&2
  exit 1
fi

child_args=("$forward_exe" --output-dir "$forward_output_dir")
child_command="$(quote_command "${child_args[@]}")"
printf '%s\n' "$child_command" >"$command_path"

cat >"$manifest_path" <<JSON
{
  "tool": "lauka",
  "target": "o2a_forward_model",
  "runs": $runs,
  "warmup": $warmup,
  "measurements": $(json_string "$measurements"),
  "command": $(json_string "$child_command"),
  "report": $(json_string "$report_path"),
  "forward_summary": $(json_string "$forward_output_dir/summary.json")
}
JSON

echo "recording forward-model PMU counters to $report_path"
echo "child command: $child_command"

lauka_args=(
  record
  --color never
  --runs "$runs"
  --warmup "$warmup"
  --measurements "$measurements"
  --
  "${child_args[@]}"
)

if ((use_sudo)); then
  sudo "$lauka_path" "${lauka_args[@]}" | tee "$report_path"
else
  "$lauka_path" "${lauka_args[@]}" | tee "$report_path"
fi

if [[ -f "$forward_output_dir/summary.json" ]]; then
  echo
  echo "forward summary"
  awk -F ': ' '
    /"trace_enabled"/ { trace_enabled = $2 }
    /"prepare_s"/ { prepare = $2 }
    /"forward_wall_s"/ { forward = $2 }
    END {
      gsub(/[, ]/, "", trace_enabled)
      gsub(/[, ]/, "", prepare)
      gsub(/[, ]/, "", forward)
      printf "  trace_enabled:          %s\n", trace_enabled
      printf "  prepare_s:              %s\n", prepare
      printf "  forward_wall_s:         %s\n", forward
    }
  ' "$forward_output_dir/summary.json"
fi
