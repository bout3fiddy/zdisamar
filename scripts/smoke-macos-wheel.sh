#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wheel_dir="$(mktemp -d /tmp/zdisamar-macos-wheel.XXXXXX)"
venv_dir="$(mktemp -d /tmp/zdisamar-wheel-smoke.XXXXXX)"

cleanup() {
    rm -rf "${wheel_dir}" "${venv_dir}"
}
trap cleanup EXIT

"${repo_root}/scripts/build-wheel.sh" "${wheel_dir}"
wheel_path="$(find "${wheel_dir}" -maxdepth 1 -name 'zdisamar-*.whl' -print -quit)"

if [[ -z "${wheel_path}" ]]; then
    echo "no zdisamar wheel was built" >&2
    exit 1
fi

uv venv --python 3.14 "${venv_dir}/venv"
uv pip install --python "${venv_dir}/venv/bin/python" "${wheel_path}"

cd /tmp
"${venv_dir}/venv/bin/python" "${repo_root}/tests/python/wheel_install_smoke_test.py" \
    --forbid-path "${repo_root}"
