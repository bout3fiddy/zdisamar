#!/usr/bin/env bash
# Fails if any `test "..."` or anonymous `test { ... }` block reappears under
# src/. Inline tests under src/ are forbidden — they live under tests/unit/,
# mirroring source paths.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
matches=$(grep -rEln '^test([[:space:]]+"|[[:space:]]*\{)' "$repo_root/src" 2>/dev/null || true)
if [ -n "$matches" ]; then
    echo "error: inline test blocks under src/ are forbidden — migrate them to tests/unit/" >&2
    echo "$matches" >&2
    exit 1
fi
