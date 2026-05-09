"""JSON-compatible timing helpers for validation scripts."""

from collections.abc import Iterator
from contextlib import contextmanager
from time import perf_counter


class PhaseTimer:
    def __init__(self) -> None:
        self._total_start = perf_counter()
        self.phases_s: dict[str, float] = {}

    @contextmanager
    def phase(self, name: str) -> Iterator[None]:
        start = perf_counter()
        try:
            yield
        finally:
            self.phases_s[name] = perf_counter() - start

    def finish(self) -> dict[str, float]:
        self.phases_s["total_s"] = perf_counter() - self._total_start
        return dict(self.phases_s)
