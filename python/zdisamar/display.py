"""Display helpers for notebook-facing domain objects."""

import json
from collections.abc import Iterator, Mapping


def pretty_json_value(value: object) -> object:
    """Return JSON-friendly values for compact notebook summaries."""

    if isinstance(value, Mapping):
        return {str(key): pretty_json_value(item) for key, item in value.items()}

    if isinstance(value, tuple | list):
        return [pretty_json_value(item) for item in value]

    return value


class NotebookDisplay:
    """Use the object's repr as its IPython pretty display."""

    def _repr_pretty_(self, printer, cycle) -> None:

        if cycle:
            printer.text(f"{type(self).__name__}(...)")

            return

        printer.text(repr(self))


class PrettyMapping(NotebookDisplay, Mapping[str, object]):
    """Small display object for public summaries that would otherwise be raw dicts."""

    def __init__(self, title: str, data: Mapping[str, object]) -> None:

        self.title = str(title)
        self.data = dict(data)

    def __getitem__(self, key: str) -> object:

        return self.data[key]

    def __iter__(self) -> Iterator[str]:

        return iter(self.data)

    def __len__(self) -> int:

        return len(self.data)

    def to_dict(self) -> dict[str, object]:
        """Return the underlying summary for programmatic use."""

        return {str(key): pretty_json_value(item) for key, item in self.data.items()}

    def __repr__(self) -> str:

        payload = json.dumps(self.to_dict(), indent=2, sort_keys=False)

        return f"{self.title}({payload})"
