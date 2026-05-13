"""JSON-compatible timing helpers for validation scripts."""

from collections.abc import Callable, Iterator
from contextlib import contextmanager
from time import perf_counter
from typing import ParamSpec, TypeVar

P = ParamSpec("P")
T = TypeVar("T")


class PhaseTimer:
    def __init__(self) -> None:
        self._total_start = perf_counter()
        self.phases_s: dict[str, float] = {}

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        self.finish()

    @contextmanager
    def phase(self, name: str) -> Iterator[None]:
        start = perf_counter()
        try:
            yield
        finally:
            self.phases_s[name] = perf_counter() - start

    def run(
        self, name: str, callable_object: Callable[P, T], *args: P.args, **kwargs: P.kwargs
    ) -> T:
        with self.phase(name):
            return callable_object(*args, **kwargs)

    def finish(self) -> dict[str, float]:
        self.phases_s["total_s"] = perf_counter() - self._total_start
        return dict(self.phases_s)
