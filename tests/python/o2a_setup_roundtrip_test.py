import argparse
import copy
import json
import time
from dataclasses import asdict
from pathlib import Path
from typing import Any

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]


def parse_args() -> argparse.Namespace:

    parser = argparse.ArgumentParser(
        description=(
            "Verify that the typed Python O2 A setup matches the default DISAMAR parity entrypoint."
        )
    )
    parser.add_argument(
        "--output",
        default="out/ci/python_o2a_setup_roundtrip.json",
        help="JSON report path. Defaults to out/ci/python_o2a_setup_roundtrip.json.",
    )

    return parser.parse_args()


def spectrum_arrays(spectrum: Any) -> dict[str, np.ndarray]:

    return {
        "wavelength_nm": spectrum.wavelength_nm.copy(),
        "radiance": spectrum.radiance.copy(),
        "irradiance": spectrum.irradiance.copy(),
        "reflectance": spectrum.reflectance.copy(),
    }


def run_roundtrip() -> dict[str, Any]:

    from zdisamar import rtm
    from zdisamar.wavelength_bands import o2a

    tolerance = 1.0e-12
    start_s = time.perf_counter()

    case_start_s = time.perf_counter()
    case = o2a.reference_case()
    case_s = time.perf_counter() - case_start_s

    typed_rtm_start_s = time.perf_counter()
    typed_spectrum = rtm.spectrum(case)
    typed_rtm_s = time.perf_counter() - typed_rtm_start_s
    typed_report = typed_spectrum.diagnostic_report
    typed_arrays = spectrum_arrays(typed_spectrum)

    reference_rtm_start_s = time.perf_counter()
    reference_spectrum = rtm.spectrum(o2a.reference_case())
    reference_rtm_s = time.perf_counter() - reference_rtm_start_s
    reference_report = reference_spectrum.diagnostic_report
    reference_arrays = spectrum_arrays(reference_spectrum)

    perturbed_case = copy.deepcopy(case)
    perturbed_case.aerosol.optical_depth_550_nm *= 1.05

    session_create_start_s = time.perf_counter()

    with rtm.SessionCache() as cache:
        session_create_s = time.perf_counter() - session_create_start_s

        session_prepare_start_s = time.perf_counter()
        cache.load(case)
        session_prepare_s = time.perf_counter() - session_prepare_start_s
        session_rtm_start_s = time.perf_counter()
        session_spectrum = cache.spectrum()
        session_rtm_s = time.perf_counter() - session_rtm_start_s
        session_arrays = spectrum_arrays(session_spectrum)

        perturbed_session_prepare_start_s = time.perf_counter()
        cache.load(perturbed_case)
        perturbed_session_prepare_s = time.perf_counter() - perturbed_session_prepare_start_s
        perturbed_session_rtm_start_s = time.perf_counter()
        perturbed_session_spectrum = cache.spectrum(jacobian=True)
        perturbed_session_rtm_s = time.perf_counter() - perturbed_session_rtm_start_s
        perturbed_session_arrays = spectrum_arrays(perturbed_session_spectrum)
        perturbed_session_jacobian = perturbed_session_spectrum.radiance_jacobian.copy()

        requested_jacobian_names = (
            "aerosol_optical_depth",
            "aerosol_layer_mid_pressure_hpa",
        )
        compact_session_spectrum = cache.spectrum(
            jacobian=True,
            jacobian_state_names=requested_jacobian_names,
        )
        compact_session_names = compact_session_spectrum.jacobian_state_names
        compact_session_jacobian = compact_session_spectrum.radiance_jacobian.copy()
        empty_jacobian_state_selection_rejected = False

        try:
            cache.spectrum(jacobian=True, jacobian_state_names=())
        except ValueError:
            empty_jacobian_state_selection_rejected = True

    perturbed_functional_spectrum = rtm.spectrum(perturbed_case, jacobian=True)
    perturbed_functional_arrays = spectrum_arrays(perturbed_functional_spectrum)
    perturbed_functional_jacobian = perturbed_functional_spectrum.radiance_jacobian.copy()

    checks = {
        "typed_sample_count": int(typed_arrays["wavelength_nm"].size),
        "reference_sample_count": int(reference_arrays["wavelength_nm"].size),
        "sample_counts_match": bool(
            typed_arrays["wavelength_nm"].size == reference_arrays["wavelength_nm"].size
        ),
        "typed_report_matches_arrays": bool(
            typed_report.sample_count == typed_arrays["wavelength_nm"].size
            and np.isclose(
                typed_report.mean_reflectance,
                np.mean(typed_arrays["reflectance"]),
                atol=tolerance,
                rtol=tolerance,
            )
        ),
        "reference_report_matches_arrays": bool(
            reference_report.sample_count == reference_arrays["wavelength_nm"].size
            and np.isclose(
                reference_report.mean_reflectance,
                np.mean(reference_arrays["reflectance"]),
                atol=tolerance,
                rtol=tolerance,
            )
        ),
        "reference_matches_typed_arrays": bool(
            np.allclose(
                reference_arrays["wavelength_nm"],
                typed_arrays["wavelength_nm"],
                atol=tolerance,
                rtol=tolerance,
            )
            and np.allclose(
                reference_arrays["radiance"],
                typed_arrays["radiance"],
                atol=tolerance,
                rtol=tolerance,
            )
            and np.allclose(
                reference_arrays["irradiance"],
                typed_arrays["irradiance"],
                atol=tolerance,
                rtol=tolerance,
            )
            and np.allclose(
                reference_arrays["reflectance"],
                typed_arrays["reflectance"],
                atol=tolerance,
                rtol=tolerance,
            )
        ),
        "session_matches_typed_arrays": bool(
            np.allclose(
                session_arrays["wavelength_nm"],
                typed_arrays["wavelength_nm"],
                atol=tolerance,
                rtol=tolerance,
            )
            and np.allclose(
                session_arrays["radiance"],
                typed_arrays["radiance"],
                atol=tolerance,
                rtol=tolerance,
            )
            and np.allclose(
                session_arrays["irradiance"],
                typed_arrays["irradiance"],
                atol=tolerance,
                rtol=tolerance,
            )
            and np.allclose(
                session_arrays["reflectance"],
                typed_arrays["reflectance"],
                atol=tolerance,
                rtol=tolerance,
            )
        ),
        "session_reload_matches_functional_jacobian": bool(
            np.allclose(
                perturbed_session_arrays["reflectance"],
                perturbed_functional_arrays["reflectance"],
                atol=tolerance,
                rtol=tolerance,
            )
            and np.allclose(
                perturbed_session_jacobian,
                perturbed_functional_jacobian,
                atol=tolerance,
                rtol=tolerance,
            )
        ),
        "requested_jacobian_dimension_matches_state_vector": bool(
            compact_session_names == requested_jacobian_names
            and compact_session_jacobian.shape
            == (perturbed_session_arrays["wavelength_nm"].size, len(requested_jacobian_names))
        ),
        "requested_jacobian_columns_match_full_native_columns": bool(
            np.allclose(
                compact_session_jacobian,
                perturbed_session_jacobian[:, 1:3],
                atol=tolerance,
                rtol=tolerance,
            )
        ),
        "empty_jacobian_state_selection_rejected": empty_jacobian_state_selection_rejected,
        "parity_route_used": True,
        "tolerance": tolerance,
    }

    return {
        "question": "Does the typed Python O2 A setup match the default DISAMAR parity entrypoint?",
        "answer": {
            "matches": checks["reference_matches_typed_arrays"],
            "sample_count": checks["typed_sample_count"],
        },
        "typed_diagnostic_report": asdict(typed_report),
        "reference_diagnostic_report": asdict(reference_report),
        "checks": checks,
        "timing": {
            "o2a_case_s": case_s,
            "typed_rtm_s": typed_rtm_s,
            "reference_rtm_s": reference_rtm_s,
            "session_create_s": session_create_s,
            "session_prepare_s": session_prepare_s,
            "session_rtm_s": session_rtm_s,
            "perturbed_session_prepare_s": perturbed_session_prepare_s,
            "perturbed_session_rtm_jacobian_s": perturbed_session_rtm_s,
            "total_s": time.perf_counter() - start_s,
        },
    }


