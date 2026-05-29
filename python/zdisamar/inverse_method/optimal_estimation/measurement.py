"""Measurement-grid validation for optimal estimation."""


class WavelengthGridMismatchError(ValueError):
    """Raised when retrieval quantities are sampled on different wavelength grids."""


def require_matching_wavelength_grid(
    expected,
    actual,
    *,
    expected_name: str,
    actual_name: str,
) -> None:
    """Reject hidden wavelength-grid adaptation at OE boundaries."""

    expected_values = tuple(float(value) for value in expected)
    actual_values = tuple(float(value) for value in actual)

    if expected_values != actual_values:
        raise WavelengthGridMismatchError(
            f"{actual_name} wavelength grid must match {expected_name} wavelength grid"
        )
