"""Radiative-transfer control input objects.

`RadiativeTransferPerformanceThresholds` is the central place for numerical
thresholds that trade LABOS radiative-transfer work against accuracy.  These
settings do not change the physical scene; they change when the solver decides
that another Fourier term, multiple-scattering order, layer-doubling step, or
small matrix product is no longer worth evaluating.

The default thresholds are the reference-grade settings used by validation.
The `fast()` preset returns the defaults plus the current aggressive fast
override.  For an existing scene, prefer
`performance_thresholds.with_fast_mode()` so scene- or validation-family-specific
thresholds are preserved while the speed/accuracy override is applied.  The
higher-level fast mode also applies adaptive-reference-grid settings;
that combined preset is the user-facing speed mode.

Threshold guide:

- `fourier_tail_reflectance_epsilon`: stops the azimuthal Fourier expansion
  once a Fourier reflectance coefficient is smaller than this value after the
  floor order.  It must be finite and positive; the default is `3e-14`.
  In the sweep over default, azimuth, aerosol-loading, and bright-surface
  scenes, raising it to `1e-11` produced a worst reflectance residual of about
  `1e-10`, but this was too conservative to provide the desired fast-mode
  speedup by itself.

- `fourier_floor_scalar`: the earliest Fourier order where the Fourier-tail
  stop may trigger.  It must fit in the model's 16-bit field; the
  default is `2`.  Keeping this above the low orders protects the dominant
  angular structure in the reflectance field.  Lowering it would risk pruning
  physically important low-order azimuthal terms; we have not validated that as
  a safe speed knob.

- `fourier_order_cap`: a hard maximum Fourier order, or `None` for the
  geometry-derived limit.  When set, it must fit in the model's 16-bit
  field.  It is useful for experiments because it skips whole Fourier-order
  evaluations directly, but it is cruder than the tail threshold.  The
  fast preset uses `5`; in the retained four-scene spectra sweep this was the
  main contributor to the speedup while keeping the worst reflectance residual
  below `5e-4` when combined with the layer-doubling override.

- `aerosol_tangent_order_cap`: a hard maximum Fourier order for aerosol AOD and
  aerosol-pressure tangent weighting functions, or `None` to evaluate every
  active order.  The perturbation sweep found orders `>=12` to be near-neutral,
  so the fast preset uses `11`.  With the current generic Fourier cap of
  `5`, this is mainly a centrally exposed custom-fast-mode knob; it becomes
  active when callers relax the full Fourier cap but still want to skip
  high-order tangent work.

- `num_orders_max`: the hard cap on multiple-scattering order iterations inside
  each Fourier term.  `0` keeps the optical-depth-derived default; any explicit
  cap must fit in the model's 16-bit field.  Lowering it limits
  repeated scattering work but can omit real multiple-scattering energy in
  optically thicker scenes.  Prefer the convergence thresholds below before
  forcing this cap.

- `threshold_conv_first`: after the first scattering-order transport pass,
  LABOS returns early when the estimated contribution is below this threshold.
  It must be finite and positive; the default is `1.5e-7`.  In the sweep,
  raising it into the `5e-7` to `1.5e-5` range produced residuals from roughly
  `3e-9` to `4e-8` but did not produce a reliable speed win, so it is not part
  of the fast preset.

- `threshold_conv_mult`: convergence threshold for later multiple-scattering
  orders.  It must be finite and positive; the default is `1.5e-9`.
  Raising it stops the order loop earlier after the initial pass.  In the
  tested range `5e-9` to `1.5e-7`, worst residuals were about `1e-9` to `8e-8`,
  again without a consistent timing win.

- `threshold_doubl`: controls whether a layer is split to a thinner starting
  optical thickness and then rebuilt through doubling.  It must be finite and
  positive; the default is `1e-6`.  Relaxing it can save layer-doubling
  work, but this is a stronger approximation.  The fast preset uses
  `3e-5`; by itself this was not fast enough, but in combination with the
  Fourier-order cap it kept the retained spectra sweep below the `5e-4`
  reflectance-residual envelope.

- `threshold_mul`: suppresses matrix products when the product of known matrix
  traces is small.  It must be finite and positive; the default is
  `1e-8`.  This looked unsafe as a broad fast-mode control: even `3e-8`
  produced about `2.3e-5` worst reflectance residual in the sweep.

- `phase_function_truncation_threshold`: controls how much aerosol
  phase-function structure is retained before the radiative-transfer solve.
  It must be finite and positive; the default is `1e-8`.  It affects the
  angular scattering physics before LABOS runs.  Raising it was also too lossy
  for a generic fast preset: even `3e-8` produced about `1.3e-6` worst residual
  in the sweep.
"""

from dataclasses import dataclass, replace
from typing import ClassVar, Self

from .shared import object_dict, to_bool, to_float, to_int


