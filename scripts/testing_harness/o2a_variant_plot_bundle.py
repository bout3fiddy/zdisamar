#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_METRICS = REPO_ROOT / "validation" / "compatibility" / "o2a_plots" / "comparison_metrics.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate an O2A comparison bundle for a perturbed DISAMAR/zdisamar "
            "geometry, aerosol, and surface-albedo case."
        )
    )
    parser.add_argument(
        "--vendor-root",
        default="vendor/disamar-fortran",
        help="Vendored DISAMAR root directory.",
    )
    parser.add_argument(
        "--base-vendor-config",
        default="vendor/disamar-fortran/InputFiles/Config_O2_with_CIA.in",
        help="Base DISAMAR config file to perturb.",
    )
    parser.add_argument(
        "--base-yaml",
        default="data/examples/vendor_o2a_parity.yaml",
        help="Base zdisamar parity YAML file to perturb.",
    )
    parser.add_argument(
        "--profile-exe",
        default="zig-out/bin/zdisamar-o2a-forward-profile",
        help="Built zdisamar O2A profile executable.",
    )
    parser.add_argument(
        "--output-root",
        default="out/analysis/o2a/variant_plot_bundle",
        help="Root directory for disposable variant artifacts.",
    )
    parser.add_argument(
        "--canonical-command",
        default="zig build o2a-variant-plot-bundle",
        help="Command recorded in the generated plot manifest.",
    )
    parser.add_argument("--solar-zenith-deg", type=float, default=47.0)
    parser.add_argument("--viewing-zenith-deg", type=float, default=18.0)
    parser.add_argument("--relative-azimuth-deg", type=float, default=80.0)
    parser.add_argument("--surface-albedo", type=float, default=0.11)
    parser.add_argument("--aerosol-optical-depth-550-nm", type=float, default=0.12)
    parser.add_argument("--aerosol-single-scatter-albedo", type=float, default=0.93)
    parser.add_argument("--aerosol-asymmetry-factor", type=float, default=0.55)
    parser.add_argument("--aerosol-angstrom-exponent", type=float, default=1.2)
    return parser.parse_args()


def stable_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return resolved.as_posix()


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"expected exactly one occurrence of {old!r}, found {count}")
    return text.replace(old, new, 1)


def write_variant_vendor_config(base_path: Path, output_path: Path, args: argparse.Namespace) -> None:
    text = base_path.read_text()
    solar_azimuth_deg = 180.0
    instrument_azimuth_deg = solar_azimuth_deg - args.relative_azimuth_deg

    replacements = {
        "solar_zenith_angle_sim        60.0d0  (in degree)": (
            f"solar_zenith_angle_sim        {args.solar_zenith_deg:.1f}d0  (in degree)"
        ),
        "solar_zenith_angle_retr       60.0d0  (in degree)": (
            f"solar_zenith_angle_retr       {args.solar_zenith_deg:.1f}d0  (in degree)"
        ),
        "instrument_nadir_angle_sim    30.0d0  (in degree)": (
            f"instrument_nadir_angle_sim    {args.viewing_zenith_deg:.1f}d0  (in degree)"
        ),
        "instrument_nadir_angle_retr   30.0d0  (in degree)": (
            f"instrument_nadir_angle_retr   {args.viewing_zenith_deg:.1f}d0  (in degree)"
        ),
        "instrument_azimuth_angle_sim  60.0d0  (in degree)": (
            f"instrument_azimuth_angle_sim  {instrument_azimuth_deg:.1f}d0  (in degree)"
        ),
        "instrument_azimuth_angle_retr 60.0d0  (in degree)": (
            f"instrument_azimuth_angle_retr {instrument_azimuth_deg:.1f}d0  (in degree)"
        ),
        "surfAlbedo             0.200    ( surface albedo at the wavelength nodes )": (
            f"surfAlbedo             {args.surface_albedo:.3f}    ( surface albedo at the wavelength nodes )"
        ),
        "surfAlbedo             0.200    ( a priori surface albedo at the wavelength nodes )": (
            f"surfAlbedo             {args.surface_albedo:.3f}    ( a priori surface albedo at the wavelength nodes )"
        ),
        "opticalThickness                2             0.3": (
            f"opticalThickness                2             {args.aerosol_optical_depth_550_nm:.3f}"
        ),
        "angstromCoefficient             2             0.0": (
            f"angstromCoefficient             2             {args.aerosol_angstrom_exponent:.3f}"
        ),
        "singleScatteringAlbedo          2             1.0": (
            f"singleScatteringAlbedo          2             {args.aerosol_single_scatter_albedo:.3f}"
        ),
        "HGparameter_g                   2             0.7": (
            f"HGparameter_g                   2             {args.aerosol_asymmetry_factor:.3f}"
        ),
        "opticalThickness                2              0.3          1.0": (
            f"opticalThickness                2              {args.aerosol_optical_depth_550_nm:.3f}          1.0"
        ),
        "angstromCoefficient             2              0.0": (
            f"angstromCoefficient             2              {args.aerosol_angstrom_exponent:.3f}"
        ),
        "singleScatteringAlbedo          2              1.0": (
            f"singleScatteringAlbedo          2              {args.aerosol_single_scatter_albedo:.3f}"
        ),
        "HGparameter_g                   2              0.7": (
            f"HGparameter_g                   2              {args.aerosol_asymmetry_factor:.3f}"
        ),
    }
    for old, new in replacements.items():
        text = replace_once(text, old, new)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text)


