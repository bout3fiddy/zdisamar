# DISAMAR Overview

## Model Family and Scope

DISAMAR, "Determining Instrument Specifications and Analysing Methods for Atmospheric Retrieval", is a radiative-transfer and retrieval model family for passive atmospheric remote sensing. The model-description paper by de Haan et al. (2022) places DISAMAR across ultraviolet, visible, near-infrared, and shortwave-infrared applications and identifies ozone-profile retrieval, visible-band NO2 retrieval, oxygen A-band cloud studies, and SWIR CO2 and fluorescence work as representative use cases.

The scientific lineage is broader than a single aerosol product. Recent literature documents:

- operational Sentinel-5P/TROPOMI ozone profiling and its geophysical validation,
- ongoing oxygen A-band aerosol-layer-height improvements, especially surface-reflection treatment,
- geometry-dependent surface-reflectivity climatologies used by cloud and greenhouse-gas retrieval chains, including methane-sensitive workflows.

In other words, DISAMAR should be understood as a mature scientific framework with a long operational and research pedigree, not as a one-off aerosol code.

## Historical Note

The model family was developed first in Fortran and has been used for instrument-definition studies, algorithm development, and operational Earth-observation processing. The documentation in this repository is about the current implementation in `zdisamar`: a typed execution model that preserves the scientific identity of DISAMAR while making state ownership, provenance, and extension boundaries explicit.

## Scientific Pedigree

Several aspects of the literature matter directly for this repository.

### Broad spectral and algorithmic range

The 2022 GMD model description presents DISAMAR as both a forward model and a retrieval system. That matters because the codebase must carry not only radiance simulation but also derivatives, inverse methods, and operational measurement handling.

### Operational oxygen A-band work

The oxygen A-band has been central to cloud and aerosol studies for years. The 2015 Sentinel-5 Precursor aerosol-layer-height paper formalized an operational retrieval context in that band, while more recent work by de Graaf and co-authors (2025) shows that directional surface reflection is still an active scientific issue with operational consequences.

### Ozone-profile operations

The 2024 TROPOMI ozone-profile validation paper documents five years of operational ozone profiling in the Sentinel-5P processing chain, within the broader ESA and Copernicus operational context. The later 2025 harmonisation work shows that these ozone-profile records are part of an active cross-sensor atmospheric data record effort. That is important context for `zdisamar`: the implementation is not only about reproducing a numerical kernel, but about supporting a model family that is already embedded in sustained satellite-product generation.

### Supporting surface and trace-gas infrastructure

The 2024 geometry-dependent Lambert-equivalent-reflectivity climatology paper is not only a surface-data paper. It also shows how the DISAMAR ecosystem contributes supporting data products for cloud and trace-gas retrieval chains, including greenhouse-gas applications such as methane.

## Core Method Families

The scientific vocabulary in the DISAMAR literature is specific. The main terms that appear throughout this repository are these.

In this repository, those names serve two different roles:

- they describe the literature families the project is trying to host,
- they also label the current transport and retrieval lanes, which are still surrogate implementations in several places.

So the definitions below describe the scientific target vocabulary. They should not be read as a claim that every current Zig kernel is already a method-faithful reproduction of that literature.

### Doubling-adding

Doubling-adding is a multiple-scattering method for layered atmospheres. Each atmospheric layer is represented through reflection, transmission, and source terms; larger stacks are then assembled by recursively combining layers. The method is attractive for satellite retrieval work because it handles strong multiple scattering in a numerically stable way while keeping layer interfaces explicit.

In the current Zig tree, the transport lane carrying the adding label is still a surrogate layered-scattering kernel. The name is preserved as a family label and routing seam, not as a claim of full doubling-adding fidelity.

### LABOS

LABOS stands for layer-based orders of scattering. In practical terms it is an order-of-scattering formulation organized layer by layer, which makes it useful when a full multiple-scattering solution is not the only quantity of interest and when controlled approximations, perturbations, or derivative-like diagnostics are needed. In the DISAMAR literature, doubling-adding and LABOS are complementary transport lanes rather than competing codebases.

In the current Zig tree, the LABOS-labeled lane is likewise still a surrogate transport path that preserves a typed route boundary while the numerics mature.

### Optimal estimation

Optimal estimation, usually in the Rodgers sense, combines a forward model, a prior state, and error statistics to solve an inverse problem. In DISAMAR-class retrievals this means the code must provide Jacobians, state-vector handling, consistent measurement-error treatment, posterior covariance, and averaging-kernel diagnostics.

The current OE-labeled solver in `zdisamar` now follows that Rodgers-style spectral-fit path. The remaining surrogate retrieval work is in the DOAS- and DISMAS-labeled lanes, not in OE.

### DOAS

DOAS, differential optical absorption spectroscopy, fits narrow-band differential absorption structures after broad spectral structure has been removed or parameterized. It is useful when the retrieval target is the fine spectral signature of trace-gas absorption rather than the full absolute radiance field.

The current DOAS-labeled solver preserves the typed route and observation contract for that family, but it remains a surrogate implementation today.

### DISMAS

DISMAS is the direct intensity fitting strategy described in the DISAMAR literature. Instead of isolating only differential structure, it works directly in measurement space and therefore depends strongly on the quality of the forward operator, sampling model, and derivative information.

The current DISMAS-labeled solver is also still a surrogate implementation. Its value today is that it preserves the direct-measurement-space seam and provenance route while the method-specific numerics remain under active construction.

## Why This Matters For `zdisamar`

The current implementation is organized around the consequences of those method families.

- `src/model/` carries one canonical scene and observation description.
- `src/kernels/transport/` carries forward-operator families and measurement-space evaluation.
- `src/retrieval/` carries OE-, DOAS-, and DISMAS-labeled retrieval layers on shared contracts.
- `src/runtime/reference/` and `src/adapters/` carry the scientific input surfaces needed to prepare execution without letting file I/O leak into kernels.
- `src/plugins/` carries capability registration and extension boundaries for transport, retrieval, surface, instrument, and exporter lanes.

The important point is that DISAMAR in this repository is the scientific model family hosted by the engine, not a claim that the rest of the system should inherit every trait of an earlier application layout.

## Operational Role

The acronym itself signals one historical purpose: instrument specifications and retrieval-method analysis. That heritage remains visible in current usage. DISAMAR-related work appears in the literature both as a retrieval engine and as part of the scientific infrastructure around operational satellite products, especially in the Sentinel-5P/TROPOMI context used by European Earth-observation programmes.

For the present codebase, that means the implementation has to satisfy three conditions at once:

- it must describe the physics and retrieval language used in the papers;
- it must expose operational replacement surfaces such as slit functions, solar references, and spectroscopy lookup tables explicitly;
- it must keep provenance strong enough that a result can be traced back to its model family, route, reference data, and capability inventory.

## Recommended Next Reads

After this overview:

1. Read [Architecture and Execution Model](./zig-architecture.md) for the system-level layout.
2. Read [Operational O2 A-Band Path](./operational-o2a.md) for the main operational science path.
3. Read [Plugins and Extension Boundaries](./plugins-and-extension-boundaries.md) for the capability system.
4. Read [Validation and Scientific Scope](./validation-and-parity.md) for the current tested and validated contract envelope.
