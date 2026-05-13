"""Path and JSON helpers for validation scripts."""

import json
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
VALIDATION_ROOT = REPO_ROOT / "validation"
VALIDATION_REFERENCE_DATA_ROOT = VALIDATION_ROOT / "reference_data"
OUT_VALIDATION_ROOT = REPO_ROOT / "out" / "validation"


def stable_repo_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
