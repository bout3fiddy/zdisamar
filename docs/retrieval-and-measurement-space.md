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

The repository currently exposes retrieval lanes for OE, DOAS, and DISMAS under `src/retrieval/`. They share contracts, priors, covariance handling, and synthetic-forward summary code while keeping method-specific policy separate.

### Optimal estimation

The OE path treats the problem as a state-estimation task with priors and derivative information. In practice this means the solver expects Jacobian support and works directly with a physically interpretable forward response.

### DOAS

The DOAS path emphasizes narrow-band differential structure. It still uses the same scene and observation contracts, but its solver policy is narrower and does not require the same derivative mode as OE or DISMAS.

### DISMAS

The DISMAS path fits directly in measurement space. That makes the fidelity of the forward product particularly important, because the method depends on the absolute shape of the simulated observation rather than only on differential structures.

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
6. inspect the solver modules under `src/retrieval/oe/`, `src/retrieval/doas/`, and `src/retrieval/dismas/`.
