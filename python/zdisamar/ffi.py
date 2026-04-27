"""ctypes bindings for coarse native O2A spectrum calls."""

from __future__ import annotations

import ctypes
import os
import sys
from pathlib import Path
from typing import Optional


class _CSpectrum(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("wavelength_nm", ctypes.POINTER(ctypes.c_double)),
        ("radiance", ctypes.POINTER(ctypes.c_double)),
        ("irradiance", ctypes.POINTER(ctypes.c_double)),
        ("reflectance", ctypes.POINTER(ctypes.c_double)),
        ("result_handle", ctypes.c_void_p),
    ]


def _library_name() -> str:
    if sys.platform == "darwin":
        return "libzdisamar_c.dylib"
    if os.name == "nt":
        return "zdisamar_c.dll"
    return "libzdisamar_c.so"


def _load_library(path: Optional[str | os.PathLike[str]] = None) -> ctypes.CDLL:
    if path is not None:
        return ctypes.CDLL(os.fspath(path))

    env_path = os.environ.get("ZDISAMAR_LIBRARY")
    if env_path:
        return ctypes.CDLL(env_path)

    repo_root = Path(__file__).resolve().parents[2]
    candidates = [
        repo_root / "zig-out" / "lib" / _library_name(),
        repo_root / _library_name(),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ctypes.CDLL(str(candidate))

    return ctypes.CDLL(_library_name())


def _configure(lib: ctypes.CDLL) -> ctypes.CDLL:
    lib.zds_context_create.argtypes = []
    lib.zds_context_create.restype = ctypes.c_void_p
    lib.zds_context_destroy.argtypes = [ctypes.c_void_p]
    lib.zds_context_destroy.restype = None
    lib.zds_prepare_default_o2a.argtypes = [ctypes.c_void_p]
    lib.zds_prepare_default_o2a.restype = ctypes.c_int
    lib.zds_run_spectrum.argtypes = [ctypes.c_void_p, ctypes.POINTER(_CSpectrum)]
    lib.zds_run_spectrum.restype = ctypes.c_int
    lib.zds_spectrum_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(_CSpectrum)]
    lib.zds_spectrum_free.restype = None
    lib.zds_last_error.argtypes = [ctypes.c_void_p]
    lib.zds_last_error.restype = ctypes.c_char_p
    return lib


class Spectrum:
    """Bulk spectrum arrays returned by one native run."""

    def __init__(self, owner: "Context", raw: _CSpectrum, close_owner: bool = False):
        self._owner = owner
        self._raw = raw
        self._close_owner = close_owner

    def _array(self, pointer: ctypes.POINTER(ctypes.c_double)):
        import numpy as np

        return np.ctypeslib.as_array(pointer, shape=(self._raw.len,))

    @property
    def wavelength_nm(self):
        return self._array(self._raw.wavelength_nm)

    @property
    def radiance(self):
        return self._array(self._raw.radiance)

    @property
    def irradiance(self):
        return self._array(self._raw.irradiance)

    @property
    def reflectance(self):
        return self._array(self._raw.reflectance)

    def close(self) -> None:
        if self._owner is not None:
            owner = self._owner
            owner._free_spectrum(self._raw)
            if self._close_owner:
                owner.close()
            self._owner = None
            self._raw = _CSpectrum()
            self._close_owner = False

    def __enter__(self) -> "Spectrum":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class Context:
    """Native zdisamar context."""

    def __init__(self, library_path: Optional[str | os.PathLike[str]] = None):
        self._lib = _configure(_load_library(library_path))
        self._ctx = self._lib.zds_context_create()
        if not self._ctx:
            raise RuntimeError("failed to create zdisamar context")

    def close(self) -> None:
        if self._ctx:
            self._lib.zds_context_destroy(self._ctx)
            self._ctx = None

    def prepare_default_o2a(self) -> "Context":
        self._check(self._lib.zds_prepare_default_o2a(self._ctx))
        return self

    def run(self) -> Spectrum:
        raw = _CSpectrum()
        self._check(self._lib.zds_run_spectrum(self._ctx, ctypes.byref(raw)))
        return Spectrum(self, raw)

    def _free_spectrum(self, raw: _CSpectrum) -> None:
        self._lib.zds_spectrum_free(self._ctx, ctypes.byref(raw))

    def _check(self, status: int) -> None:
        if status == 0:
            return
        message = self._lib.zds_last_error(self._ctx)
        raise RuntimeError((message or b"zdisamar error").decode("utf-8", errors="replace"))

    def __enter__(self) -> "Context":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


def forward(library_path: Optional[str | os.PathLike[str]] = None) -> Spectrum:
    ctx = Context(library_path)
    try:
        ctx.prepare_default_o2a()
        raw = _CSpectrum()
        ctx._check(ctx._lib.zds_run_spectrum(ctx._ctx, ctypes.byref(raw)))
        return Spectrum(ctx, raw, close_owner=True)
    except Exception:
        ctx.close()
        raise
