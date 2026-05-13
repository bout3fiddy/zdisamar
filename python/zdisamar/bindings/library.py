"""Native zdisamar shared-library discovery."""

import ctypes
import os
import sys
from importlib import resources
from pathlib import Path


def load_library(path: str | os.PathLike[str] | None = None) -> ctypes.CDLL:

    if path is not None:
        return ctypes.CDLL(os.fspath(path))

    env_path = os.environ.get("ZDISAMAR_LIBRARY")

    if env_path:
        return ctypes.CDLL(env_path)

    packaged = resources.files("zdisamar").joinpath("native", library_name())

    if packaged.is_file():
        with resources.as_file(packaged) as packaged_path:
            return ctypes.CDLL(str(packaged_path))

    repo_root = Path(__file__).resolve().parents[3]
    candidates = [
        repo_root / "zig-out" / "lib" / library_name(),
        repo_root / library_name(),
    ]

    for candidate in candidates:
        if candidate.exists():
            return ctypes.CDLL(str(candidate))

    return ctypes.CDLL(library_name())


def library_name() -> str:

    if sys.platform == "darwin":
        return "libzdisamar_c.dylib"

    if os.name == "nt":
        return "zdisamar_c.dll"

    return "libzdisamar_c.so"
