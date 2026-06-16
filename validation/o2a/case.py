"""Canonical validation scene construction."""

from dataclasses import replace


def build_o2a_case(band, *, jacobian_reference_layer: bool = False):
    """Return the packaged scene, with optional Jacobian-validation geometry."""

    case = band.reference_scene()

    if not jacobian_reference_layer:
        return case

    aerosol_top_pressure_hpa = 875.0
    aerosol_bottom_pressure_hpa = 925.0
    aerosol_layer = replace(
        case.aerosol.profile[0],
        top_pressure_hpa=aerosol_top_pressure_hpa,
        bottom_pressure_hpa=aerosol_bottom_pressure_hpa,
    )
    performance_thresholds = replace(
        case.radiative_transfer.performance_thresholds,
        phase_function_truncation_threshold=1.0e-6,
    )

    return replace(
        case,
        atmosphere=replace(
            case.atmosphere,
            intervals=[
                replace(
                    case.atmosphere.intervals[0],
                    bottom_pressure_hpa=aerosol_top_pressure_hpa,
                ),
                replace(
                    case.atmosphere.intervals[1],
                    top_pressure_hpa=aerosol_top_pressure_hpa,
                    bottom_pressure_hpa=aerosol_bottom_pressure_hpa,
                    altitude_divisions=2,
                ),
                replace(
                    case.atmosphere.intervals[2],
                    top_pressure_hpa=aerosol_bottom_pressure_hpa,
                    altitude_divisions=4,
                ),
            ],
        ),
        geometry=replace(
            case.geometry,
            viewing_zenith_deg=0.0,
            relative_azimuth_deg=0.0,
        ),
        aerosol=replace(
            case.aerosol,
            placement=replace(
                case.aerosol.placement,
                top_pressure_hpa=aerosol_top_pressure_hpa,
                bottom_pressure_hpa=aerosol_bottom_pressure_hpa,
            ),
            profile=(aerosol_layer,),
        ),
        instrument_response=replace(
            case.instrument_response,
            adaptive_reference_grid={
                **case.instrument_response.adaptive_reference_grid,
                "points_per_fwhm": 12,
                "strong_line_max_divisions": 30,
            },
        ),
        radiative_transfer=replace(
            case.radiative_transfer,
            performance_thresholds=performance_thresholds,
        ),
    )


def build_o2a_jacobian_case(band):
    """Return the validation scene used by retained Jacobian comparisons."""

    case = build_o2a_case(band, jacobian_reference_layer=True)

    return replace(
        case,
        metadata={
            "id": "disamar_reference_o2a_jacobian_validation",
            "storage": "disamar-reference-o2a-jacobian-validation",
            "description": "DISAMAR O2A Jacobian validation case.",
        },
        scene_id="o2a_disamar_reference_jacobian_validation",
        instrument_response=replace(
            case.instrument_response,
            instrument_name="disamar-o2a-jacobian-validation",
        ),
    )
