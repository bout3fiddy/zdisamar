#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/vendor/disamar-fortran"
UPSTREAM_URL="https://gitlab.com/KNMI-OSS/disamar/disamar.git"

mkdir -p "${ROOT_DIR}/vendor"

if [[ -d "${TARGET_DIR}/.git" ]]; then
  git -C "${TARGET_DIR}" pull --ff-only
else
  git clone --depth 1 "${UPSTREAM_URL}" "${TARGET_DIR}"
fi
