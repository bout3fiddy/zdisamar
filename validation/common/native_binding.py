"""Native binding setup for validation scripts."""

import subprocess
import time
from pathlib import Path
from typing import Any


def sync_release_fast_binding(repo_root: Path) -> dict[str, Any]:
    """Build and sync the ReleaseFast Python binding before validation imports it."""

    command = ["zig", "build", "sync-python-package", "-Doptimize=ReleaseFast"]
    start = time.perf_counter()
    subprocess.run(command, cwd=repo_root, check=True)
    elapsed_s = time.perf_counter() - start
    print(f"[native] synced ReleaseFast binding in {elapsed_s:.3f}s", flush=True)

    return {
        "command": " ".join(command),
        "elapsed_s": elapsed_s,
    }
