#!/usr/bin/env python3
"""Copy generated Python package resources into the source package tree."""

import argparse
import shutil
import sys
from pathlib import Path


def library_filename() -> str:

    if sys.platform == "darwin":
        return "libzdisamar_c.dylib"

    if sys.platform == "win32":
        return "zdisamar_c.dll"

    return "libzdisamar_c.so"


def parse_args() -> argparse.Namespace:

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--binding",
        type=Path,
        required=True,
        help="Zig-built zdisamar C shared-library artifact.",
    )

    return parser.parse_args()


def copy_tree(source: Path, destination: Path) -> None:

    if destination.exists():
        shutil.rmtree(destination)

    shutil.copytree(source, destination)


def remove_stale_bindings(bindings_dir: Path) -> None:

    for stale in [*bindings_dir.glob("libzdisamar_c.*"), bindings_dir / "zdisamar_c.dll"]:
        if stale.exists():
            stale.unlink()


def main() -> int:

    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    package_root = repo_root / "python" / "zdisamar"
    library_source = args.binding

    if not library_source.is_file():
        raise FileNotFoundError(f"Zig shared library is not built: {library_source}")

    bindings_dir = package_root / "bindings"
    bindings_dir.mkdir(parents=True, exist_ok=True)
    remove_stale_bindings(bindings_dir)
    shutil.copy2(library_source, bindings_dir / library_filename())
    copy_tree(repo_root / "data" / "reference_data", package_root / "reference_data" / "assets")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
