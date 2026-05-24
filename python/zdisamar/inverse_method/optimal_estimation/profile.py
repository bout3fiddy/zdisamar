"""Discrete pressure-bin profile retrieval for O2 A aerosol location."""

import math
from collections.abc import Sequence
from dataclasses import dataclass, replace

from ... import rtm
from ...input.wavelength_band.o2a import O2AInput
from .retrieval import Measurement, RetrievalControls
from .state_vector import AEROSOL_OPTICAL_DEPTH, AerosolOpticalDepth


@dataclass(frozen=True)
class ProfilePressureBin:
    """One pressure interval used as a fixed aerosol-layer location hypothesis."""

    id: str
    top_pressure_hpa: float
    bottom_pressure_hpa: float
    center_pressure_hpa: float
    prior_probability: float


@dataclass(frozen=True)
class ProfileCandidate:
    """Retrieval result for one fixed aerosol-layer pressure bin."""

    bin: ProfilePressureBin
    converged: bool
    iteration_count: int
    retrieved_aod_550_nm: float
    posterior_variance: float
    averaging_kernel: float
    spectral_chi2_ref: float
    prior_chi2: float
    total_cost_ref: float
    delta_cost: float
    probability: float
    residual_rms: float
    residual_max_abs: float


@dataclass(frozen=True)
class ExpectedAodProfileBin:
    """Probability-weighted AOD contribution implied by the bin hypotheses."""

    bin: ProfilePressureBin
    expected_aod_550_nm: float
    expected_aod_fraction: float


@dataclass(frozen=True)
class ProfileResult:
    """Discrete profile supplement for an AOD-only fixed-location retrieval."""

    candidates: tuple[ProfileCandidate, ...]
    expected_aod_profile: tuple[ExpectedAodProfileBin, ...]
    best_bin_id: str
    second_best_bin_id: str | None
    probability_by_bin: dict[str, float]
    pressure_mean_hpa: float
    pressure_p05_hpa: float
    pressure_p50_hpa: float
    pressure_p95_hpa: float
    entropy: float
    effective_bin_count: float
    ambiguity_flags: tuple[str, ...]
    probability_calibration_beta: float
    layer_thickness_hpa: float
    score_kind: str = "reference_total_cost_softmax"
    state_retrieved_per_bin: tuple[str, ...] = (AEROSOL_OPTICAL_DEPTH,)

    @property
    def plot(self):
        """Import plotting only when a caller asks for profile figures."""

        from ...plot.profile import ProfileRetrievalPlot

        return ProfileRetrievalPlot(self)

    def to_dict(self) -> dict[str, object]:
        """Return a dependency-free product shape for notebooks and validation."""

        return {
            "schema_version": 1,
            "score_kind": self.score_kind,
            "probability_calibration_beta": self.probability_calibration_beta,
            "layer_thickness_hpa": self.layer_thickness_hpa,
            "state_retrieved_per_bin": list(self.state_retrieved_per_bin),
            "best_bin_id": self.best_bin_id,
            "second_best_bin_id": self.second_best_bin_id,
            "probability_by_bin": dict(self.probability_by_bin),
            "pressure_mean_hpa": self.pressure_mean_hpa,
            "pressure_p05_hpa": self.pressure_p05_hpa,
            "pressure_p50_hpa": self.pressure_p50_hpa,
            "pressure_p95_hpa": self.pressure_p95_hpa,
            "entropy": self.entropy,
            "effective_bin_count": self.effective_bin_count,
            "ambiguity_flags": list(self.ambiguity_flags),
            "bins": [candidate_to_dict(candidate) for candidate in self.candidates],
            "expected_aod_profile": [
                {
                    "id": item.bin.id,
                    "top_pressure_hpa": item.bin.top_pressure_hpa,
                    "bottom_pressure_hpa": item.bin.bottom_pressure_hpa,
                    "center_pressure_hpa": item.bin.center_pressure_hpa,
                    "expected_aod_550_nm": item.expected_aod_550_nm,
                    "expected_aod_fraction": item.expected_aod_fraction,
                }
                for item in self.expected_aod_profile
            ],
        }


