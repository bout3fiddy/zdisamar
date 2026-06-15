from pathlib import Path

import pytest


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--run-wheel",
        action="store_true",
        default=False,
        help="run packaging/install wheel probes",
    )
    parser.addoption(
        "--forbid-path",
        type=Path,
        default=None,
        help="path that must not provide the imported zdisamar package in wheel probes",
    )


def pytest_collection_modifyitems(config: pytest.Config, items: list[pytest.Item]) -> None:
    if config.getoption("--run-wheel"):
        return

    skip_wheel = pytest.mark.skip(reason="wheel packaging probe requires --run-wheel")
    for item in items:
        if "wheel" in item.keywords:
            item.add_marker(skip_wheel)
