"""Reference-data asset input objects."""

from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path


@dataclass
class ReferenceAsset:
    """Named reference-data file used by an O2 A scene."""

    id: str
    path: str
    format: str

    @classmethod
    def from_dict(cls, data: dict) -> ReferenceAsset:

        return cls(
            id=str(data["id"]),
            path=str(data["path"]),
            format=str(data["format"]),
        )

    def to_dict(self) -> dict[str, str]:

        return {"id": self.id, "path": self.path, "format": self.format}

    def with_resolved_path(self, resolver) -> ReferenceAsset:
        """Resolve relative data paths only when preparing a calculation."""

        path = Path(self.path)

        if path.is_absolute():
            return deepcopy(self)

        return ReferenceAsset(id=self.id, path=str(resolver(path)), format=self.format)


@dataclass
class ReferenceAssets:
    """Reference-data files required to reproduce one O2 A calculation."""

    atmosphere_profile: ReferenceAsset
    vendor_reference_csv: ReferenceAsset
    raw_solar_reference: ReferenceAsset
    airmass_factor_lut: ReferenceAsset

    @classmethod
    def from_dict(cls, data: dict) -> ReferenceAssets:

        return cls(
            atmosphere_profile=ReferenceAsset.from_dict(data["atmosphere_profile"]),
            vendor_reference_csv=ReferenceAsset.from_dict(data["vendor_reference_csv"]),
            raw_solar_reference=ReferenceAsset.from_dict(data["raw_solar_reference"]),
            airmass_factor_lut=ReferenceAsset.from_dict(data["airmass_factor_lut"]),
        )

    def to_dict(self) -> dict[str, dict[str, str]]:

        return {
            "atmosphere_profile": self.atmosphere_profile.to_dict(),
            "vendor_reference_csv": self.vendor_reference_csv.to_dict(),
            "raw_solar_reference": self.raw_solar_reference.to_dict(),
            "airmass_factor_lut": self.airmass_factor_lut.to_dict(),
        }