def pressure_bins(
    edges_hpa: Sequence[float],
    *,
    prior_probabilities: Sequence[float] | None = None,
) -> tuple[ProfilePressureBin, ...]:
    """Build center-pressure hypothesis bins from user-provided pressure edges."""

    edges = tuple(float(value) for value in edges_hpa)

    if len(edges) < 2:
        raise ValueError("profile pressure grid must contain at least two edges")

    if any(not math.isfinite(value) or value <= 0.0 for value in edges):
        raise ValueError("profile pressure edges must be finite positive hPa values")

    if any(upper <= lower for lower, upper in zip(edges, edges[1:], strict=False)):
        raise ValueError("profile pressure edges must be strictly increasing")

    bin_count = len(edges) - 1
    priors = normalized_priors(prior_probabilities, bin_count)

    return tuple(
        ProfilePressureBin(
            id=pressure_bin_id(edges[index], edges[index + 1]),
            top_pressure_hpa=edges[index],
            bottom_pressure_hpa=edges[index + 1],
            center_pressure_hpa=0.5 * (edges[index] + edges[index + 1]),
            prior_probability=priors[index],
        )
        for index in range(bin_count)
    )


def profile(
    *,
    case: O2AInput,
    measurement: Measurement,
    pressure_edges_hpa: Sequence[float] | None = None,
    bins: Sequence[ProfilePressureBin] | None = None,
    aod_state: AerosolOpticalDepth,
    controls: RetrievalControls | None = None,
    layer_thickness_hpa: float | None = None,
    beta: float = 1.0,
    cache: rtm.SessionCache | None = None,
) -> ProfileResult:
    """Run the O2 A profile mode: many fixed-height AOD-only retrievals."""

    profile_bins_value = resolve_profile_bins(pressure_edges_hpa=pressure_edges_hpa, bins=bins)
    validate_aod_state(aod_state)
    active_controls = controls or RetrievalControls.from_disamar_retrieval_specs()
    active_layer_thickness_hpa = (
        float(case.aerosol_layer.thickness_hpa)
        if layer_thickness_hpa is None
        else float(layer_thickness_hpa)
    )

    if active_layer_thickness_hpa <= 0.0 or not math.isfinite(active_layer_thickness_hpa):
        raise ValueError("profile layer_thickness_hpa must be finite and positive")

    if not math.isfinite(beta) or beta < 0.0:
        raise ValueError("profile probability beta must be finite and non-negative")

    if cache is None:
        with rtm.SessionCache(case) as local_cache:
            return run_profile_with_cache(
                case=case,
                measurement=measurement,
                bins=profile_bins_value,
                aod_state=aod_state,
                controls=active_controls,
                layer_thickness_hpa=active_layer_thickness_hpa,
                beta=beta,
                cache=local_cache,
                load_case=False,
            )

    return run_profile_with_cache(
        case=case,
        measurement=measurement,
        bins=profile_bins_value,
        aod_state=aod_state,
        controls=active_controls,
        layer_thickness_hpa=active_layer_thickness_hpa,
        beta=beta,
        cache=cache,
        load_case=True,
    )


def run_profile_with_cache(
    *,
    case: O2AInput,
    measurement: Measurement,
    bins: tuple[ProfilePressureBin, ...],
    aod_state: AerosolOpticalDepth,
    controls: RetrievalControls,
    layer_thickness_hpa: float,
    beta: float,
    cache: rtm.SessionCache,
    load_case: bool,
) -> ProfileResult:
    """Execute the native profile batch using one loaded RTM session."""

    if load_case and not cache.has_loaded_case(case):
        cache.load(case, copy_case=False)

    raw_candidates = cache._handle.profile_retrieval_aod(  # noqa: SLF001
        measurement=measurement,
        bins=bins,
        aod=aod_state,
        controls=controls,
        layer_thickness_hpa=layer_thickness_hpa,
    )

    return build_profile_result(
        bins=bins,
        raw_candidates=raw_candidates,
        beta=beta,
        layer_thickness_hpa=layer_thickness_hpa,
    )


