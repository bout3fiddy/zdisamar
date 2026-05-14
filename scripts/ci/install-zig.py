#!/usr/bin/env python3
"""Install Zig on GitHub-hosted runners without a JavaScript action."""

import hashlib
import inspect
import json
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

TARGETS = {
    ("Linux", "X64"): "x86_64-linux",
    ("Windows", "X64"): "x86_64-windows",
    ("macOS", "X64"): "x86_64-macos",
    ("macOS", "ARM64"): "aarch64-macos",
}


def runner_target() -> str:

    key = (os.environ["RUNNER_OS"], os.environ["RUNNER_ARCH"])

    try:
        return TARGETS[key]
    except KeyError as exc:
        raise SystemExit(f"unsupported runner target: {key}") from exc


def download(url: str, destination: Path, expected_sha256: str) -> None:

    digest = hashlib.sha256()

    with urllib.request.urlopen(url) as response, destination.open("wb") as handle:
        while True:
            chunk = response.read(1024 * 1024)

            if not chunk:
                break

            digest.update(chunk)
            handle.write(chunk)

    actual = digest.hexdigest()

    if actual != expected_sha256:
        raise SystemExit(f"zig archive checksum mismatch: expected {expected_sha256}, got {actual}")


def unpack(archive: Path, destination: Path) -> Path:

    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as bundle:
            roots = {name.split("/", 1)[0] for name in bundle.namelist() if "/" in name}
            bundle.extractall(destination)
    else:
        with tarfile.open(archive) as bundle:
            roots = {member.name.split("/", 1)[0] for member in bundle.getmembers()}
            supports_filter = "filter" in inspect.signature(bundle.extractall).parameters

            if supports_filter:
                bundle.extractall(destination, filter="data")
            else:
                bundle.extractall(destination)

    if len(roots) != 1:
        raise SystemExit(f"expected one Zig archive root, found {sorted(roots)}")

    return destination / roots.pop()


def append_github_path(path: Path) -> None:

    github_path = os.environ.get("GITHUB_PATH")

    if github_path is None:
        print(path)

        return

    with Path(github_path).open("a", encoding="utf-8") as handle:
        handle.write(f"{path}\n")


def main() -> int:

    if len(sys.argv) != 2:
        raise SystemExit("usage: install-zig.py <version>")

    version = sys.argv[1]
    target = runner_target()
    workspace = Path(os.environ.get("GITHUB_WORKSPACE", Path.cwd()))
    install_root = workspace / ".zig" / version / target
    archive = workspace / ".zig" / f"zig-{version}-{target}"

    if not install_root.exists():
        shutil.rmtree(install_root.parent, ignore_errors=True)
        install_root.parent.mkdir(parents=True, exist_ok=True)
        archive.parent.mkdir(parents=True, exist_ok=True)

        with urllib.request.urlopen("https://ziglang.org/download/index.json") as response:
            manifest = json.load(response)

        package = manifest[version][target]
        archive_extension = ".zip" if package["tarball"].endswith(".zip") else ".tar.xz"
        archive_path = archive.parent / f"{archive.name}{archive_extension}"
        download(package["tarball"], archive_path, package["shasum"])
        unpacked = unpack(archive_path, install_root.parent)
        unpacked.rename(install_root)

    append_github_path(install_root)
    subprocess.run(
        [str(install_root / ("zig.exe" if target.endswith("windows") else "zig")), "version"],
        check=True,
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
