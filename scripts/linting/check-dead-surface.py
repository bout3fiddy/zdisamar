#!/usr/bin/env python3
"""Fail when counted src pub fns have no production caller and no reason."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


PUB_FN_RE = re.compile(r"^\s*pub\s+(?:inline\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\b", re.M)


ALLOWLIST: dict[tuple[str, str], str] = {
    ("src/cache/profile_line_memory.zig", "supportProfileRow"): "wp4-staged profile-line inspection helper; session runner must wire or demote before WP4 close",
    ("src/cache/solar_irradiance_memory.zig", "put"): "wp4-staged solar cache mutation surface; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "resetValidity"): "wp4-staged worker-memory lifecycle; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "geometryWithStatus"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "dynamicAttenuationBuffer"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "dynamicAttenuationTangentBuffer"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "layerTransmittanceBuffer"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "topToLevelBuffer"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "layerRt"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "layerRtTangent"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "layerPhaseMaxIndices"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "layerEffectiveScatteringSuffixes"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "sourcePhaseMaxIndices"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "ordersWorkArrays"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "phaseRowCache"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "phaseRowValid"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/transport_worker_memory.zig", "fourierPlmBasisWithStatus"): "wp4-staged worker-memory access; session runner must wire before WP4 close",
    ("src/cache/weak_line_cutoff_memory.zig", "replaceFromSupport"): "wp4-staged cutoff cache mutation surface; session runner must wire before WP4 close",
    ("src/common/hashing.zig", "fromBytes"): "wp4-staged exact-f64 key helper; session runner dedup path must wire before WP4 close",
    ("src/common/math/gauss_legendre.zig", "fillDisamarDivPointsInterval"): "wp4-staged sampling quadrature helper; sampling-table runner must wire before WP4 close",
    ("src/common/worker_partition.zig", "FirstWorkerErrorState"): "wp4.5-staged worker kit; multi-worker phases must wire before WP4.5 close",
    ("src/common/worker_partition.zig", "staticRange"): "wp4.5-staged worker kit; dense prefetch worker ranges must wire before WP4.5 close",
    ("src/common/worker_partition.zig", "preferredWorkerCountForCpuCount"): "worker-count oracle for preferredWorkerCount tests; production uses preferredWorkerCount",
    ("src/common/worker_partition.zig", "runWorkers"): "wp4.5-staged worker orchestration; multi-worker phases must wire before WP4.5 close",
    ("src/optics/cia_absorption.zig", "interpolateCoefficients"): "wp4-staged optical helper; production optics runner must wire before WP4 close",
    ("src/optics/rayleigh.zig", "refractiveIndexDryAir"): "wp4-staged optical helper; production optics runner must wire before WP4 close",
    ("src/optics/rayleigh.zig", "depolarizationFactorAir"): "wp4-staged optical helper; production optics runner must wire before WP4 close",
    ("src/root.zig", "deinitO2RunTables"): "wp4-staged root surface; C API ownership tests must wire before WP4 close",
    ("src/root.zig", "runO2A"): "wp4-staged one-shot root surface; C/Python API path must wire before WP4 close",
    ("src/setup/phase_table.zig", "zeroPhaseCoefficients"): "test oracle for phase coefficient storage; keep until HG phase lane is wired",
    ("src/setup/phase_table.zig", "hgPhaseCoefficients"): "wp5-staged HG phase lane, uncalled and untested; WP5 must test before first use",
    ("src/setup/phase_table.zig", "hgPhaseCoefficientsWithThreshold"): "wp5-staged HG phase lane, uncalled and untested; WP5 must test before first use",
    ("src/setup/phase_table.zig", "maxPhaseCoefficientIndex"): "wp5-staged HG phase lane, uncalled and untested; WP5 must test before first use",
    ("src/setup/refresh_profile_lines.zig", "rebuildO2ProfileLineValues"): "wp5-staged refresh path, uncalled and untested; WP5 must test before first use",
    ("src/setup/refresh_tables.zig", "rebuildO2RunTables"): "wp5-staged refresh path, uncalled and untested; WP5 must test before first use",
    ("src/spectrum/instrument_average.zig", "applySignal"): "wp4-staged spectrum postprocess helper; session runner must wire before WP4 close",
    ("src/spectrum/instrument_average.zig", "applySignalDerivative"): "wp4-staged spectrum postprocess helper; session runner must wire before WP4 close",
    ("src/spectrum/instrument_average.zig", "applySlitConvolution"): "wp4-staged spectrum postprocess helper; session runner must wire before WP4 close",
    ("src/spectrum/radiance_wavelengths.zig", "radianceSampleIndexCount"): "wp4-staged spectrum shape helper; session runner must wire before WP4 close",
    ("src/spectrum/sampling_table.zig", "summarize"): "test oracle for sampling-table shape until runner owns telemetry summary",
    ("src/spectrum/solar_lookup.zig", "cachedIrradianceAtWavelengthAssumeCapacity"): "wp4-staged solar lookup helper; session runner must wire before WP4 close",
    ("src/spectrum/solar_lookup.zig", "irradianceSampleCount"): "wp4-staged solar lookup helper; session runner must wire before WP4 close",
    ("src/spectrum/solar_lookup.zig", "interpolateWithinBounds"): "wp4-staged solar lookup helper; session runner must wire before WP4 close",
    ("src/spectrum/spectrum_run.zig", "radianceAtWavelength"): "wp4-staged spectrum runner helper; production runner must wire before WP4 close",
    ("src/spectrum/spectrum_run.zig", "prefetchO2ARadianceRowsSingleWorker"): "wp4-staged prefetch loop; collapse with generic production loop before WP4 close",
    ("src/spectrum/spectrum_run.zig", "prefetchRadianceRowsSingleWorker"): "wp4-staged production prefetch loop; runner must wire before WP4 close",
    ("src/spectrum/spectrum_run.zig", "gatherProductRows"): "wp4-staged spectrum stage helper; production runner must wire before WP4 close",
    ("src/spectrum/spectrum_run.zig", "postprocessAndAssembleProductRows"): "wp4-staged spectrum stage helper; production runner must wire before WP4 close",
    ("src/spectrum/spectrum_run.zig", "preferredRadianceWorkerCount"): "wp4-staged worker kit; production runner must wire before WP4 close",
    ("src/transport/attenuation.zig", "isValidFor"): "wp4-staged transport precondition helper; runner must wire before WP4 close",
    ("src/transport/controls.zig", "supermatrixSize"): "wp4-staged transport shape helper; runner must wire before WP4 close",
    ("src/transport/gauss_angles.zig", "pairIndex"): "transport test oracle for paired Gaussian layout",
    ("src/transport/jacobian_states.zig", "activeStateIndex"): "wp4-staged jacobian helper; runner/API must wire or demote before WP4 close",
    ("src/transport/jacobian_states.zig", "activeStateAt"): "wp4-staged jacobian helper; runner/API must wire or demote before WP4 close",
    ("src/transport/layer_reflect_transmit.zig", "renormalizeZeroFourierPhaseKernel"): "transport test oracle for old LABOS phase renormalization",
    ("src/transport/layer_reflect_transmit.zig", "classifyLayerDoubling"): "transport test oracle for old LABOS layer-doubling branch decisions",
    ("src/transport/layer_reflect_transmit.zig", "fillSingleScatterReflection"): "transport test oracle for old LABOS single-scatter reflection row",
    ("src/transport/layer_reflect_transmit.zig", "fillSingleScatterTransmission"): "transport test oracle for old LABOS single-scatter transmission row",
    ("src/transport/layer_reflect_transmit.zig", "gaussianBlockTrace"): "transport test oracle for old LABOS trace gate",
    ("src/transport/layer_reflect_transmit.zig", "squareAttenuation"): "transport test oracle for old LABOS layer-doubling primitive",
    ("src/transport/layer_reflect_transmit.zig", "doubleLayer"): "transport test oracle for old LABOS layer-doubling primitive",
    ("src/transport/matrix_12x10.zig", "smul"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/transport/matrix_12x10.zig", "smulInto"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "smulIntoKnownTraces"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "smulIntoKnownTracesIfNonzero"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "qseries"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/transport/matrix_12x10.zig", "qseriesKnownNonzeroProduct"): "transport test oracle for q-series after retained product",
    ("src/transport/matrix_12x10.zig", "esmul"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/transport/matrix_12x10.zig", "semul"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/transport/matrix_12x10.zig", "matAdd"): "oracle: main matrix reference form; production uses fused *Into variants; tests assert equality",
    ("src/transport/matrix_12x10.zig", "matAddSemul3"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "smulAddSemul3"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "smulAddSemul3KnownRightTrace"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "semulAdd"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "matAddEsmul3"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "matAddEsmul"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "esmulSemul"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/matrix_12x10.zig", "esmulSemulAdd"): "wp4-staged fused matrix kernel; layer runner must wire before WP4 close",
    ("src/transport/phase_basis.zig", "minusParitySign"): "transport test oracle for old LABOS Z- parity",
    ("src/transport/phase_timing.zig", "setWorkspaceState"): "trace-build public hook; stripped or wired at WP5 cutover",
    ("src/transport/phase_timing.zig", "clearWorkspaceState"): "trace-build public hook; stripped or wired at WP5 cutover",
    ("src/transport/reflectance.zig", "fourierWeight"): "transport test oracle for old Fourier accumulation weight",
    ("src/transport/reflectance.zig", "fourierTailBreak"): "transport test oracle for old Fourier tail stop rule",
    ("src/transport/scattering_orders.zig", "setTracePhaseTiming"): "trace-build public hook; stripped or wired at WP5 cutover",
    ("src/transport/scattering_orders.zig", "activeTracePhaseTiming"): "trace-build public hook; stripped or wired at WP5 cutover",
}


def git_files(patterns: list[str]) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", *patterns],
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
    counted_files = [path for path in tracked_src if counted_src_file(path)]
    search_files = [path for path in tracked_src if search_src_file(path)]
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
