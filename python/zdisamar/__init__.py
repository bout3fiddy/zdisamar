"""Python access to zdisamar radiative-transfer tooling."""

from importlib import import_module

from . import reference_data, rtm, wavelength_bands


def __getattr__(name: str):

    if name == "optimal_estimation":
        module = import_module(".optimal_estimation", __name__)
        globals()[name] = module

        return module

    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


__all__ = [
    "reference_data",
    "rtm",
    "optimal_estimation",
    "wavelength_bands",
]
