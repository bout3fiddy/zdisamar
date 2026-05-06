from __future__ import annotations

import argparse
import os
from pathlib import Path

import nbformat
from nbclient import NotebookClient


def repo_root() -> Path:
    start = Path(__file__).resolve()
    for candidate in (start, *start.parents):
        if (candidate / "build.zig").exists() and (candidate / "pyproject.toml").exists():
            return candidate
    raise RuntimeError("could not find repository root")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Execute a demo notebook and write the executed copy under out/demo.")
    parser.add_argument("notebook", type=Path, help="Source notebook path.")
    parser.add_argument("--timeout", type=int, default=1800, help="Cell timeout in seconds.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = repo_root()
    notebook_path = args.notebook if args.notebook.is_absolute() else root / args.notebook
    notebook = nbformat.read(notebook_path, as_version=4)

    output_dir = root / "out" / "demo" / "executed"
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / notebook_path.name

    os.environ["ZDISAMAR_REPO_ROOT"] = str(root)
    client = NotebookClient(
        notebook,
        kernel_name="python3",
        resources={"metadata": {"path": str(root)}},
        timeout=args.timeout,
    )
    client.execute()
    nbformat.write(notebook, output_path)
    print(f"executed {notebook_path.relative_to(root)} -> {output_path.relative_to(root)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
