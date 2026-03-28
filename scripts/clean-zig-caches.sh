#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cd "${repo_root}"

removed_any=0

for cache_dir in .zig-cache .zig-cache-int zig-cache; do
    if [ -e "${cache_dir}" ]; then
        rm -rf -- "${cache_dir}"
        printf 'removed %s\n' "${cache_dir}"
        removed_any=1
    fi
done

if [ "${removed_any}" -eq 0 ]; then
    printf 'no repo-local Zig caches were present\n'
fi
