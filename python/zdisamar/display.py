"""Display helpers for notebook-facing domain objects."""


class NotebookDisplay:
    """Use the object's repr as its IPython pretty display."""

    def _repr_pretty_(self, printer, cycle) -> None:

        if cycle:
            printer.text(f"{type(self).__name__}(...)")

            return

        printer.text(repr(self))
