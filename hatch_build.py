"""Hatch build hook for zdisamar native wheels."""

import os
import subprocess
from pathlib import Path
from typing import Any

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


def platform_tag_for_zig_target(zig_target: str | None) -> str | None:

    if zig_target == "x86_64-linux-gnu":
        return "linux_x86_64"

    if zig_target == "aarch64-linux-gnu":
        return "linux_aarch64"

    if zig_target == "x86_64-windows-gnu":
        return "win_amd64"

    if zig_target == "aarch64-windows-gnu":
        return "win_arm64"

    return None


def platform_tag(build_config: Any) -> str:

    target_platform = platform_tag_for_zig_target(os.environ.get("ZDISAMAR_ZIG_TARGET"))

    if target_platform is not None:
        return target_platform

    from packaging.tags import sys_tags

    tag = next(
        candidate
        for candidate in sys_tags()
        if "manylinux" not in candidate.platform and "musllinux" not in candidate.platform
    )
    platform = tag.platform

    if platform.startswith("macosx_"):
        from hatchling.builders.macos import process_macos_plat_tag

        platform = process_macos_plat_tag(
            platform,
            compat=getattr(build_config, "macos_max_compat", False),
        )

    return platform


class NativeWheelHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict) -> None:

        if self.target_name != "wheel":
            return

        command = ["zig", "build", "sync-python-package"]
        zig_target = os.environ.get("ZDISAMAR_ZIG_TARGET")

        if zig_target:
            command.append(f"-Dtarget={zig_target}")

        optimize = os.environ.get("ZDISAMAR_ZIG_OPTIMIZE", "ReleaseFast")
        command.append(f"-Doptimize={optimize}")

        subprocess.run(command, cwd=self.root, check=True)
        library = synced_library_path(self.root)
        build_data["force_include"][str(library)] = f"zdisamar/bindings/{library.name}"
        build_data["tag"] = f"py3-none-{platform_tag(self.build_config)}"
        build_data["pure_python"] = False
