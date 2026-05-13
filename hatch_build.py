"""Hatch build hook for zdisamar native wheels."""

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


class NativeWheelHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict) -> None:

        if self.target_name != "wheel":
            return

        build_data["infer_tag"] = True
        build_data["pure_python"] = False
