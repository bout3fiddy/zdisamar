from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from validation.common.o2a_reference_case import asset, build_o2a_case  # noqa: E402

__all__ = ["asset", "build_o2a_case"]
