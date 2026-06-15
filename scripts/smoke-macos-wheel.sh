#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wheel_dir="$(mktemp -d /tmp/zdisamar-macos-wheel.XXXXXX)"
venv_dir="$(mktemp -d /tmp/zdisamar-wheel-smoke.XXXXXX)"
test_dir="$(mktemp -d /tmp/zdisamar-wheel-test.XXXXXX)"

cleanup() {
    rm -rf "${wheel_dir}" "${venv_dir}" "${test_dir}"
}
trap cleanup EXIT

"${repo_root}/scripts/build-wheel.sh" "${wheel_dir}"
wheel_path="$(find "${wheel_dir}" -maxdepth 1 -name 'zdisamar-*.whl' -print -quit)"
test_path="${test_dir}/test_wheel_install_smoke.py"
cp "${repo_root}/tests/python/conftest.py" "${test_dir}/conftest.py"
cp "${repo_root}/tests/python/test_wheel_install_smoke.py" "${test_path}"

if [[ -z "${wheel_path}" ]]; then
    echo "no zdisamar wheel was built" >&2
    exit 1
fi

read -r -a python_versions <<< "${ZDISAMAR_SMOKE_PYTHONS:-3.11 3.12 3.13 3.14}"

for python_version in "${python_versions[@]}"; do
    python_path="${venv_dir}/venv-${python_version}/bin/python"

    uv venv --python "${python_version}" "${venv_dir}/venv-${python_version}"
    uv pip install --python "${python_path}" pytest "${wheel_path}"

    cd /tmp
    "${python_path}" -m pytest \
        --rootdir "${test_dir}" \
        --run-wheel \
        --forbid-path "${repo_root}" \
        "${test_path}"
done
