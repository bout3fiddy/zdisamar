"""Hatch build hook for zdisamar native wheels."""

import subprocess
import sys
from pathlib import Path

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


def library_filename() -> str:

    if sys.platform == "darwin":
        return "libzdisamar_c.dylib"

    if sys.platform == "win32":
        return "zdisamar_c.dll"

    return "libzdisamar_c.so"


class NativeWheelHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict) -> None:

        if self.target_name != "wheel":
            return

        subprocess.run(["zig", "build", "sync-python-package"], cwd=self.root, check=True)
        filename = library_filename()
        build_data["force_include"][
            str(Path(self.root) / "python" / "zdisamar" / "bindings" / filename)
        ] = f"zdisamar/bindings/{filename}"
        build_data["infer_tag"] = True
        build_data["pure_python"] = False