def write_variant_yaml(
    base_path: Path,
    output_path: Path,
    vendor_reference_path: Path,
    args: argparse.Namespace,
) -> None:
    text = base_path.read_text()
    replacements = {
        "path: validation/reference/o2a_with_cia_disamar_reference.csv": (
            f"path: {stable_path(vendor_reference_path)}"
        ),
        "solar_zenith_deg: 60.0": f"solar_zenith_deg: {args.solar_zenith_deg:.1f}",
        "viewing_zenith_deg: 30.0": f"viewing_zenith_deg: {args.viewing_zenith_deg:.1f}",
        "relative_azimuth_deg: 120.0": f"relative_azimuth_deg: {args.relative_azimuth_deg:.1f}",
        "albedo: 0.2": f"albedo: {args.surface_albedo:.3f}",
        "optical_depth_550_nm: 0.3": (
            f"optical_depth_550_nm: {args.aerosol_optical_depth_550_nm:.3f}"
        ),
        "single_scatter_albedo: 1.0": (
            f"single_scatter_albedo: {args.aerosol_single_scatter_albedo:.3f}"
        ),
        "asymmetry_factor: 0.7": f"asymmetry_factor: {args.aerosol_asymmetry_factor:.3f}",
        "angstrom_exponent: 0.0": f"angstrom_exponent: {args.aerosol_angstrom_exponent:.3f}",
    }
    for old, new in replacements.items():
        text = replace_once(text, old, new)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text)


def run_command(command: list[str]) -> None:
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=REPO_ROOT, check=True)


def write_metric_comparison(output_root: Path, plot_dir: Path, scenario_doc: dict[str, object]) -> None:
    variant_metrics_path = plot_dir / "comparison_metrics.json"
    variant_metrics = json.loads(variant_metrics_path.read_text())
    default_metrics = json.loads(DEFAULT_METRICS.read_text()) if DEFAULT_METRICS.exists() else None
    comparison = {
        "scenario": scenario_doc,
        "default_metrics_path": stable_path(DEFAULT_METRICS),
        "variant_metrics_path": stable_path(variant_metrics_path),
        "default_metrics": default_metrics,
        "variant_metrics": variant_metrics,
    }
    (output_root / "metric_comparison.json").write_text(json.dumps(comparison, indent=2) + "\n")
    print(json.dumps({
        "variant_metrics_path": stable_path(variant_metrics_path),
        "metric_comparison_path": stable_path(output_root / "metric_comparison.json"),
        "variant_reflectance": variant_metrics["reflectance"],
        "variant_radiance": variant_metrics["radiance"],
        "variant_irradiance": variant_metrics["irradiance"],
    }, indent=2), flush=True)


def main() -> None:
    args = parse_args()
    output_root = (REPO_ROOT / args.output_root).resolve()
    inputs_dir = output_root / "inputs"
    vendor_raw_dir = output_root / "vendor_raw"
    current_dir = output_root / "zdisamar_current"
    plot_dir = output_root / "plots"
    vendor_reference_path = output_root / "variant_disamar_reference.csv"
    vendor_config_path = inputs_dir / "Config_O2_with_CIA_variant.in"
    yaml_path = inputs_dir / "vendor_o2a_parity_variant.yaml"

    base_vendor_config = (REPO_ROOT / args.base_vendor_config).resolve()
    base_yaml = (REPO_ROOT / args.base_yaml).resolve()
    profile_exe = (REPO_ROOT / args.profile_exe).resolve()

    write_variant_vendor_config(base_vendor_config, vendor_config_path, args)
    write_variant_yaml(base_yaml, yaml_path, vendor_reference_path, args)

    scenario_doc: dict[str, object] = {
        "schema_version": 1,
        "base_vendor_config": stable_path(base_vendor_config),
        "base_yaml": stable_path(base_yaml),
        "variant_vendor_config": stable_path(vendor_config_path),
        "variant_yaml": stable_path(yaml_path),
        "variant_vendor_reference": stable_path(vendor_reference_path),
        "settings": {
            "solar_zenith_deg": args.solar_zenith_deg,
            "viewing_zenith_deg": args.viewing_zenith_deg,
            "relative_azimuth_deg": args.relative_azimuth_deg,
            "surface_albedo": args.surface_albedo,
            "aerosol_optical_depth_550_nm": args.aerosol_optical_depth_550_nm,
            "aerosol_single_scatter_albedo": args.aerosol_single_scatter_albedo,
            "aerosol_asymmetry_factor": args.aerosol_asymmetry_factor,
            "aerosol_angstrom_exponent": args.aerosol_angstrom_exponent,
        },
    }
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "variant_scenario.json").write_text(json.dumps(scenario_doc, indent=2) + "\n")

    run_command([
        "uv",
        "run",
        "scripts/testing_harness/o2a_vendor_reference_refresh.py",
        "--vendor-root",
        args.vendor_root,
        "--config",
        vendor_config_path.as_posix(),
        "--reference-csv",
        vendor_reference_path.as_posix(),
        "--output-dir",
        vendor_raw_dir.as_posix(),
    ])
    run_command([
        profile_exe.as_posix(),
        "--case-yaml",
        yaml_path.as_posix(),
        "--output-dir",
        current_dir.as_posix(),
        "--repeat",
        "1",
        "--write-spectrum",
        "--plot-bundle-grid",
    ])
    run_command([
        "uv",
        "run",
        "scripts/testing_harness/o2a_plot_bundle.py",
        "--current-spectrum",
        (current_dir / "generated_spectrum.csv").as_posix(),
        "--profile-summary",
        (current_dir / "summary.json").as_posix(),
        "--vendor-reference",
        vendor_reference_path.as_posix(),
        "--output-dir",
        plot_dir.as_posix(),
        "--canonical-command",
        args.canonical_command,
    ])
    (plot_dir / "variant_scenario.json").write_text(json.dumps(scenario_doc, indent=2) + "\n")
    write_metric_comparison(output_root, plot_dir, scenario_doc)


if __name__ == "__main__":
    main()