def build_profile_result(
    *,
    bins: tuple[ProfilePressureBin, ...],
    raw_candidates: Sequence[dict[str, float | int | bool]],
    beta: float,
    layer_thickness_hpa: float,
) -> ProfileResult:
    """Normalize native candidate scores into a profile product."""

    if len(raw_candidates) != len(bins):
        raise RuntimeError("native profile retrieval returned the wrong number of candidates")

    costs = [float(candidate["total_cost_ref"]) for candidate in raw_candidates]
    min_cost = min(costs)
    probabilities = softmax_probabilities(
        [
            math.log(profile_bin.prior_probability) - 0.5 * beta * (cost - min_cost)
            for profile_bin, cost in zip(bins, costs, strict=True)
        ]
    )
    candidates = tuple(
        ProfileCandidate(
            bin=profile_bin,
            converged=bool(raw["converged"]),
            iteration_count=int(raw["iteration_count"]),
            retrieved_aod_550_nm=float(raw["retrieved_aod_550_nm"]),
            posterior_variance=float(raw["posterior_variance"]),
            averaging_kernel=float(raw["averaging_kernel"]),
            spectral_chi2_ref=float(raw["spectral_chi2_ref"]),
            prior_chi2=float(raw["prior_chi2"]),
            total_cost_ref=float(raw["total_cost_ref"]),
            delta_cost=float(raw["total_cost_ref"]) - min_cost,
            probability=probability,
            residual_rms=float(raw["residual_rms"]),
            residual_max_abs=float(raw["residual_max_abs"]),
        )
        for profile_bin, raw, probability in zip(bins, raw_candidates, probabilities, strict=True)
    )
    ranked = tuple(sorted(candidates, key=lambda candidate: candidate.probability, reverse=True))
    probability_by_bin = {candidate.bin.id: candidate.probability for candidate in candidates}
    entropy = -sum(
        candidate.probability * math.log(candidate.probability)
        for candidate in candidates
        if candidate.probability > 0.0
    )
    expected_aod_profile = expected_aod_bins(candidates)

    return ProfileResult(
        candidates=candidates,
        expected_aod_profile=expected_aod_profile,
        best_bin_id=ranked[0].bin.id,
        second_best_bin_id=None if len(ranked) == 1 else ranked[1].bin.id,
        probability_by_bin=probability_by_bin,
        pressure_mean_hpa=sum(
            candidate.probability * candidate.bin.center_pressure_hpa for candidate in candidates
        ),
        pressure_p05_hpa=weighted_quantile(candidates, 0.05),
        pressure_p50_hpa=weighted_quantile(candidates, 0.50),
        pressure_p95_hpa=weighted_quantile(candidates, 0.95),
        entropy=entropy,
        effective_bin_count=math.exp(entropy),
        ambiguity_flags=ambiguity_flags(ranked),
        probability_calibration_beta=beta,
        layer_thickness_hpa=layer_thickness_hpa,
    )


def resolve_profile_bins(
    *,
    pressure_edges_hpa: Sequence[float] | None,
    bins: Sequence[ProfilePressureBin] | None,
) -> tuple[ProfilePressureBin, ...]:
    """Accept either pressure edges or already constructed profile bins."""

    if (pressure_edges_hpa is None) == (bins is None):
        raise ValueError("provide exactly one of pressure_edges_hpa or bins")

    if pressure_edges_hpa is not None:
        return pressure_bins(pressure_edges_hpa)

    resolved_bins = tuple(bins or ())

    if not resolved_bins:
        raise ValueError("profile bins must not be empty")

    total_prior = sum(float(item.prior_probability) for item in resolved_bins)

    if not math.isfinite(total_prior) or not math.isclose(total_prior, 1.0, abs_tol=1.0e-9):
        raise ValueError("profile bin prior probabilities must sum to 1")

    for previous, current in zip(resolved_bins, resolved_bins[1:], strict=False):
        if current.top_pressure_hpa < previous.bottom_pressure_hpa:
            raise ValueError("profile bins must be ordered by increasing pressure")

    return tuple(validate_profile_bin(item) for item in resolved_bins)


