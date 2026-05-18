"""Reflectance-Jacobian plots."""

from . import fields
from .properties import PLOT
from .svg import SvgFigure, line_panel


def reflectance_jacobian(spectrum, state: str):

    rows, y_field, y_title = jacobian_frame(spectrum, state)
    panel = line_panel(
        title=f"{y_title}: {state}",
        x_title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        y_title=y_title,
        x=[float(row[fields.WAVELENGTH_NM]) for row in rows],
        y=[float(row[y_field]) for row in rows],
        name=f"{y_title}: {state}",
        color=PLOT.colors["blue"],
    )

    return SvgFigure(title=f"{y_title}: {state}", panels=(panel,))


def jacobian_frame(spectrum, state: str):

    names = spectrum.jacobian_state_names

    if state not in names:
        raise ValueError(f"unknown Jacobian state: {state}")

    index = names.index(state)
    wavelength_nm = spectrum.wavelength_nm.copy()

    try:
        reflectance_jacobian = spectrum.reflectance_jacobian(state).copy()
    except RuntimeError:
        radiance_jacobian = spectrum.radiance_jacobian[:, index].copy()

        return (
            [
                {
                    fields.WAVELENGTH_NM: float(wavelength),
                    fields.RADIANCE_JACOBIAN: float(value),
                }
                for wavelength, value in zip(wavelength_nm, radiance_jacobian, strict=True)
            ],
            fields.RADIANCE_JACOBIAN,
            "dL / dx",
        )

    return (
        [
            {
                fields.WAVELENGTH_NM: float(wavelength),
                fields.REFLECTANCE_JACOBIAN: float(value),
            }
            for wavelength, value in zip(wavelength_nm, reflectance_jacobian, strict=True)
        ],
        fields.REFLECTANCE_JACOBIAN,
        fields.QUANTITY_LABELS[fields.REFLECTANCE_JACOBIAN],
    )
