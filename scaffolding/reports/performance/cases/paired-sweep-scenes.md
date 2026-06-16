# Paired Sweep Scenes

The paired sweep script currently builds a deterministic scene pool:

```text
SCENE_SAMPLE_COUNT = 500
RUN_COUNT = 100
RNG_SEED = 20260507
```

The script runs the first `RUN_COUNT` scenes from the 500-scene pool. This keeps
the first 100 scenes stable if the sweep is later expanded.

The varied scene parameters follow the ranges used in the AMT 2019
aerosol-height retrieval study, `https://doi.org/10.5194/amt-12-6619-2019`,
narrowed to sensible cloud-free aerosol-only validation ranges.

Varied across scenes:

```text
solar zenith
viewing zenith
relative azimuth
surface pressure
surface albedo
aerosol optical depth
aerosol layer mid pressure
```

Fixed inside the current retrieval:

```text
surface pressure
surface albedo
geometry
aerosol single-scattering albedo
aerosol asymmetry factor
Angstrom exponent
aerosol layer thickness
```

Retrieved state:

```text
aerosol optical depth
aerosol layer mid pressure
```