def validate_profile_bin(profile_bin: ProfilePressureBin) -> ProfilePressureBin:
    """Return a normalized profile bin or reject inconsistent pressure fields."""

    top = float(profile_bin.top_pressure_hpa)
    bottom = float(profile_bin.bottom_pressure_hpa)
    center = float(profile_bin.center_pressure_hpa)
    prior = float(profile_bin.prior_probability)

    if (
        not math.isfinite(top)
        or not math.isfinite(bottom)
        or not math.isfinite(center)
        or not math.isfinite(prior)
        or top <= 0.0
        or bottom <= top
        or prior <= 0.0
    ):
        raise ValueError("profile bin pressures and priors must be finite positive values")

    expected_center = 0.5 * (top + bottom)

    if not math.isclose(center, expected_center, rel_tol=0.0, abs_tol=1.0e-9):
        raise ValueError("profile bin center_pressure_hpa must be the edge midpoint")

    return replace(
        profile_bin,
        top_pressure_hpa=top,
        bottom_pressure_hpa=bottom,
        center_pressure_hpa=center,
        prior_probability=prior,
    )


def validate_aod_state(aod_state: AerosolOpticalDepth) -> None:
    """Keep profile mode constrained to direct AOD-only nuisance retrievals."""

    if aod_state.name != AEROSOL_OPTICAL_DEPTH:
        raise ValueError("profile mode retrieves only aerosol optical depth")

    values = [aod_state.initial, aod_state.prior, aod_state.variance]

    if aod_state.lower is not None:
        values.append(aod_state.lower)

    if aod_state.upper is not None:
        values.append(aod_state.upper)

    if any(not math.isfinite(float(value)) for value in values):
        raise ValueError("profile AOD state values must be finite")

    if aod_state.variance <= 0.0:
        raise ValueError("profile AOD variance must be positive")

    if (
        aod_state.lower is not None
        and aod_state.upper is not None
        and aod_state.lower > aod_state.upper
    ):
        raise ValueError("profile AOD lower bound must not exceed upper bound")


def normalized_priors(
    prior_probabilities: Sequence[float] | None,
    count: int,
) -> tuple[float, ...]:
    """Return normalized bin priors."""

    if prior_probabilities is None:
        return tuple(1.0 / count for _ in range(count))

    priors = tuple(float(value) for value in prior_probabilities)

    if len(priors) != count:
        raise ValueError("profile prior count must match pressure bin count")

    if any(not math.isfinite(value) or value <= 0.0 for value in priors):
        raise ValueError("profile priors must be finite positive values")

    total = sum(priors)

    if total <= 0.0 or not math.isfinite(total):
        raise ValueError("profile priors must have finite positive total")

    return tuple(value / total for value in priors)


def softmax_probabilities(log_weights: Sequence[float]) -> tuple[float, ...]:
    """Stable softmax for candidate log weights."""

    if not log_weights:
        raise ValueError("profile probability calculation needs at least one candidate")

    if any(not math.isfinite(value) for value in log_weights):
        raise ValueError("profile log weights must be finite")

    maximum = max(log_weights)
    weights = [math.exp(value - maximum) for value in log_weights]
    total = sum(weights)

    if total <= 0.0 or not math.isfinite(total):
        raise ValueError("profile weights underflowed")

    return tuple(value / total for value in weights)


