"""Hatch build hook for zdisamar native wheels."""

import subprocess
from pathlib import Path

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


def synced_library_path(root: str) -> Path:

    bindings_dir = Path(root) / "python" / "zdisamar" / "bindings"
    candidates = sorted(bindings_dir.glob("libzdisamar_c.*")) + sorted(
        bindings_dir.glob("zdisamar_c.dll")
    )

    if len(candidates) != 1:
        raise RuntimeError(
            f"expected one synced native library in {bindings_dir}, found {candidates}"
        )

    return candidates[0]


class NativeWheelHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict) -> None:

        if self.target_name != "wheel":
            return

        subprocess.run(["zig", "build", "sync-python-package"], cwd=self.root, check=True)
        library = synced_library_path(self.root)
        build_data["force_include"][str(library)] = f"zdisamar/bindings/{library.name}"
        build_data["infer_tag"] = True
        build_data["pure_python"] = False
