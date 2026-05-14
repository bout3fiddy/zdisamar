#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${1:-"${repo_root}/dist"}"

cd "${repo_root}"
rm -rf "${out_dir}"
mkdir -p "${out_dir}"

uv run --no-project --python 3.14 --with 'hatchling>=1.29' python -m hatchling build -t wheel -d "${out_dir}"
