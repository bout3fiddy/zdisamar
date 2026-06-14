#!/usr/bin/env python3
"""Fail when counted src pub fns have no production caller and no reason."""

import re
import subprocess
import sys
from pathlib import Path

PUB_FN_RE = re.compile(r"^\s*pub\s+(?:inline\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\b", re.M)

HG_PHASE_STAGED_REASON = "staged HG phase lane; tests must cover it before first use"
MATRIX_REFERENCE_REASON = "matrix reference form; tests assert equality with fused variants"
MATRIX_KNOWN_PRODUCT_REASON = "matrix helper; production uses known-product kernels"
MATRIX_CALLER_OWNED_REASON = "matrix helper; production uses caller-owned kernels"


ALLOWLIST: dict[tuple[str, str], str] = {
    (
        "src/common/math/gauss_legendre.zig",
        "fillDisamarDivPointsIntervalNodes",
    ): "DISAMAR node split oracle; production uses retained rows plus scaleIntervalNodes",
    (
        "src/common/worker_partition.zig",
        "preferredWorkerCountForCpuCount",
    ): "worker-count test oracle; production uses preferredWorkerCount",
    (
        "src/input/hitran_partition_tables.zig",
        "partitionSampleMatchesEndpointSecant",
    ): "prepared partition spline oracle; production uses ratioT0OverT",
    (
        "src/root.zig",
        "runO2A",
    ): "public Zig one-shot facade; C/Python uses context-owned session path",
    (
        "src/setup/atmosphere_layers.zig",
        "intervalNodes",
    ): "same-file helper; tests assert retained canonical row lookup",
    (
        "src/setup/phase_table.zig",
        "zeroPhaseCoefficients",
    ): "phase coefficient storage oracle; keep until HG phase lane is wired",
    (
        "src/setup/phase_table.zig",
        "hgPhaseCoefficients",
    ): HG_PHASE_STAGED_REASON,
    (
        "src/setup/phase_table.zig",
        "hgPhaseCoefficientsWithThreshold",
    ): HG_PHASE_STAGED_REASON,
    (
        "src/setup/phase_table.zig",
        "maxPhaseCoefficientIndex",
    ): HG_PHASE_STAGED_REASON,
    (
        "src/spectrum/instrument_average.zig",
        "applySlitConvolution",
    ): "slit-kernel normalization oracle; same-file production path reaches it",
    (
        "src/spectrum/sampling_table.zig",
        "summarize",
    ): "sampling-table shape oracle until runner owns telemetry summary",
    (
        "src/spectrum/spectrum_run.zig",
        "gatherProductRows",
    ): "same-file stage helper; runO2ASpectrum calls it",
    (
        "src/spectrum/spectrum_run.zig",
        "postprocessAndAssembleProductRows",
    ): "same-file stage helper; runO2ASpectrum calls it",
    ("src/rtm/gauss_angles.zig", "pairIndex"): "paired Gaussian layout oracle",
    (
        "src/rtm/layer_reflect_transmit.zig",
        "renormalizeZeroFourierPhaseKernel",
    ): "LABOS phase renormalization oracle",
    (
        "src/rtm/layer_reflect_transmit.zig",
        "classifyLayerDoubling",
    ): "LABOS layer-doubling branch oracle",
    (
        "src/rtm/layer_reflect_transmit.zig",
        "fillSingleScatterReflection",
    ): "LABOS single-scatter reflection oracle",
    (
        "src/rtm/layer_reflect_transmit.zig",
        "fillSingleScatterTransmission",
    ): "LABOS single-scatter transmission oracle",
    (
        "src/rtm/layer_reflect_transmit.zig",
        "gaussianBlockTrace",
    ): "LABOS trace-gate oracle",
    (
        "src/rtm/layer_reflect_transmit.zig",
        "squareAttenuation",
    ): "LABOS layer-doubling primitive oracle",
    (
        "src/rtm/layer_reflect_transmit.zig",
        "doubleLayer",
    ): "LABOS layer-doubling primitive oracle",
    (
        "src/rtm/matrix_12x10.zig",
        "smul",
    ): MATRIX_REFERENCE_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "smulInto",
    ): MATRIX_KNOWN_PRODUCT_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "smulIntoKnownTraces",
    ): MATRIX_KNOWN_PRODUCT_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "smulIntoKnownTracesIfNonzero",
    ): MATRIX_KNOWN_PRODUCT_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "qseries",
    ): MATRIX_REFERENCE_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "qseriesKnownNonzeroProduct",
    ): "q-series retained-product oracle",
    (
        "src/rtm/matrix_12x10.zig",
        "esmul",
    ): MATRIX_REFERENCE_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "semul",
    ): MATRIX_REFERENCE_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "matAdd",
    ): MATRIX_REFERENCE_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "matAddSemul3",
    ): MATRIX_CALLER_OWNED_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "smulAddSemul3",
    ): MATRIX_CALLER_OWNED_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "smulAddSemul3KnownRightTrace",
    ): MATRIX_CALLER_OWNED_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "semulAdd",
    ): MATRIX_CALLER_OWNED_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "matAddEsmul3",
    ): MATRIX_CALLER_OWNED_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "matAddEsmul",
    ): MATRIX_CALLER_OWNED_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "esmulSemul",
    ): MATRIX_CALLER_OWNED_REASON,
    (
        "src/rtm/matrix_12x10.zig",
        "esmulSemulAdd",
    ): MATRIX_CALLER_OWNED_REASON,
    ("src/rtm/phase_basis.zig", "minusParitySign"): "transport test oracle for old LABOS Z- parity",
    (
        "src/rtm/reflectance.zig",
        "fourierWeight",
    ): "transport test oracle for old Fourier accumulation weight",
    (
        "src/rtm/reflectance.zig",
        "fourierTailBreak",
    ): "transport test oracle for old Fourier tail stop rule",
    (
        "src/retrieval/root.zig",
        "altitudeDerivativeAtPressure",
    ): "staged pressure-profile hook; tests cover finite-difference route",
}


