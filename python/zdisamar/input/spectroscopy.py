"""O2 spectroscopy input objects."""

from dataclasses import dataclass
from typing import Self

from .assets import ReferenceAsset
from .shared import int_list, object_dict, optional_float, to_bool


def _asset_or_none(asset: ReferenceAsset | None) -> dict[str, str] | None:

    return None if asset is None else asset.to_dict()


@dataclass
class LineByLine:
    """Line-list and line-mixing inputs for O2 absorption."""

    line_list_asset: ReferenceAsset
    line_mixing_asset: ReferenceAsset
    strong_lines_asset: ReferenceAsset
    line_mixing_factor: float | None
    isotopes_sim: list[int]
    threshold_line_sim: float | None
    cutoff_sim_cm1: float | None

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        return cls(
            line_list_asset=ReferenceAsset.from_dict(object_dict(data["line_list_asset"])),
            line_mixing_asset=ReferenceAsset.from_dict(object_dict(data["line_mixing_asset"])),
            strong_lines_asset=ReferenceAsset.from_dict(object_dict(data["strong_lines_asset"])),
            line_mixing_factor=optional_float(data, "line_mixing_factor"),
            isotopes_sim=int_list(data["isotopes_sim"]),
            threshold_line_sim=optional_float(data, "threshold_line_sim"),
            cutoff_sim_cm1=optional_float(data, "cutoff_sim_cm1"),
        )

    def to_dict(self) -> dict[str, object]:

        return {
            "line_list_asset": self.line_list_asset.to_dict(),
            "line_mixing_asset": self.line_mixing_asset.to_dict(),
            "strong_lines_asset": self.strong_lines_asset.to_dict(),
            "line_mixing_factor": self.line_mixing_factor,
            "isotopes_sim": self.isotopes_sim,
            "threshold_line_sim": self.threshold_line_sim,
            "cutoff_sim_cm1": self.cutoff_sim_cm1,
        }


@dataclass
class OxygenCollisionInducedAbsorption:
    """O2-O2 collision-induced absorption settings for the scene."""

    enabled: bool
    cross_section_asset: ReferenceAsset | None

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        cross_section_asset = data.get("cia_asset")

        return cls(
            enabled=to_bool(data["enabled"]),
            cross_section_asset=(
                None
                if cross_section_asset is None
                else ReferenceAsset.from_dict(object_dict(cross_section_asset))
            ),
        )

    def to_dict(self) -> dict[str, bool | dict[str, str] | None]:

        return {
            "enabled": self.enabled,
            "cia_asset": _asset_or_none(self.cross_section_asset),
        }