@dataclass
class RadiativeTransferPerformanceThresholds:
    """Accuracy and speed thresholds for the LABOS radiative-transfer solve."""

    FAST_FOURIER_ORDER_CAP: ClassVar[int] = 5
    FAST_AEROSOL_TANGENT_ORDER_CAP: ClassVar[int] = 11
    FAST_FOURIER_TAIL_REFLECTANCE_EPSILON: ClassVar[float] = 1.0e-11
    FAST_THRESHOLD_DOUBL: ClassVar[float] = 3.0e-5

    num_orders_max: int
    fourier_floor_scalar: int
    fourier_order_cap: int | None
    aerosol_tangent_order_cap: int | None
    fourier_tail_reflectance_epsilon: float
    threshold_conv_first: float
    threshold_conv_mult: float
    threshold_doubl: float
    threshold_mul: float
    phase_function_truncation_threshold: float = 1.0e-8

    @classmethod
    def o2a_default(cls) -> Self:
        """Use the reference-grade thresholds unless fast mode is requested."""

        return cls(
            num_orders_max=0,
            fourier_floor_scalar=2,
            fourier_order_cap=None,
            aerosol_tangent_order_cap=None,
            fourier_tail_reflectance_epsilon=3.0e-14,
            threshold_conv_first=1.5e-7,
            threshold_conv_mult=1.5e-9,
            threshold_doubl=1.0e-6,
            threshold_mul=1.0e-8,
            phase_function_truncation_threshold=1.0e-8,
        )

    @classmethod
    def fast(cls) -> Self:
        """Return the validated speed/accuracy threshold bundle."""

        thresholds = cls.o2a_default()
        thresholds.fourier_order_cap = cls.FAST_FOURIER_ORDER_CAP
        thresholds.aerosol_tangent_order_cap = cls.FAST_AEROSOL_TANGENT_ORDER_CAP
        thresholds.fourier_tail_reflectance_epsilon = cls.FAST_FOURIER_TAIL_REFLECTANCE_EPSILON
        thresholds.threshold_doubl = cls.FAST_THRESHOLD_DOUBL

        return thresholds

    def with_fast_mode(self) -> Self:
        """Return a copy with the validated fast-mode overrides applied.

        This preserves scene-specific threshold choices, such as a validation
        family's phase-function truncation threshold, and changes only the
        broadly validated speed knobs.  The current fast preset applies the
        Fourier-order cap, aerosol tangent cap, Fourier-tail reflectance
        epsilon, and layer-doubling threshold defined by `fast()`.
        """
        thresholds = replace(self)
        fast = type(self).fast()
        thresholds.fourier_order_cap = fast.fourier_order_cap
        thresholds.aerosol_tangent_order_cap = fast.aerosol_tangent_order_cap
        thresholds.fourier_tail_reflectance_epsilon = fast.fourier_tail_reflectance_epsilon
        thresholds.threshold_doubl = fast.threshold_doubl

        return thresholds

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        allowed = {
            "num_orders_max",
            "fourier_floor_scalar",
            "fourier_order_cap",
            "aerosol_tangent_order_cap",
            "fourier_tail_reflectance_epsilon",
            "threshold_conv_first",
            "threshold_conv_mult",
            "threshold_doubl",
            "threshold_mul",
            "phase_function_truncation_threshold",
        }
        unknown = set(data) - allowed
        if unknown:
            joined = ", ".join(sorted(unknown))
            raise ValueError(f"unsupported radiative-transfer threshold fields: {joined}")

        return cls(
            num_orders_max=to_int(data["num_orders_max"]),
            fourier_floor_scalar=to_int(data["fourier_floor_scalar"]),
            fourier_order_cap=(
                None if data.get("fourier_order_cap") is None else to_int(data["fourier_order_cap"])
            ),
            aerosol_tangent_order_cap=(
                None
                if data.get("aerosol_tangent_order_cap") is None
                else to_int(data["aerosol_tangent_order_cap"])
            ),
            fourier_tail_reflectance_epsilon=to_float(data["fourier_tail_reflectance_epsilon"]),
            threshold_conv_first=to_float(data["threshold_conv_first"]),
            threshold_conv_mult=to_float(data["threshold_conv_mult"]),
            threshold_doubl=to_float(data["threshold_doubl"]),
            threshold_mul=to_float(data["threshold_mul"]),
            phase_function_truncation_threshold=to_float(
                data.get("phase_function_truncation_threshold", 1.0e-8)
            ),
        )

    def to_dict(self) -> dict[str, float | int | bool | None]:

        return {
            "num_orders_max": self.num_orders_max,
            "fourier_floor_scalar": self.fourier_floor_scalar,
            "fourier_order_cap": self.fourier_order_cap,
            "aerosol_tangent_order_cap": self.aerosol_tangent_order_cap,
            "fourier_tail_reflectance_epsilon": self.fourier_tail_reflectance_epsilon,
            "threshold_conv_first": self.threshold_conv_first,
            "threshold_conv_mult": self.threshold_conv_mult,
            "threshold_doubl": self.threshold_doubl,
            "threshold_mul": self.threshold_mul,
            "phase_function_truncation_threshold": self.phase_function_truncation_threshold,
        }


@dataclass
class RadiativeTransferControls:
    """Radiative-transfer settings for one scene."""

    scattering: str
    n_streams: int
    performance_thresholds: RadiativeTransferPerformanceThresholds
    use_spherical_correction: bool
    integrate_source_function: bool
    renorm_phase_function: bool

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        legacy_keys = {"stokes_dimension", "use_adding"}.intersection(data)

        if legacy_keys:
            joined = ", ".join(sorted(legacy_keys))
            raise ValueError(f"unsupported radiative-transfer fields: {joined}")

        return cls(
            scattering=str(data["scattering"]),
            n_streams=to_int(data["n_streams"]),
            performance_thresholds=RadiativeTransferPerformanceThresholds.from_dict(
                object_dict(data["performance_thresholds"])
            ),
            use_spherical_correction=to_bool(data["use_spherical_correction"]),
            integrate_source_function=to_bool(data["integrate_source_function"]),
            renorm_phase_function=to_bool(data["renorm_phase_function"]),
        )

    def to_dict(self) -> dict[str, object]:

        return {
            "scattering": self.scattering,
            "n_streams": self.n_streams,
            "performance_thresholds": self.performance_thresholds.to_dict(),
            "use_spherical_correction": self.use_spherical_correction,
            "integrate_source_function": self.integrate_source_function,
            "renorm_phase_function": self.renorm_phase_function,
        }