def main() -> int:

    args = parse_args()
    output_path = Path(args.output)
    summary = run_roundtrip()
    summary["artifacts"] = {"json": str(output_path)}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    checks = summary["checks"]
    print(summary["question"])
    print(
        f"answer: matches={summary['answer']['matches']}, "
        f"sample_count={summary['answer']['sample_count']}"
    )
    print(
        "checks: "
        f"sample_counts_match={checks['sample_counts_match']}, "
        f"typed_report_matches_arrays={checks['typed_report_matches_arrays']}, "
        f"reference_report_matches_arrays={checks['reference_report_matches_arrays']}, "
        f"reference_matches_typed_arrays={checks['reference_matches_typed_arrays']}, "
        f"session_matches_typed_arrays={checks['session_matches_typed_arrays']}, "
        "session_reload_matches_functional_jacobian="
        f"{checks['session_reload_matches_functional_jacobian']}, "
        "requested_jacobian_dimension_matches_state_vector="
        f"{checks['requested_jacobian_dimension_matches_state_vector']}, "
        "requested_jacobian_columns_match_full_native_columns="
        f"{checks['requested_jacobian_columns_match_full_native_columns']}, "
        "empty_jacobian_state_selection_rejected="
        f"{checks['empty_jacobian_state_selection_rejected']}"
    )
    print(f"json: {output_path}")
    excluded = {"tolerance", "typed_sample_count", "reference_sample_count"}
    passed = all(value for key, value in checks.items() if key not in excluded)

    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
