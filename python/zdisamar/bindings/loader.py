"""Load the packaged zdisamar native binding."""

import ctypes
import os
import sys
from importlib import resources


def load_library() -> ctypes.CDLL:
    """Load the shared library shipped inside the Python package."""

    packaged = resources.files("zdisamar.bindings").joinpath(library_filename())

    if not packaged.is_file():
        raise FileNotFoundError(
            "zdisamar native bindings are not packaged; build the Rust library before using "
            "the source checkout or install a built wheel"
        )

    with resources.as_file(packaged) as packaged_path:
        return ctypes.CDLL(os.fspath(packaged_path))


def library_filename() -> str:
    """Return the platform-specific binding filename."""

    if sys.platform == "darwin":
        return "libzdisamar_c.dylib"

    if os.name == "nt":
        return "zdisamar_c.dll"

    return "libzdisamar_c.so"
