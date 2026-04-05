#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import datetime as dt
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_WAVELENGTHS_NM = (762.29, 765.0, 755.0)
DEFAULT_TRACE_ROOT = REPO_ROOT / "out" / "analysis" / "o2a" / "function_diff"
VENDOR_SOURCE_ROOT = REPO_ROOT / "vendor" / "disamar-fortran"
VENDOR_CONFIG_SOURCE = VENDOR_SOURCE_ROOT / "InputFiles" / "Config_O2_with_CIA.in"
FORTRAN_TRACE_ASSET_DIR = REPO_ROOT / "scripts" / "testing_harness" / "vendor_o2a_function_trace"
FORTRAN_TRACE_MODULE = FORTRAN_TRACE_ASSET_DIR / "o2aFunctionTraceModule.f90"
ZIG_TRACE_CLI = REPO_ROOT / "scripts" / "testing_harness" / "o2a_function_trace.zig"
ZIG_BUILD_OPTIONS = REPO_ROOT / "scripts" / "testing_harness" / "build_options_test_support.zig"
ZIG_VENDOR_SUPPORT = REPO_ROOT / "tests" / "validation" / "o2a_vendor_reflectance_support.zig"
EXPECTED_CSVS = (
    "line_catalog.csv",
    "strong_state.csv",
    "spectroscopy_summary.csv",
    "adaptive_grid.csv",
    "kernel_samples.csv",
    "transport_samples.csv",
    "transport_summary.csv",
)


@dataclass(frozen=True)
class CsvSpec:
    key_columns: tuple[str, ...]
    numeric_columns: tuple[str, ...]


CSV_SPECS: dict[str, CsvSpec] = {
    "line_catalog.csv": CsvSpec(
        key_columns=(
            "center_wavelength_nm",
            "isotope_number",
            "branch_ic1",
            "branch_ic2",
            "rotational_nf",
            "source_row_index",
        ),
        numeric_columns=(
            "source_row_index",
            "gas_index",
            "isotope_number",
            "center_wavelength_nm",
            "center_wavenumber_cm1",
            "line_strength_cm2_per_molecule",
            "air_half_width_nm",
            "temperature_exponent",
            "lower_state_energy_cm1",
            "pressure_shift_nm",
            "line_mixing_coefficient",
            "branch_ic1",
            "branch_ic2",
            "rotational_nf",
        ),
    ),
    "strong_state.csv": CsvSpec(
        key_columns=("pressure_hpa", "temperature_k", "center_wavelength_nm", "strong_index"),
        numeric_columns=(
            "pressure_hpa",
            "temperature_k",
            "strong_index",
            "center_wavelength_nm",
            "center_wavenumber_cm1",
            "sig_moy_cm1",
            "population_t",
            "dipole_t",
            "mod_sig_cm1",
            "half_width_cm1_at_t",
            "line_mixing_coefficient",
        ),
    ),
    "spectroscopy_summary.csv": CsvSpec(
        key_columns=("pressure_hpa", "temperature_k", "wavelength_nm"),
        numeric_columns=(
            "pressure_hpa",
            "temperature_k",
            "wavelength_nm",
            "weak_sigma_cm2_per_molecule",
            "strong_sigma_cm2_per_molecule",
            "line_mixing_sigma_cm2_per_molecule",
            "total_sigma_cm2_per_molecule",
        ),
    ),
    "adaptive_grid.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "interval_kind", "interval_start_nm", "interval_end_nm", "division_count"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "source_center_wavelength_nm",
            "interval_start_nm",
            "interval_end_nm",
            "division_count",
        ),
    ),
    "kernel_samples.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm"),
        numeric_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "weight"),
    ),
    "transport_samples.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "radiance",
            "irradiance",
            "weight",
        ),
    ),
    "transport_summary.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm",),
        numeric_columns=("nominal_wavelength_nm", "final_radiance", "final_irradiance", "final_reflectance"),
    ),
}