def weighted_quantile(candidates: Sequence[ProfileCandidate], quantile: float) -> float:
    """Return a pressure-center quantile from discrete bin probabilities."""

    ordered = sorted(candidates, key=lambda candidate: candidate.bin.center_pressure_hpa)
    target = min(max(float(quantile), 0.0), 1.0)
    cumulative = 0.0

    for candidate in ordered:
        cumulative += candidate.probability

        if cumulative >= target:
            return candidate.bin.center_pressure_hpa

    return ordered[-1].bin.center_pressure_hpa


def expected_aod_bins(
    candidates: Sequence[ProfileCandidate],
) -> tuple[ExpectedAodProfileBin, ...]:
    """Convert location support into probability-weighted AOD by profile bin."""

    expected = [
        candidate.probability * candidate.retrieved_aod_550_nm for candidate in candidates
    ]
    total = sum(expected)

    return tuple(
        ExpectedAodProfileBin(
            bin=candidate.bin,
            expected_aod_550_nm=value,
            expected_aod_fraction=0.0 if total <= 0.0 else value / total,
        )
        for candidate, value in zip(candidates, expected, strict=True)
    )


def ambiguity_flags(candidates_by_probability: Sequence[ProfileCandidate]) -> tuple[str, ...]:
    """Derive first-pass diagnostic flags from the bin probability shape."""

    flags: list[str] = []
    best = candidates_by_probability[0]
    second = candidates_by_probability[1] if len(candidates_by_probability) > 1 else None
    entropy = -sum(
        candidate.probability * math.log(candidate.probability)
        for candidate in candidates_by_probability
        if candidate.probability > 0.0
    )
    effective_count = math.exp(entropy)

    if best.probability < 0.6:
        flags.append("ambiguous_layer_location")

    if second is not None and (second.probability >= 0.25 or second.delta_cost < 4.0):
        flags.append("two_competing_locations")

    if effective_count >= 3.0:
        flags.append("broad_location_support")

    if max(candidate.delta_cost for candidate in candidates_by_probability) < 2.0:
        flags.append("weak_vertical_information")

    if best.retrieved_aod_550_nm < 0.05:
        flags.append("low_aod_weak_vertical_information")

    return tuple(flags)


def candidate_to_dict(candidate: ProfileCandidate) -> dict[str, object]:
    """Serialize one candidate without exposing Python object internals."""

    return {
        "id": candidate.bin.id,
        "top_pressure_hpa": candidate.bin.top_pressure_hpa,
        "bottom_pressure_hpa": candidate.bin.bottom_pressure_hpa,
        "center_pressure_hpa": candidate.bin.center_pressure_hpa,
        "prior_probability": candidate.bin.prior_probability,
        "posterior_probability": candidate.probability,
        "retrieved_aod_550_nm": candidate.retrieved_aod_550_nm,
        "posterior_variance": candidate.posterior_variance,
        "averaging_kernel": candidate.averaging_kernel,
        "spectral_chi2_ref": candidate.spectral_chi2_ref,
        "prior_chi2": candidate.prior_chi2,
        "total_cost_ref": candidate.total_cost_ref,
        "delta_cost": candidate.delta_cost,
        "converged": candidate.converged,
        "iteration_count": candidate.iteration_count,
        "residual_rms": candidate.residual_rms,
        "residual_max_abs": candidate.residual_max_abs,
    }


def pressure_bin_id(top_pressure_hpa: float, bottom_pressure_hpa: float) -> str:
    """Return a stable pressure-bin identifier."""

    def part(value: float) -> str:
        return f"{value:.6g}".replace("-", "m").replace(".", "p")

    return f"p_{part(top_pressure_hpa)}_{part(bottom_pressure_hpa)}"


__all__ = [
    "ExpectedAodProfileBin",
    "ProfileCandidate",
    "ProfilePressureBin",
    "ProfileResult",
    "pressure_bins",
    "profile",
]
