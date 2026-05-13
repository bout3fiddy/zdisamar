"""Output-comparison helpers for validation artifacts."""

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ScalarComparison:
    name: str
    actual: float | int | bool
    expected: float | int | bool
    tolerance: float | None
    passed: bool
    difference: float | None

    def to_json(self) -> dict[str, Any]:

        return {
            "name": self.name,
            "actual": self.actual,
            "expected": self.expected,
            "tolerance": self.tolerance,
            "passed": self.passed,
            "difference": self.difference,
        }


def compare_scalar(
    name: str,
    actual: float | int | bool,
    expected: float | int | bool,
    *,
    tolerance: float | None = None,
) -> ScalarComparison:

    if isinstance(actual, bool) or isinstance(expected, bool):
        passed = bool(actual) == bool(expected)
        difference = None
    else:
        difference = float(actual) - float(expected)
        passed = abs(difference) <= float(tolerance or 0.0)

    return ScalarComparison(
        name=name,
        actual=actual,
        expected=expected,
        tolerance=tolerance,
        passed=passed,
        difference=difference,
    )
