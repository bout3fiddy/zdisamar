"""Chart export helpers."""

from __future__ import annotations

from pathlib import Path


def save(chart, path: str | Path, *, scale: float = 2.0, ppi: int = 300) -> None:
    """Save an Altair chart, creating parent directories when needed."""

    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    suffix = output.suffix.lower()
    kwargs = {}
    if suffix == ".png":
        kwargs["scale_factor"] = scale
    else:
        _ = scale
    _ = ppi
    chart.save(output, **kwargs)
