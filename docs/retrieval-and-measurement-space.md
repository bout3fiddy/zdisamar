# Retrieval and Measurement-Space Outputs

## Why Measurement Space Is Explicit

The DISAMAR literature treats the system as both a forward model and a retrieval framework. That makes the measurement-space product a first-class scientific result. The code should therefore expose radiance-space outputs directly instead of hiding them behind a single retrieval scalar.

In `zdisamar`, the measurement-space product is the shared interface between:

- optical preparation,
- transport evaluation,
- retrieval methods,
- exporters,
- validation harnesses.

## Execution Layers

### 1. Request-time scene

The `Request` carries a typed `Scene` and optional inverse-problem state. The scene contains the physical description of the observation:

- geometry,
- spectral sampling,
- surface properties,
- aerosol and cloud state,
- observation-model and instrument-response settings.

### 2. Prepared optical state

`src/kernels/optics/prepare.zig` turns the scene and reference data into a `PreparedOpticalState`.

That state contains the quantities needed by the forward operator:

- layer and sublayer optical depths,
- continuum and line contributions,
- CIA terms,
- temperature and pressure summaries,
- aerosol and cloud scattering properties,
- wavelength-dependent helpers.

### 3. Measurement-space product

`src/kernels/transport/measurement_space.zig` evaluates the prepared state and writes an owned measurement-space product into `Result`.

The product can carry:

- wavelength arrays,
- radiance,
- irradiance,
- reflectance,
- noise estimates,
- Jacobian-like derivatives when requested,
- optical-depth summaries and auxiliary physical scalars.

This is the stable observation-side surface seen by retrieval code and exporters.

## Method Families

The repository currently exposes OE-, DOAS-, and DISMAS-labeled retrieval lanes under `src/retrieval/`. They share contracts, priors, covariance handling, and typed forward-model interfaces while keeping family-specific policy separate.

Those family names are deliberate, but they should be read carefully: the current solvers preserve the intended retrieval seams and result surfaces without claiming that each lane is already a full method-faithful implementation of the corresponding literature algorithm.

### Optimal estimation

The OE-labeled path treats the problem as a Rodgers-style state-estimation task with priors, measurement covariance, Jacobians, posterior covariance, DFS, and averaging-kernel products. In `zdisamar` this is now the first retrieval family that runs on the real spectral residual path rather than on summary-only surrogate features.

### DOAS

The DOAS-labeled path emphasizes narrow-band differential structure. It still uses the same scene and observation contracts, but its solver policy is narrower and does not require the same derivative mode as OE or DISMAS. Today it is a surrogate DOAS lane with truthful convergence reporting and typed state access, not a full differential-spectral fit implementation.

### DISMAS

The DISMAS-labeled path fits directly in measurement space. That makes the fidelity of the forward product particularly important, because the method depends on the absolute shape of the simulated observation rather than only on differential structures. The current solver preserves that direct-measurement-space seam while remaining a surrogate DISMAS lane.

## Why Irradiance Is Part Of The Product

Irradiance is not a normalization afterthought. In oxygen-band and related DISAMAR use cases it is part of the observation model:

- reflectance depends on radiance and irradiance together,
- operational runs may carry explicit high-resolution solar references,
- slit-function and sampling choices affect how the irradiance field should be interpreted.

For that reason the measurement-space product stores radiance and irradiance explicitly.

## Physical Scalars

`MeasurementSpaceProduct` also carries scalar summaries that are useful for exporters, validation, and retrieval diagnostics:

- effective air-mass factor,
- effective temperature and pressure,
- gas optical depth,
- CIA optical depth,
- aerosol optical depth,
- cloud optical depth,
- total optical depth,
- depolarization factor,
- temperature derivative of optical depth.

These scalars are not substitutes for the spectral product. They are compact physical summaries of how the spectrum was generated.

## Why Retrievals Share The Same Product

Using one common measurement-space interface has several advantages:

- transport code is implemented once,
- retrieval methods can be compared on the same forward product,
- exporters do not need to guess which observation-side quantities matter,
- validation can inspect spectral behavior directly instead of reverse-engineering it from method-specific outputs.

This is especially important for a codebase that needs to host multiple retrieval philosophies without forking the entire physical scene model.

## Exporter Relevance

The concrete exporters in `src/adapters/exporters/` consume the owned measurement-space product and associated provenance. They do not rerun transport, re-read operational inputs, or derive their own private forward-model summaries.

That keeps the serialization path honest: if an exported quantity matters scientifically, it should already exist in `Result`.

## Reading Order In Code

For one end-to-end path:

1. read `src/core/Engine.zig`,
2. read `src/kernels/optics/prepare.zig`,
3. read `src/kernels/transport/measurement_space.zig`,
4. read `src/core/Result.zig`,
5. read `src/retrieval/common/contracts.zig`,
6. inspect `src/retrieval/common/forward_model.zig` for the spectral evaluator path,
7. inspect `src/retrieval/common/surrogate_forward.zig` for the DOAS/DISMAS surrogate helper still used by those unfinished lanes,
8. then read the solver modules under `src/retrieval/oe/`, `src/retrieval/doas/`, and `src/retrieval/dismas/`.
