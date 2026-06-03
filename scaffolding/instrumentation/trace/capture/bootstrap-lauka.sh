#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
lock_path="$script_dir/lauka.lock"

# shellcheck source=/dev/null
source "$lock_path"

: "${LAUKA_REPO:?missing LAUKA_REPO in $lock_path}"
: "${LAUKA_REF:?missing LAUKA_REF in $lock_path}"
: "${LAUKA_ZIG_VERSION:?missing LAUKA_ZIG_VERSION in $lock_path}"

if [[ "$(zig version)" != "$LAUKA_ZIG_VERSION" ]]; then
  echo "expected Zig $LAUKA_ZIG_VERSION for pinned Lauka; found $(zig version)" >&2
  exit 2
fi

safe_ref="${LAUKA_REF//\//_}"
repo_key="$(printf '%s' "$LAUKA_REPO" | shasum -a 256 | awk '{print substr($1, 1, 12)}')"
tool_dir="$repo_root/out/tools/lauka/${repo_key}-${safe_ref}"
lauka_bin="$tool_dir/zig-out/bin/lauka"

if [[ ! -d "$tool_dir/.git" ]]; then
  mkdir -p "$(dirname "$tool_dir")"
  tmp_dir="$(mktemp -d "$repo_root/out/tools/lauka/.tmp.XXXXXX")"
  cleanup() {
    rm -rf "$tmp_dir"
  }
  trap cleanup EXIT

  git clone "$LAUKA_REPO" "$tmp_dir" >&2
  git -C "$tmp_dir" checkout --detach "$LAUKA_REF" >&2
  mv "$tmp_dir" "$tool_dir"
  trap - EXIT
fi

if ! grep -q 'target_pid = child.id' "$tool_dir/src/record.zig" ||
   ! grep -q 'kill -STOP' "$tool_dir/src/record.zig"; then
  echo "pinned Lauka checkout does not contain the child-pid PMU filter fix" >&2
  echo "check $lock_path" >&2
  exit 2
fi

(
  cd "$tool_dir"
  zig build -Doptimize=ReleaseFast
) >&2

if [[ ! -x "$lauka_bin" ]]; then
  echo "expected Lauka binary not produced: $lauka_bin" >&2
  exit 1
fi

printf '%s\n' "$lauka_bin"
