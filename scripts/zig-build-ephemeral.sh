#!/usr/bin/env bash

set -euo pipefail

for arg in "$@"; do
    case "${arg}" in
        --cache-dir|--global-cache-dir|--cache-dir=*|--global-cache-dir=*)
            printf 'scripts/zig-build-ephemeral.sh manages --cache-dir and --global-cache-dir itself\n' >&2
            exit 2
            ;;
    esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
tmp_parent="${TMPDIR:-/tmp}"

local_cache_dir="$(mktemp -d "${tmp_parent%/}/zdisamar-zig-local-cache.XXXXXX")"
global_cache_dir="$(mktemp -d "${tmp_parent%/}/zdisamar-zig-global-cache.XXXXXX")"

cleanup() {
    rm -rf -- "${local_cache_dir}" "${global_cache_dir}"
}

trap cleanup EXIT HUP INT TERM

cd "${repo_root}"

zig build "$@" --cache-dir "${local_cache_dir}" --global-cache-dir "${global_cache_dir}"
