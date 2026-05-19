"""Process memory measurements for retained benchmark evidence."""

import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class PeakRssSample:
    bytes: int | None
    source: str
    supported: bool

    @property
    def mib(self) -> float | None:

        if self.bytes is None:
            return None

        return self.bytes / (1024 * 1024)


@dataclass(frozen=True)
class PeakRssProbe:
    start: PeakRssSample

    def finish(self) -> dict[str, bool | int | float | str | None]:

        end = peak_rss()
        delta_bytes = None
        delta_mib = None

        if self.start.bytes is not None and end.bytes is not None:
            delta_bytes = max(end.bytes - self.start.bytes, 0)
            delta_mib = delta_bytes / (1024 * 1024)

        return {
            "peak_rss_supported": end.supported,
            "peak_rss_source": end.source,
            "peak_rss_bytes": end.bytes,
            "peak_rss_mib": end.mib,
            "peak_rss_delta_bytes": delta_bytes,
            "peak_rss_delta_mib": delta_mib,
            "start_peak_rss_bytes": self.start.bytes,
            "start_peak_rss_mib": self.start.mib,
        }


def start_peak_rss_probe() -> PeakRssProbe:

    return PeakRssProbe(start=peak_rss())


def peak_rss() -> PeakRssSample:

    try:
        import resource
    except ImportError:
        return PeakRssSample(
            bytes=None,
            source="resource.getrusage unavailable",
            supported=False,
        )

    maxrss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss

    return PeakRssSample(
        bytes=normalize_ru_maxrss_to_bytes(maxrss),
        source="resource.getrusage(RUSAGE_SELF).ru_maxrss",
        supported=True,
    )


def normalize_ru_maxrss_to_bytes(maxrss: int) -> int:

    if sys.platform == "darwin":
        return maxrss

    return maxrss * 1024