def main() -> int:
    args = parse_args()
    wavelengths_nm = parse_wavelengths(args.wavelengths)
    trace_root = resolve_trace_root(args.trace_root)
    vendor_workspace = trace_root / "vendor_workspace"
    fortran_root = trace_root / "fortran"
    zig_root = trace_root / "zig"
    diff_root = trace_root / "diff"

    if trace_root.exists():
        shutil.rmtree(trace_root)
    for path in (trace_root, fortran_root, zig_root, diff_root):
        path.mkdir(parents=True, exist_ok=True)

    copy_vendor_workspace(vendor_workspace)
    try:
        prepare_vendor_workspace(vendor_workspace)
        build_vendor_workspace(vendor_workspace)
        run_vendor_trace(vendor_workspace, fortran_root, wavelengths_nm)
        merge_fortran_spectroscopy_summary(fortran_root)
        run_zig_trace(trace_root, wavelengths_nm, args.zig_optimize)
        canonicalize_side(fortran_root)
        canonicalize_side(zig_root)
        verify_expected_csvs(fortran_root, "fortran")
        verify_expected_csvs(zig_root, "zig")
        write_diff_summary(fortran_root, zig_root, diff_root)
    finally:
        if not args.keep_vendor_workspace and vendor_workspace.exists():
            shutil.rmtree(vendor_workspace)

    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare minimal O2A function outputs between vendored DISAMAR and zdisamar.")
    parser.add_argument("--wavelengths", default=",".join(str(value) for value in DEFAULT_WAVELENGTHS_NM))
    parser.add_argument("--trace-root", default=None)
    parser.add_argument(
        "--zig-optimize",
        choices=("Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall"),
        default="Debug",
        help="Optimization mode for the Zig trace CLI. Use ReleaseFast for a practical full transport trace run.",
    )
    parser.add_argument("--keep-vendor-workspace", action="store_true")
    return parser.parse_args()


def parse_wavelengths(raw: str) -> list[float]:
    values: list[float] = []
    for part in raw.split(","):
        text = part.strip()
        if not text:
            continue
        values.append(float(text))
    return values or list(DEFAULT_WAVELENGTHS_NM)


def resolve_trace_root(raw: str | None) -> Path:
    if raw:
        return Path(raw).expanduser().resolve()
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return DEFAULT_TRACE_ROOT / run_id


def copy_vendor_workspace(destination: Path) -> None:
    if not VENDOR_SOURCE_ROOT.exists():
        raise RuntimeError(f"Missing vendored DISAMAR source tree at {VENDOR_SOURCE_ROOT}")
    shutil.copytree(VENDOR_SOURCE_ROOT, destination)


def prepare_vendor_workspace(vendor_workspace: Path) -> None:
    shutil.copy2(FORTRAN_TRACE_MODULE, vendor_workspace / "src" / FORTRAN_TRACE_MODULE.name)
    patch_makefile(vendor_workspace / "src" / "makefile")
    patch_hitran_module(vendor_workspace / "src" / "HITRANModule.f90")
    patch_disamar_module(vendor_workspace / "src" / "DISAMARModule.f90")
    patch_radiance_module(vendor_workspace / "src" / "radianceIrradianceModule.f90")
    shutil.copy2(VENDOR_CONFIG_SOURCE, vendor_workspace / "Config.in")


def build_vendor_workspace(vendor_workspace: Path) -> None:
    run_command(["make", "install"], cwd=vendor_workspace / "src")


def run_vendor_trace(vendor_workspace: Path, fortran_root: Path, wavelengths_nm: list[float]) -> None:
    env = os.environ.copy()
    env["ZDISAMAR_O2A_TRACE_ROOT"] = str(fortran_root)
    env["ZDISAMAR_O2A_TRACE_WAVELENGTHS_NM"] = ",".join(format_wavelength(value) for value in wavelengths_nm)
    run_command([str(vendor_workspace / "Disamar.exe")], cwd=vendor_workspace, env=env)


def run_zig_trace(trace_root: Path, wavelengths_nm: list[float], zig_optimize: str) -> None:
    command = [
        "zig",
        "run",
        "-O",
        zig_optimize,
        "--dep",
        "zdisamar",
        "--dep",
        "zdisamar_internal",
        "--dep",
        "vendor_o2a_trace_support",
        f"-Mroot={ZIG_TRACE_CLI}",
        "--dep",
        "zdisamar",
        "--dep",
        "zdisamar_internal",
        f"-Mvendor_o2a_trace_support={ZIG_VENDOR_SUPPORT}",
        "--dep",
        "build_options",
        f"-Mzdisamar={REPO_ROOT / 'src' / 'root.zig'}",
        f"-Mbuild_options={ZIG_BUILD_OPTIONS}",
        "--dep",
        "zdisamar",
        f"-Mzdisamar_internal={REPO_ROOT / 'src' / 'internal.zig'}",
        "--",
        "--trace-root",
        str(trace_root),
        "--wavelengths",
        ",".join(format_wavelength(value) for value in wavelengths_nm),
    ]
    run_command(command, cwd=REPO_ROOT)


