"""Native binding setup for benchmark runs."""

import subprocess
import time
from typing import Any

from . import config


def sync_release_fast() -> dict[str, Any]:

    command = ["zig", "build", "sync-python-package", "-Doptimize=ReleaseFast"]
    start = time.perf_counter()
    subprocess.run(command, cwd=config.REPO_ROOT, check=True)

    return {
        "command": " ".join(command),
        "elapsed_s": time.perf_counter() - start,
    }
