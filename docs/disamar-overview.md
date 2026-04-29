# DISAMAR Overview

## Model Family and Scope

DISAMAR, "Determining Instrument Specifications and Analysing Methods for Atmospheric Retrieval", is a radiative-transfer and retrieval model family for passive atmospheric remote sensing. The model-description paper by de Haan et al. (2022) places DISAMAR across ultraviolet, visible, near-infrared, and shortwave-infrared applications and identifies ozone-profile retrieval, visible-band NO2 retrieval, oxygen A-band cloud studies, and SWIR CO2 and fluorescence work as representative use cases.

The scientific lineage is broader than a single aerosol product. Recent literature documents:

- operational Sentinel-5P/TROPOMI ozone profiling and its geophysical validation,
- ongoing oxygen A-band aerosol-layer-height improvements, especially surface-reflection treatment,
- geometry-dependent surface-reflectivity climatologies used by cloud and greenhouse-gas retrieval chains, including methane-sensitive workflows.

In other words, DISAMAR should be understood as a mature scientific framework with a long operational and research pedigree, not as a one-off aerosol code.

## Historical Note

The model family was developed first in Fortran and has been used for instrument-definition studies, algorithm development, and operational Earth-observation processing. The documentation in this repository is about the current implementation in `zdisamar`: a typed forward model that preserves the scientific identity of DISAMAR while making state ownership and provenance explicit.

## Scientific Pedigree

Several aspects of the literature matter directly for this repository.

### Broad spectral and algorithmic range

The 2022 GMD model description presents DISAMAR as both a forward model and a retrieval system. That context matters even while this repository's retained public surface is centered on the O2 A forward model.

### Operational oxygen A-band work

The oxygen A-band has been central to cloud and aerosol studies for years. The 2015 Sentinel-5 Precursor aerosol-layer-height paper formalized an operational retrieval context in that band, while more recent work by de Graaf and co-authors (2025) shows that directional surface reflection is still an active scientific issue with operational consequences.

### Ozone-profile operations

The 2024 TROPOMI ozone-profile validation paper documents five years of operational ozone profiling in the Sentinel-5P processing chain, within the broader ESA and Copernicus operational context. The later 2025 harmonisation work shows that these ozone-profile records are part of an active cross-sensor atmospheric data record effort. That is important context for `zdisamar`: the implementation is not only about reproducing a numerical routine, but about supporting a model family that is already embedded in sustained satellite-product generation.

### Supporting surface and trace-gas infrastructure

The 2024 geometry-dependent Lambert-equivalent-reflectivity climatology paper is not only a surface-data paper. It also shows how the DISAMAR ecosystem contributes supporting data products for cloud and trace-gas retrieval chains, including greenhouse-gas applications such as methane.

## Core Method Families

The scientific vocabulary in the DISAMAR literature is specific. The main terms that appear throughout this repository are these.

The definitions below describe the scientific target vocabulary. They should not be read as a claim that every current Zig routine is already a method-faithful reproduction of that literature.

### Doubling-adding

Doubling-adding is a multiple-scattering method for layered atmospheres. Each atmospheric layer is represented through reflection, transmission, and source terms; larger stacks are then assembled by recursively combining layers. The method is attractive for satellite retrieval work because it handles strong multiple scattering in a numerically stable way while keeping layer interfaces explicit.

In the current Zig tree, the adding label identifies the doubling-adding radiative-transfer family. Public documentation should describe it as a radiative-transfer method, not as an implementation route.

### LABOS

LABOS stands for layer-based orders of scattering. In practical terms it is an order-of-scattering formulation organized layer by layer, which makes it useful when a full multiple-scattering solution is not the only quantity of interest and when controlled approximations, perturbations, or derivative-like diagnostics are needed. In the DISAMAR literature, doubling-adding and LABOS are complementary radiative-transfer methods rather than competing codebases.

In the current Zig tree, the LABOS-labeled path identifies the layer-based orders-of-scattering method family.

### Optimal estimation

Optimal estimation, usually in the Rodgers sense, combines a forward model, a prior state, and error statistics to solve an inverse problem. In DISAMAR-class retrievals this means the code must provide Jacobians, state-vector handling, consistent measurement-error treatment, posterior covariance, and averaging-kernel diagnostics.

The O2 A forward-model surface does not expose retrieval execution yet. OE remains important terminology for future retrieval-facing work.

### DOAS

DOAS, differential optical absorption spectroscopy, fits narrow-band differential absorption structures after broad spectral structure has been removed or parameterized. It is useful when the retrieval target is the fine spectral signature of trace-gas absorption rather than the full absolute radiance field.

The O2 A forward-model surface does not expose DOAS retrieval execution yet.

### DISMAS

DISMAS is the direct intensity fitting strategy described in the DISAMAR literature. Instead of isolating only differential structure, it works directly on the measured spectrum and therefore depends strongly on the quality of the forward model, sampling model, and derivative information.

The O2 A forward-model surface does not expose DISMAS retrieval execution yet.

## Why This Matters For `zdisamar`

The current implementation is organized around the retained O2 A forward model.

- `src/input/` carries the typed scene and observation description.
- `src/root.zig` carries the public `Input -> forward model -> Output` surface.
- `src/input/reference_data/` carries the scientific input surfaces needed to prepare execution without letting file I/O leak into numerical routines.
- `src/forward_model/` and `src/common/` carry numerical routines for optical-property preparation, radiative transfer, interpolation, quadrature, spectra, and linear algebra.

The important point is that DISAMAR in this repository is the scientific model family behind the forward model, not a claim that the rest of the system should inherit every trait of an earlier application layout.

## Operational Role

The acronym itself signals one historical purpose: instrument specifications and retrieval-method analysis. That heritage remains visible in current usage. DISAMAR-related work appears in the literature both as a retrieval forward model and as part of the scientific infrastructure around operational satellite products, especially in the Sentinel-5P/TROPOMI context used by European Earth-observation programmes.

For the present codebase, that means the implementation has to satisfy three conditions at once:

- it must describe the physics and retrieval language used in the papers;
- it must expose operational replacement surfaces such as slit functions, solar references, and spectroscopy lookup tables explicitly;
- it must keep provenance strong enough that a result can be tied back to its model family, radiative-transfer method, and reference data.

## Recommended Next Reads

After this overview:

1. Read [O2A Forward](./o2a-forward.md) for the retained public runtime path.
2. Read [Parity Harness](./parity-harness.md) for the bounded DISAMAR comparison workflow.
3. Read [Reference Data And Bundles](./reference-data-and-bundles.md) for the data-loading boundary.
4. Read [Validation and Scientific Scope](./validation-and-parity.md) for the current tested and validated contract envelope.
