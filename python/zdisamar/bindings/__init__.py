"""Connection to the zdisamar library."""

from .library import load_library
from .signatures import configure

__all__ = ["configure", "load_library"]
