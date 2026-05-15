"""Hatch build hook for zdisamar native wheels."""

import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


def platform_tag_for_cargo_target(cargo_target: str | None) -> str | None:

    if cargo_target == "x86_64-unknown-linux-gnu":
        return "linux_x86_64"

    if cargo_target == "aarch64-unknown-linux-gnu":
        return "linux_aarch64"

    if cargo_target == "x86_64-pc-windows-msvc":
        return "win_amd64"

    if cargo_target == "aarch64-pc-windows-msvc":
        return "win_arm64"

    return None


def platform_tag(build_config: Any) -> str:

    target_platform = platform_tag_for_cargo_target(os.environ.get("ZDISAMAR_CARGO_TARGET"))

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


def cargo_profile() -> str:

    return os.environ.get("ZDISAMAR_CARGO_PROFILE", "release")


def cargo_library_name() -> str:

    import sys

    if sys.platform == "darwin":
        return "libzdisamar.dylib"

    if os.name == "nt":
        return "zdisamar.dll"

    return "libzdisamar.so"


def packaged_library_name() -> str:

    import sys

    if sys.platform == "darwin":
        return "libzdisamar_c.dylib"

    if os.name == "nt":
        return "zdisamar_c.dll"

    return "libzdisamar_c.so"


def built_library_path(root: str) -> Path:

    target = os.environ.get("ZDISAMAR_CARGO_TARGET")
    profile = cargo_profile()
    profile_dir = "release" if profile == "release" else profile
    target_dir = Path(root) / "target"

    if target:
        target_dir /= target

    return target_dir / profile_dir / cargo_library_name()


def copy_reference_data_assets(root: str) -> None:

    source = Path(root) / "data" / "reference_data"
    destination = Path(root) / "python" / "zdisamar" / "reference_data" / "assets"

    if destination.exists():
        shutil.rmtree(destination)

    shutil.copytree(source, destination)


def sync_python_package(root: str) -> Path:

    command = ["cargo", "build"]
    target = os.environ.get("ZDISAMAR_CARGO_TARGET")
    profile = cargo_profile()

    if profile == "release":
        command.append("--release")
    elif profile != "debug":
        command.extend(["--profile", profile])

    if target:
        command.extend(["--target", target])

    subprocess.run(command, cwd=root, check=True)
    source = built_library_path(root)

    if not source.is_file():
        raise RuntimeError(f"cargo build did not produce {source}")

    bindings_dir = Path(root) / "python" / "zdisamar" / "bindings"
    bindings_dir.mkdir(parents=True, exist_ok=True)

    for stale in [*bindings_dir.glob("libzdisamar_c.*"), bindings_dir / "zdisamar_c.dll"]:
        stale.unlink(missing_ok=True)

    target_path = bindings_dir / packaged_library_name()
    shutil.copy2(source, target_path)
    copy_reference_data_assets(root)

    return target_path


class NativeWheelHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict) -> None:

        if self.target_name != "wheel":
            return

        library = sync_python_package(self.root)
        build_data["force_include"][str(library)] = f"zdisamar/bindings/{library.name}"
        build_data["tag"] = f"py3-none-{platform_tag(self.build_config)}"
        build_data["pure_python"] = False
