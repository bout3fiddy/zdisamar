#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wheel_input="${1:-}"

if [[ -z "${wheel_input}" ]]; then
    echo "usage: scripts/smoke-linux-wheel-docker.sh <linux-wheel-or-directory>" >&2
    echo "set ZDISAMAR_DOCKER_SMOKE_IMAGES to entries like image or image::/path/to/python" >&2
    exit 2
fi

if [[ -d "${wheel_input}" ]]; then
    wheel_path="$(find "${wheel_input}" -maxdepth 1 -name 'zdisamar-*.whl' -print -quit)"
else
    wheel_path="${wheel_input}"
fi

if [[ -z "${wheel_path}" || ! -f "${wheel_path}" ]]; then
    echo "no zdisamar wheel found: ${wheel_input}" >&2
    exit 1
fi

case "$(basename "${wheel_path}")" in
    *linux* | *manylinux* | *musllinux*) ;;
    *)
        echo "expected a Linux wheel, got: ${wheel_path}" >&2
        exit 1
        ;;
esac

wheel_dir="$(cd "$(dirname "${wheel_path}")" && pwd)"
wheel_name="$(basename "${wheel_path}")"
read -r -a images <<< "${ZDISAMAR_DOCKER_SMOKE_IMAGES:-python:3.11-slim-bookworm python:3.12-slim-bookworm python:3.13-slim-bookworm python:3.14-slim-bookworm}"

for entry in "${images[@]}"; do
    image="${entry%%::*}"
    python_cmd="python"
    if [[ "${entry}" == *"::"* ]]; then
        python_cmd="${entry#*::}"
    fi

    echo "smoke_linux_wheel_docker image=${image} python=${python_cmd} wheel=${wheel_name}"
    docker run --rm --platform linux/amd64 \
        --mount "type=bind,src=${wheel_dir},dst=/dist,readonly" \
        --mount "type=bind,src=${repo_root},dst=/workspace,readonly" \
        -e ZDISAMAR_DOCKER_PYTHON="${python_cmd}" \
        -e ZDISAMAR_WHEEL_NAME="${wheel_name}" \
        "${image}" \
        sh -lc '
            set -e
            "${ZDISAMAR_DOCKER_PYTHON}" -m venv /tmp/zdisamar-smoke
            /tmp/zdisamar-smoke/bin/python -m pip install --no-cache-dir \
                pytest \
                "/dist/${ZDISAMAR_WHEEL_NAME}"
            cd /tmp
            /tmp/zdisamar-smoke/bin/python -m pytest \
                --run-wheel \
                --forbid-path /workspace \
                /workspace/tests/python/test_wheel_install_smoke.py \
        '
done
