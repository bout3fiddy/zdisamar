"""Dataclass tables returned by RTM diagnostic functions."""

from collections.abc import Mapping
from dataclasses import dataclass
from typing import ClassVar

from ..bindings.structures import (
    CAtmosphericBudgetRow,
)


def field_names(structure: type[object]) -> tuple[str, ...]:
    """Keep Python table columns in the same order as the model output."""

    fields = getattr(structure, "_fields_")  # noqa: B009

    return tuple(str(field[0]) for field in fields)


@dataclass(frozen=True)
class RtmTable:
    """Copied RTM diagnostic rows."""

    data: tuple[dict[str, object], ...]

    columns: ClassVar[tuple[str, ...]]
    label_columns: ClassVar[Mapping[str, tuple[str, Mapping[int, str]]]] = {}

    @property
    def row_count(self) -> int:

        return len(self.data)

    @property
    def table(self) -> tuple[dict[str, object], ...]:
        """Return a copy so analysis code cannot mutate the stored table."""

        return tuple(dict(row) for row in self.data)

    def column(self, name: str) -> tuple[object, ...]:

        if name not in self.columns:
            raise KeyError(name)

        return tuple(row[name] for row in self.data)

    def to_rows(self) -> list[dict[str, object]]:
        """Return rows with labels for coded model fields."""

        rows: list[dict[str, object]] = []

        for row in self.data:
            item = {name: row[name] for name in self.columns}

            for label_name, (source_name, labels) in self.label_columns.items():
                source_value = item[source_name]

                if not isinstance(source_value, int | float | str):
                    item[label_name] = "unknown"
                else:
                    item[label_name] = labels.get(int(source_value), "unknown")

            rows.append(item)

        return rows


@dataclass(frozen=True)
class AtmosphericBudget(RtmTable):
    """Atmospheric support-row absorption and scattering table."""

    support_row_kind_labels = {
        0: "physical",
        1: "parity_boundary",
        2: "parity_active",
    }
    columns = field_names(CAtmosphericBudgetRow)
    label_columns = {
        "support_row_kind_label": ("support_row_kind", support_row_kind_labels),
    }

    @property
    def plot(self):

        from ..plot.atmosphere import BudgetPlot

        return BudgetPlot(self)
