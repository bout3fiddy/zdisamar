"""Access packaged zdisamar reference-data assets."""

from contextlib import ExitStack
from importlib import resources
from pathlib import Path

_RESOURCE_STACK = ExitStack()


def root() -> Path:
    """Return the directory containing packaged reference-data assets."""

    packaged = resources.files("zdisamar.reference_data").joinpath("assets")

    if packaged.is_dir():
        return Path(_RESOURCE_STACK.enter_context(resources.as_file(packaged)))

    raise FileNotFoundError(
        "zdisamar reference-data assets are not packaged; run `zig build` before "
        "using the source checkout or install a built wheel"
    )


def path(relative: str | Path) -> Path:
    """Return an existing packaged reference-data path."""

    relative_path = Path(relative)

    if relative_path.is_absolute() or ".." in relative_path.parts:
        raise ValueError("reference-data paths must be relative to data/reference_data")

    resolved = root() / relative_path

    if not resolved.exists():
        raise FileNotFoundError(f"zdisamar reference-data asset not found: {relative_path}")

    return resolved


def resolve_asset_path(asset_path: str | Path) -> Path:
    """Resolve an input asset path that may include the data/reference_data prefix."""

    raw = Path(asset_path)

    if raw.is_absolute():
        return raw

    parts = raw.parts
    prefix = ("data", "reference_data")

    if parts[:2] == prefix:
        return path(Path(*parts[2:]))

    return raw


__all__ = ["path", "resolve_asset_path", "root"]