def merge_fortran_spectroscopy_summary(fortran_root: Path) -> None:
    weak_path = fortran_root / "spectroscopy_weak_raw.csv"
    strong_path = fortran_root / "spectroscopy_strong_raw.csv"
    output_path = fortran_root / "spectroscopy_summary.csv"
    if not weak_path.exists() or not strong_path.exists():
        raise RuntimeError("Missing raw Fortran spectroscopy trace files")

    merged: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in read_csv_rows(weak_path):
        key = (row["pressure_hpa"], row["temperature_k"], row["wavelength_nm"])
        merged[key] = {
            "pressure_hpa": row["pressure_hpa"],
            "temperature_k": row["temperature_k"],
            "wavelength_nm": row["wavelength_nm"],
            "weak_sigma_cm2_per_molecule": row["weak_sigma_cm2_per_molecule"],
            "strong_sigma_cm2_per_molecule": "0.0",
            "line_mixing_sigma_cm2_per_molecule": "0.0",
            "total_sigma_cm2_per_molecule": row["weak_sigma_cm2_per_molecule"],
        }

    for row in read_csv_rows(strong_path):
        key = (row["pressure_hpa"], row["temperature_k"], row["wavelength_nm"])
        record = merged.setdefault(
            key,
            {
                "pressure_hpa": row["pressure_hpa"],
                "temperature_k": row["temperature_k"],
                "wavelength_nm": row["wavelength_nm"],
                "weak_sigma_cm2_per_molecule": "0.0",
                "strong_sigma_cm2_per_molecule": "0.0",
                "line_mixing_sigma_cm2_per_molecule": "0.0",
                "total_sigma_cm2_per_molecule": "0.0",
            },
        )
        record["strong_sigma_cm2_per_molecule"] = row["strong_sigma_cm2_per_molecule"]
        record["line_mixing_sigma_cm2_per_molecule"] = row["line_mixing_sigma_cm2_per_molecule"]
        total = parse_float(record["weak_sigma_cm2_per_molecule"]) + parse_float(row["strong_sigma_cm2_per_molecule"]) + parse_float(row["line_mixing_sigma_cm2_per_molecule"])
        record["total_sigma_cm2_per_molecule"] = repr(total)

    fieldnames = list(CSV_SPECS["spectroscopy_summary.csv"].numeric_columns)
    rows = list(merged.values())
    sort_rows(rows, CSV_SPECS["spectroscopy_summary.csv"])
    write_csv_rows(output_path, fieldnames, rows)
    weak_path.unlink()
    strong_path.unlink()


def canonicalize_side(side_root: Path) -> None:
    for file_name in EXPECTED_CSVS:
        path = side_root / file_name
        spec = CSV_SPECS[file_name]
        rows = read_csv_rows(path)
        sort_rows(rows, spec)
        write_csv_rows(path, list(rows[0].keys()) if rows else read_csv_headers(path), rows)


def verify_expected_csvs(side_root: Path, label: str) -> None:
    missing = [name for name in EXPECTED_CSVS if not (side_root / name).exists()]
    if missing:
        raise RuntimeError(f"Missing {label} CSVs: {', '.join(missing)}")


def write_diff_summary(fortran_root: Path, zig_root: Path, diff_root: Path) -> None:
    summary_path = diff_root / "summary.txt"
    lines: list[str] = []
    for file_name in EXPECTED_CSVS:
        lines.append(file_name)
        comparison = compare_csv_files(
            fortran_root / file_name,
            zig_root / file_name,
            CSV_SPECS[file_name],
        )
        for line in comparison:
            lines.append(f"  {line}")
        lines.append("")
    summary_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def compare_csv_files(fortran_path: Path, zig_path: Path, spec: CsvSpec) -> list[str]:
    fortran_headers = read_csv_headers(fortran_path)
    zig_headers = read_csv_headers(zig_path)
    if fortran_headers != zig_headers:
        raise RuntimeError(f"Schema mismatch for {fortran_path.name}: {fortran_headers} != {zig_headers}")

    fortran_rows = read_csv_rows(fortran_path)
    zig_rows = read_csv_rows(zig_path)
    output = [f"rows: fortran={len(fortran_rows)} zig={len(zig_rows)}"]
    if len(fortran_rows) != len(zig_rows):
        output.append("row-count mismatch")

    paired_count = min(len(fortran_rows), len(zig_rows))
    first_key_mismatch = None
    for index in range(paired_count):
        if row_key(fortran_rows[index], spec) != row_key(zig_rows[index], spec):
            first_key_mismatch = index
            break
    if first_key_mismatch is not None:
        output.append(
            "first key mismatch at row "
            f"{first_key_mismatch + 1}: "
            f"fortran={row_key(fortran_rows[first_key_mismatch], spec)} "
            f"zig={row_key(zig_rows[first_key_mismatch], spec)}"
        )
    else:
        output.append("keys/order: match")

    for column in spec.numeric_columns:
        max_abs_diff = 0.0
        first_numeric_mismatch = None
        for index in range(paired_count):
            left = parse_float(fortran_rows[index][column])
            right = parse_float(zig_rows[index][column])
            diff = numeric_difference(left, right)
            if diff > max_abs_diff:
                max_abs_diff = diff
            if first_numeric_mismatch is None and diff > 0.0:
                first_numeric_mismatch = (index, left, right)
        if first_numeric_mismatch is None:
            output.append(f"{column}: max_abs_diff=0.0 first_diff=none")
        else:
            index, left, right = first_numeric_mismatch
            output.append(
                f"{column}: max_abs_diff={max_abs_diff:.12e} "
                f"first_diff_row={index + 1} fortran={left!r} zig={right!r}"
            )
    return output


