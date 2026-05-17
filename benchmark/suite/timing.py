"""Timing helpers."""

import time
from collections.abc import Callable
from typing import Any


def timed(callback: Callable[[], Any]) -> tuple[float, Any]:

    start = time.perf_counter()
    value = callback()

    return time.perf_counter() - start, value
