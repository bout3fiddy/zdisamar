#!/usr/bin/env python3
"""Fail when counted src pub fns have no production caller and no reason."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


PUB_FN_RE = re.compile(r"^\s*pub\s+(?:inline\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\b", re.M)


ALLOWLIST: dict[tuple[str, str], str] = {
    ("src/common/math/gauss_legendre.zig", "fillDisamarDivPointsIntervalNodes"): "test oracle for canonical DISAMAR node split; production uses retained canonical rows plus scaleIntervalNodes",
    ("src/common/worker_partition.zig", "preferredWorkerCountForCpuCount"): "worker-count oracle for preferredWorkerCount tests; production uses preferredWorkerCount",
    ("src/input/hitran_partition_tables.zig", "partitionSampleMatchesEndpointSecant"): "test oracle for prepared HITRAN partition spline state; production uses ratioT0OverT",
    ("src/root.zig", "runO2A"): "public Zig one-shot facade; C/Python uses runO2AWithSessionMemory through the context-owned session path",
    ("src/setup/atmosphere_layers.zig", "intervalNodes"): "same-file production helper; buildWithQuadrature calls it while tests assert retained canonical row lookup",
    ("src/setup/phase_table.zig", "zeroPhaseCoefficients"): "test oracle for phase coefficient storage; keep until HG phase lane is wired",
    ("src/setup/phase_table.zig", "hgPhaseCoefficients"): "wp5-staged HG phase lane, uncalled and untested; WP5 must test before first use",
    ("src/setup/phase_table.zig", "hgPhaseCoefficientsWithThreshold"): "wp5-staged HG phase lane, uncalled and untested; WP5 must test before first use",
    ("src/setup/phase_table.zig", "maxPhaseCoefficientIndex"): "wp5-staged HG phase lane, uncalled and untested; WP5 must test before first use",
    ("src/spectrum/instrument_average.zig", "applySlitConvolution"): "test oracle for slit-kernel normalization; production reaches it through postprocessSignal in the same file",
    ("src/spectrum/sampling_table.zig", "summarize"): "test oracle for sampling-table shape until runner owns telemetry summary",
    ("src/spectrum/spectrum_run.zig", "gatherProductRows"): "wired same-file stage helper; runO2ASpectrum calls it and tests assert the stage contract",
    ("src/spectrum/spectrum_run.zig", "postprocessAndAssembleProductRows"): "wired same-file stage helper; runO2ASpectrum calls it and tests assert the stage contract",
    ("src/rtm/gauss_angles.zig", "pairIndex"): "transport test oracle for paired Gaussian layout",
    ("src/rtm/layer_reflect_transmit.zig", "renormalizeZeroFourierPhaseKernel"): "transport test oracle for old LABOS phase renormalization",
    ("src/rtm/layer_reflect_transmit.zig", "classifyLayerDoubling"): "transport test oracle for old LABOS layer-doubling branch decisions",
    ("src/rtm/layer_reflect_transmit.zig", "fillSingleScatterReflection"): "transport test oracle for old LABOS single-scatter reflection row",
    ("src/rtm/layer_reflect_transmit.zig", "fillSingleScatterTransmission"): "transport test oracle for old LABOS single-scatter transmission row",
    ("src/rtm/layer_reflect_transmit.zig", "gaussianBlockTrace"): "transport test oracle for old LABOS trace gate",
    ("src/rtm/layer_reflect_transmit.zig", "squareAttenuation"): "transport test oracle for old LABOS layer-doubling primitive",
    ("src/rtm/layer_reflect_transmit.zig", "doubleLayer"): "transport test oracle for old LABOS layer-doubling primitive",
    ("src/rtm/matrix_12x10.zig", "smul"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/rtm/matrix_12x10.zig", "smulInto"): "matrix oracle/helper; production uses narrower known-product Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "smulIntoKnownTraces"): "matrix oracle/helper; production uses narrower known-product Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "smulIntoKnownTracesIfNonzero"): "matrix oracle/helper; production uses narrower known-product Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "qseries"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/rtm/matrix_12x10.zig", "qseriesKnownNonzeroProduct"): "transport test oracle for q-series after retained product",
    ("src/rtm/matrix_12x10.zig", "esmul"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/rtm/matrix_12x10.zig", "semul"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/rtm/matrix_12x10.zig", "matAdd"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/rtm/matrix_12x10.zig", "matAddSemul3"): "matrix oracle/helper; production uses caller-owned Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "smulAddSemul3"): "matrix oracle/helper; production uses caller-owned Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "smulAddSemul3KnownRightTrace"): "matrix oracle/helper; production uses caller-owned Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "semulAdd"): "matrix oracle/helper; production uses caller-owned Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "matAddEsmul3"): "matrix oracle/helper; production uses caller-owned Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "matAddEsmul"): "matrix oracle/helper; production uses caller-owned Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "esmulSemul"): "matrix oracle/helper; production uses caller-owned Into kernels from layer_reflect_transmit",
    ("src/rtm/matrix_12x10.zig", "esmulSemulAdd"): "matrix oracle/helper; production uses caller-owned Into kernels from layer_reflect_transmit",
    ("src/rtm/phase_basis.zig", "minusParitySign"): "transport test oracle for old LABOS Z- parity",
    ("src/rtm/reflectance.zig", "fourierWeight"): "transport test oracle for old Fourier accumulation weight",
    ("src/rtm/reflectance.zig", "fourierTailBreak"): "transport test oracle for old Fourier tail stop rule",
    ("src/rtm/scattering_orders.zig", "setCostTiming"): "cost-timing public hook; wired when the forward path owns worker rows",
    ("src/rtm/scattering_orders.zig", "activeCostTiming"): "cost-timing public hook; wired when the forward path owns worker rows",
    ("src/retrieval/root.zig", "altitudeDerivativeAtPressure"): "wp5-staged pressure-profile hook; retrieval tests pin old finite-difference route before solver wiring",
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
    if path.startswith("src/forward_model/instrumentation/"):
        return False
    if path.startswith("src/instrumentation/"):
        return False
    if path.startswith("src/validation/"):
        return False
    if path == "src/input/o2a_reference/metrics.zig":
        return False
    if path == "src/internal.zig":
        return False
    return True


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
