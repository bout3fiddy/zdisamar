"""Hatch build hook for zdisamar native wheels."""

import subprocess

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


class NativeWheelHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict) -> None:

        if self.target_name != "wheel":
            return

        subprocess.run(["zig", "build", "sync-python-package"], cwd=self.root, check=True)
        build_data["infer_tag"] = True
        build_data["pure_python"] = False