def sort_rows(rows: list[dict[str, str]], spec: CsvSpec) -> None:
    rows.sort(key=lambda row: tuple(sortable_value(row[column]) for column in spec.key_columns))


def row_key(row: dict[str, str], spec: CsvSpec) -> tuple[object, ...]:
    return tuple(sortable_value(row[column]) for column in spec.key_columns)


def sortable_value(raw: str) -> object:
    try:
        value = parse_float(raw)
    except ValueError:
        return (0, raw)
    if math.isnan(value):
        return (1, 0.0)
    return (0, value)


def parse_float(raw: str) -> float:
    text = raw.strip()
    if text.lower() == "nan":
        return math.nan
    return float(text)


def numeric_difference(left: float, right: float) -> float:
    if math.isnan(left) and math.isnan(right):
        return 0.0
    if math.isnan(left) or math.isnan(right):
        return math.inf
    return abs(left - right)


def read_csv_headers(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        return next(reader)


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv_rows(path: Path, fieldnames: list[str], rows: Iterable[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def patch_makefile(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "    dataStructures.f90 \\\n    staticDataModule.f90 \\\n",
        "    dataStructures.f90 \\\n    o2aFunctionTraceModule.f90 \\\n    staticDataModule.f90 \\\n",
        path,
    )
    text = replace_once(
        text,
        "    dataStructures.o \\\n    staticDataModule.o \\\n",
        "    dataStructures.o \\\n    o2aFunctionTraceModule.o \\\n    staticDataModule.o \\\n",
        path,
    )
    text = replace_once(
        text,
        "dataStructures.o: dataStructures.f90\n\t$(F90) -c $(F90FLAGS) dataStructures.f90 -o dataStructures.o\n\n",
        "dataStructures.o: dataStructures.f90\n\t$(F90) -c $(F90FLAGS) dataStructures.f90 -o dataStructures.o\n\n"
        "o2aFunctionTraceModule.o: o2aFunctionTraceModule.f90\n\t$(F90) -c $(F90FLAGS) o2aFunctionTraceModule.f90 -o o2aFunctionTraceModule.o\n\n",
        path,
    )
    text = replace_once(
        text,
        "HITRANModule.o: HITRANModule.f90 \\\n                 dataStructures.o\n",
        "HITRANModule.o: HITRANModule.f90 \\\n                 dataStructures.o \\\n                 o2aFunctionTraceModule.o\n",
        path,
    )
    text = replace_once(
        text,
        "radianceIrradianceModule.o: radianceIrradianceModule.f90 \\\n                          dataStructures.o \\\n",
        "radianceIrradianceModule.o: radianceIrradianceModule.f90 \\\n                          dataStructures.o \\\n                          o2aFunctionTraceModule.o \\\n",
        path,
    )
    text = replace_once(
        text,
        "DISAMARModule.o: DISAMARModule.f90 \\\n              dataStructures.o \\\n",
        "DISAMARModule.o: DISAMARModule.f90 \\\n              dataStructures.o \\\n              o2aFunctionTraceModule.o \\\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def patch_hitran_module(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  use mathTools\n",
        "  use mathTools\n  use o2aFunctionTraceModule, only: o2a_trace_line_catalog_row, o2a_trace_convtp_state, o2a_trace_weak_spectroscopy, o2a_trace_strong_spectroscopy\n",
        path,
    )
    text = replace_once(
        text,
        "          hitranS%delt(i)    = delt_read\n\n          i = i + 1\n",
        "          hitranS%delt(i)    = delt_read\n"
        "          if ( filterStrongLinesO2A .and. (gasIndex_read == 7) ) then\n"
        "            call o2a_trace_line_catalog_row(i, gasIndex_read, isotope_read, Sig_read, S_read, gam_read, E_read, bet_read, delt_read, ic1_read, ic2_read, Nf_read)\n"
        "          end if\n\n"
        "          i = i + 1\n",
        path,
    )
    text = replace_once(
        text,
        "      ! Computation of the first order line-coupling coefficients\n"
        "      do iLine = 1, SDFS%nLines\n"
        "        YY=0.D0\n"
        "        do iLineP = 1, SDFS%nLines\n"
        "          if (iLine.ne.iLineP.and.SDFS%modSigLines(iLine).ne.SDFS%modSigLines(iLineP)) then\n"
        "            YY = YY + 2*SDFS%Dipo(iLineP)/SDFS%Dipo(iLine)* WW0(iLineP,iLine) &\n"
        "              /(SDFS%modSigLines(iLine) - SDFS%modSigLines(iLineP))\n"
        "          endif\n"
        "        end do\n"
        "        SDFS%YT(iLine) = P*YY\n"
        "      end do\n\n"
        "    end subroutine ConvTP\n",
        "      ! Computation of the first order line-coupling coefficients\n"
        "      do iLine = 1, SDFS%nLines\n"
        "        YY=0.D0\n"
        "        do iLineP = 1, SDFS%nLines\n"
        "          if (iLine.ne.iLineP.and.SDFS%modSigLines(iLine).ne.SDFS%modSigLines(iLineP)) then\n"
        "            YY = YY + 2*SDFS%Dipo(iLineP)/SDFS%Dipo(iLine)* WW0(iLineP,iLine) &\n"
        "              /(SDFS%modSigLines(iLine) - SDFS%modSigLines(iLineP))\n"
        "          endif\n"
        "        end do\n"
        "        SDFS%YT(iLine) = P*YY\n"
        "      end do\n\n"
        "      call o2a_trace_convtp_state(T, P, SigMoy, SDFS%nLines, SDFS%sigLines, SDFS%PopuT, SDFS%Dipo, SDFS%modSigLines, SDFS%HWT, SDFS%YT)\n\n"
        "    end subroutine ConvTP\n",
        path,
    )
    text = replace_once(
        text,
        "      do iLine = 1, nLines\n"
        "        HWT  = hitranS%gam(iLine) * (T0/T)**hitranS%bet(iLine)\n"
        "        Lsig = hitranS%sig(iLine)+ hitranS%delt(iLine) * P\n"
        "! JdH turn off pressure shift\n"
        "!       Lsig = hitranS%sig(iLine)\n"
        "        LS   = hitranS%S(iLine) * rapQ(hitranS%isotope(iLine)) &\n"
        "              * exp(hc_kB * hitranS%E(iLine) * (1/T0-1/T) ) / Lsig\n"
        "        LS   = LS * 0.1013d0 / k_Boltzmann / T &\n"
        "              /( 1.0d0 - exp( -hc_kB * Lsig /T0 ) )\n"
        "        indexMinloc = minloc(abs(waveNumber(:) - Lsig - cutoff))\n"
        "        startSig    = indexMinloc(1)\n"
        "        indexMinloc = minloc(abs(waveNumber(:) - Lsig + cutoff))\n"
        "        endSig   = indexMinloc(1)\n"
        "        GamD    = DopplerWidth(T, Lsig, hitranS%molWeight(hitranS%isotope(iLine)))\n"
        "        Cte     = sqrt(log(2.0d0))/GamD\n"
        "        Cte1    = Cte/sqrt(pi)\n"
        "        do iSig = startSig, endSig\n"
        "          SigC = waveNumber(iSig)\n"
        "          Cte2=SigC*(1.0d0-exp(-hc_kB*SigC/T))\n"
        "          ! Complex Probability Function for the \"Real\" Q-Lines\n"
        "          XX = ( LSig - SigC ) * Cte\n"
        "          YY = HWT * P * Cte\n"
        "          Call CPF(errS, XX,YY,WR,WI)\n"
        "          if (errorCheck(errS)) return\n"
        "          ! Voigt absorption coefficient\n"
        "          aa = Cte1 * P * LS * WR * Cte2               ! aa is the volume absorption coefficient\n"
        "                                                       ! for a volume mixing ratio of 1.0\n"
        "          aa = aa * T * 1.380658d-19 / P / 1013.25d0   ! aa is now the absorption cross section in cm2/molecule\n"
        "          absXsec(iSig) = absXsec(iSig) + aa\n"
        "        end do ! iSig\n"
        "      end do ! iLine\n\n"
        "    end subroutine CalculatAbsXsec\n",
        "      do iLine = 1, nLines\n"
        "        HWT  = hitranS%gam(iLine) * (T0/T)**hitranS%bet(iLine)\n"
        "        Lsig = hitranS%sig(iLine)+ hitranS%delt(iLine) * P\n"
        "! JdH turn off pressure shift\n"
        "!       Lsig = hitranS%sig(iLine)\n"
        "        LS   = hitranS%S(iLine) * rapQ(hitranS%isotope(iLine)) &\n"
        "              * exp(hc_kB * hitranS%E(iLine) * (1/T0-1/T) ) / Lsig\n"
        "        LS   = LS * 0.1013d0 / k_Boltzmann / T &\n"
        "              /( 1.0d0 - exp( -hc_kB * Lsig /T0 ) )\n"
        "        indexMinloc = minloc(abs(waveNumber(:) - Lsig - cutoff))\n"
        "        startSig    = indexMinloc(1)\n"
        "        indexMinloc = minloc(abs(waveNumber(:) - Lsig + cutoff))\n"
        "        endSig   = indexMinloc(1)\n"
        "        GamD    = DopplerWidth(T, Lsig, hitranS%molWeight(hitranS%isotope(iLine)))\n"
        "        Cte     = sqrt(log(2.0d0))/GamD\n"
        "        Cte1    = Cte/sqrt(pi)\n"
        "        do iSig = startSig, endSig\n"
        "          SigC = waveNumber(iSig)\n"
        "          Cte2=SigC*(1.0d0-exp(-hc_kB*SigC/T))\n"
        "          ! Complex Probability Function for the \"Real\" Q-Lines\n"
        "          XX = ( LSig - SigC ) * Cte\n"
        "          YY = HWT * P * Cte\n"
        "          Call CPF(errS, XX,YY,WR,WI)\n"
        "          if (errorCheck(errS)) return\n"
        "          ! Voigt absorption coefficient\n"
        "          aa = Cte1 * P * LS * WR * Cte2               ! aa is the volume absorption coefficient\n"
        "                                                       ! for a volume mixing ratio of 1.0\n"
        "          aa = aa * T * 1.380658d-19 / P / 1013.25d0   ! aa is now the absorption cross section in cm2/molecule\n"
        "          absXsec(iSig) = absXsec(iSig) + aa\n"
        "        end do ! iSig\n"
        "      end do ! iLine\n\n"
        "      call o2a_trace_weak_spectroscopy(T, P, size(wavel), wavel, absXsec)\n\n"
        "    end subroutine CalculatAbsXsec\n",
        path,
    )
    text = replace_once(
        text,
        "       nO2 = 1013.25 * P / T / 1.380658d-19  ! in molecules cm-3; assumed vmr = 1.0\n"
        "       Xsec(:)    =  abs_no_LM(:) / nO2\n"
        "       Xsec_LM(:) = ( abs_with_LM(:) - abs_no_LM(:) ) / nO2\n\n"
        "    end subroutine CalculateLineMixingXsec\n",
        "       nO2 = 1013.25 * P / T / 1.380658d-19  ! in molecules cm-3; assumed vmr = 1.0\n"
        "       Xsec(:)    =  abs_no_LM(:) / nO2\n"
        "       Xsec_LM(:) = ( abs_with_LM(:) - abs_no_LM(:) ) / nO2\n\n"
        "       call o2a_trace_strong_spectroscopy(T, P, size(waveNumbers), waveNumbers, Xsec, Xsec_LM)\n\n"
        "    end subroutine CalculateLineMixingXsec\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def patch_disamar_module(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  use ramansspecs,              only: NumberRamanLines, RamanLinesScatWavel\n",
        "  use ramansspecs,              only: NumberRamanLines, RamanLinesScatWavel\n"
        "  use o2aFunctionTraceModule,   only: o2a_trace_store_intervals\n",
        path,
    )
    text = replace_once(
        text,
        "     real(8), allocatable :: wavelBand(:)        ! (nwavel) full band - not accounting for excluded parts\n"
        "     real(8), allocatable :: wavelBandWeight(:)  ! (nwavel) weights for full band - not accounting for excluded parts\n\n"
        "     integer              :: iwave, nlines, iinterval, index, ipair\n"
        "     integer              :: iGauss, nGauss, nGaussMax, nGaussMin\n"
        "     integer              :: iTrace\n",
        "     real(8), allocatable :: wavelBand(:)        ! (nwavel) full band - not accounting for excluded parts\n"
        "     real(8), allocatable :: wavelBandWeight(:)  ! (nwavel) weights for full band - not accounting for excluded parts\n"
        "     logical, allocatable :: intervalIsStrong(:)\n"
        "     real(8), allocatable :: intervalSourceCenter(:)\n"
        "     integer, allocatable :: intervalDivisionCount(:)\n\n"
        "     integer              :: iwave, nlines, iinterval, index, ipair\n"
        "     integer              :: iGauss, nGauss, nGaussMax, nGaussMin\n"
        "     integer              :: iTrace\n"
        "     logical              :: intervalAddedFromStrong\n"
        "     real(8)              :: intervalStrongCenter\n",
        path,
    )
    text = replace_once(
        text,
        "     allocate ( intervalBoundaries(0:nlines), STAT = allocStatus )\n"
        "     if ( allocStatus /= 0 ) then\n"
        "       call logDebug('FATAL ERROR: allocation failed')\n"
        "       call logDebug('for intervalBoundaries')\n"
        "       call logDebug('in subroutine setupHRWavelengthGrid')\n"
        "       call logDebug('in program DISAMAR - file main_DISAMAR.f90')\n"
        "       call mystop(errS, 'stopped because allocation failed')\n"
        "       if (errorCheck(errS)) return\n"
        "     end if\n\n"
        "     ! fill values\n",
        "     allocate ( intervalBoundaries(0:nlines), STAT = allocStatus )\n"
        "     if ( allocStatus /= 0 ) then\n"
        "       call logDebug('FATAL ERROR: allocation failed')\n"
        "       call logDebug('for intervalBoundaries')\n"
        "       call logDebug('in subroutine setupHRWavelengthGrid')\n"
        "       call logDebug('in program DISAMAR - file main_DISAMAR.f90')\n"
        "       call mystop(errS, 'stopped because allocation failed')\n"
        "       if (errorCheck(errS)) return\n"
        "     end if\n"
        "     allocStatus = 0\n"
        "     allocate ( intervalIsStrong(1:nlines), intervalSourceCenter(1:nlines), intervalDivisionCount(1:nlines), STAT = allocStatus )\n"
        "     if ( allocStatus /= 0 ) then\n"
        "       call logDebug('FATAL ERROR: allocation failed')\n"
        "       call logDebug('for interval trace arrays')\n"
        "       call logDebug('in subroutine setupHRWavelengthGrid')\n"
        "       call logDebug('in program DISAMAR - file main_DISAMAR.f90')\n"
        "       call mystop(errS, 'stopped because allocation failed')\n"
        "       if (errorCheck(errS)) return\n"
        "     end if\n"
        "     intervalIsStrong(:) = .false.\n"
        "     intervalSourceCenter(:) = 0.0d0\n"
        "     intervalDivisionCount(:) = 0\n\n"
        "     ! fill values\n",
        path,
    )
    text = replace_once(
        text,
        "     do\n"
        "       nlines = nlines + 1\n"
        "       newWavel = wavel + FWHM\n"
        "       do iTrace = 1, nTrace\n"
        "         do iwave = 1,  boundariesTraceS(iTrace)%numBoundaries\n"
        "           if ( ( boundariesTraceS(iTrace)%boundaries(iwave) > wavel    ) .and.  &\n"
        "                ( boundariesTraceS(iTrace)%boundaries(iwave) < newWavel ) ) then\n"
        "              newWavel = boundariesTraceS(iTrace)%boundaries(iwave)\n"
        "           end if\n"
        "         end do ! iwave\n"
        "       end do ! iTrace\n"
        "       wavel = newWavel\n"
        "       intervalBoundaries(nlines) = wavel\n"
        "       if ( wavel > waveEnd ) exit\n"
        "     end do\n",
        "     do\n"
        "       nlines = nlines + 1\n"
        "       intervalAddedFromStrong = .false.\n"
        "       intervalStrongCenter = 0.0d0\n"
        "       newWavel = wavel + FWHM\n"
        "       do iTrace = 1, nTrace\n"
        "         do iwave = 1,  boundariesTraceS(iTrace)%numBoundaries\n"
        "           if ( ( boundariesTraceS(iTrace)%boundaries(iwave) > wavel    ) .and.  &\n"
        "                ( boundariesTraceS(iTrace)%boundaries(iwave) < newWavel ) ) then\n"
        "              newWavel = boundariesTraceS(iTrace)%boundaries(iwave)\n"
        "              intervalAddedFromStrong = .true.\n"
        "              intervalStrongCenter = boundariesTraceS(iTrace)%boundaries(iwave)\n"
        "           end if\n"
        "         end do ! iwave\n"
        "       end do ! iTrace\n"
        "       wavel = newWavel\n"
        "       intervalBoundaries(nlines) = wavel\n"
        "       intervalIsStrong(nlines) = intervalAddedFromStrong\n"
        "       intervalSourceCenter(nlines) = intervalStrongCenter\n"
        "       if ( wavel > waveEnd ) exit\n"
        "     end do\n",
        path,
    )
    text = replace_once(
        text,
        "       nGauss = max( nGaussMin, nint( nGaussMax * dw / maxInterval ) )\n"
        "       if (nGauss >  nGaussMax ) nGauss =  nGaussMax\n"
        "       do iGauss = 1, nGauss\n"
        "         index = index + 1\n"
        "       end do\n",
        "       nGauss = max( nGaussMin, nint( nGaussMax * dw / maxInterval ) )\n"
        "       if (nGauss >  nGaussMax ) nGauss =  nGaussMax\n"
        "       intervalDivisionCount(iinterval) = nGauss\n"
        "       do iGauss = 1, nGauss\n"
        "         index = index + 1\n"
        "       end do\n",
        path,
    )
    text = replace_once(
        text,
        "     if ( verbose ) then\n",
        "     call o2a_trace_store_intervals(size(intervalBoundaries) - 1, intervalBoundaries, intervalIsStrong, intervalSourceCenter, intervalDivisionCount)\n\n"
        "     if ( verbose ) then\n",
        path,
    )
    text = replace_once(
        text,
        "     deallocate( intervalBoundaries, x0, w0, wavelBand, wavelBandWeight, STAT = deallocStatus )\n",
        "     deallocate( intervalBoundaries, x0, w0, wavelBand, wavelBandWeight, intervalIsStrong, intervalSourceCenter, intervalDivisionCount, STAT = deallocStatus )\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def patch_radiance_module(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  use ramansspecs,          only: ConvoluteSpecRaman, ConvoluteSpecRamanMS, TotalRamanXsecScatWavel, RayXsec\n",
        "  use ramansspecs,          only: ConvoluteSpecRaman, ConvoluteSpecRamanMS, TotalRamanXsecScatWavel, RayXsec\n"
        "  use o2aFunctionTraceModule, only: o2a_trace_emit_kernel_and_transport, o2a_trace_transport_summary\n",
        path,
    )
    text = replace_once(
        text,
        "        do index = startIndex, endIndex\n"
        "          slitfunctionValues(index) = wavelHRS%weight(index) * slitfunctionValues(index)\n"
        "        end do\n"
        "        do iSV = 1, dimSV\n",
        "        do index = startIndex, endIndex\n"
        "          slitfunctionValues(index) = wavelHRS%weight(index) * slitfunctionValues(index)\n"
        "        end do\n"
        "        call o2a_trace_emit_kernel_and_transport(wavelInstrS%wavel(iwave), startIndex, endIndex, wavelHRS%wavel, slitfunctionValues, earthRadianceS%rad_HR(1,:), solarIrradianceS%solIrrHR)\n"
        "        do iSV = 1, dimSV\n",
        path,
    )
    text = replace_once(
        text,
        "        retrS%reflMeas(index)  = earthRadianceSimS  (iband)%rad_meas(1,iwave) &\n"
        "                               / solarIrradianceSimS(iband)%solIrrMeas(iwave)\n"
        "        retrS%reflNoiseError(index) = retrS%reflMeas(index) * sqrt(  &\n",
        "        retrS%reflMeas(index)  = earthRadianceSimS  (iband)%rad_meas(1,iwave) &\n"
        "                               / solarIrradianceSimS(iband)%solIrrMeas(iwave)\n"
        "        call o2a_trace_transport_summary(wavelInstrSimS(iband)%wavel(iwave), earthRadianceSimS(iband)%rad_meas(1,iwave), solarIrradianceSimS(iband)%solIrrMeas(iwave), retrS%reflMeas(index))\n"
        "        retrS%reflNoiseError(index) = retrS%reflMeas(index) * sqrt(  &\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def run_command(command: list[str], cwd: Path, env: dict[str, str] | None = None) -> None:
    subprocess.run(command, cwd=cwd, env=env, check=True)


def replace_once(text: str, old: str, new: str, path: Path) -> str:
    if old not in text:
        raise RuntimeError(f"Failed to patch {path}: expected snippet not found")
    return text.replace(old, new, 1)


def format_wavelength(value: float) -> str:
    return f"{value:.8f}".rstrip("0").rstrip(".")


if __name__ == "__main__":
    sys.exit(main())
