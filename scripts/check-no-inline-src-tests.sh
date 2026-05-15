#!/usr/bin/env bash
# Fails if inline Rust test modules reappear under rust_src/. Tests belong under
# tests/rust/ so production modules stay focused on implementation.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
matches=$(grep -rEln '^[[:space:]]*#\[cfg\(test\)\]|^[[:space:]]*mod[[:space:]]+tests[[:space:]]*\{' "$repo_root/rust_src" 2>/dev/null || true)
if [ -n "$matches" ]; then
    echo "error: inline test modules under rust_src/ are forbidden — migrate them to tests/rust/" >&2
    echo "$matches" >&2
    exit 1
fi