def git_files(patterns: list[str]) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", *patterns],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return result.stdout.splitlines()


def counted_src_file(path: str) -> bool:
    if not path.startswith("src/") or not path.endswith(".zig"):
        return False
    if path.startswith("src/instrumentation/"):
        return False
    if path.startswith("src/validation/"):
        return False
    return path != "src/internal.zig"


def search_src_file(path: str) -> bool:
    return (
        path.startswith("src/")
        and path.endswith(".zig")
        and path != "src/internal.zig"
        and not path.startswith("src/validation/")
    )


def main() -> int:
    repo_root = Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout.strip()
    )
    tracked_src = git_files(["src/**/*.zig", "src/*.zig"])
    current_src = [path for path in tracked_src if (repo_root / path).exists()]
    counted_files = [path for path in current_src if counted_src_file(path)]
    search_files = [path for path in current_src if search_src_file(path)]
    search_text = {path: (repo_root / path).read_text() for path in search_files}

    pub_fn_count = 0
    uncalled: list[tuple[str, int, str]] = []
    for path in counted_files:
        text = search_text[path]
        for match in PUB_FN_RE.finditer(text):
            pub_fn_count += 1
            name = match.group(1)
            line = text.count("\n", 0, match.start()) + 1
            name_re = re.compile(r"\b" + re.escape(name) + r"\b")
            has_caller = any(
                other_path != path and name_re.search(other_text)
                for other_path, other_text in search_text.items()
            )
            if not has_caller:
                uncalled.append((path, line, name))

    allowlisted = []
    non_allowlisted = []
    seen_allowlist_keys: set[tuple[str, str]] = set()
    for path, line, name in uncalled:
        key = (path, name)
        reason = ALLOWLIST.get(key)
        if reason:
            seen_allowlist_keys.add(key)
            allowlisted.append((path, line, name, reason))
        else:
            non_allowlisted.append((path, line, name))

    stale_allowlist = sorted(set(ALLOWLIST) - seen_allowlist_keys)

    print(
        "dead-surface: "
        f"counted_files={len(counted_files)} "
        f"pub_fns={pub_fn_count} "
        f"uncalled={len(uncalled)} "
        f"allowlisted={len(allowlisted)} "
        f"non_allowlisted={len(non_allowlisted)}"
    )

    if non_allowlisted:
        print("\nnon-allowlisted uncalled pub fns:")
        for path, line, name in non_allowlisted:
            print(f"  {path}:{line}:{name}")

    if stale_allowlist:
        print("\nstale allowlist entries:")
        for path, name in stale_allowlist:
            print(f"  {path}:{name}")

    if non_allowlisted or stale_allowlist:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
