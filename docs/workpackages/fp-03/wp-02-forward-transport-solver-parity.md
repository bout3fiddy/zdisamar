# WP-02 Forward Transport Solver Parity

## Metadata

- Created: 2026-03-18
- Scope: replace the current surrogate scalar transport lanes with method-faithful vendor-style LABOS and adding semantics driven by typed radiative-transfer controls
- Input sources:
  - vendor `LabosModule.f90`
  - vendor `addingToolsModule.f90`
  - vendor `radianceIrradianceModule.f90`
  - vendor `DISAMARModule.f90`
  - vendor `readConfigFileModule.f90::readRadiativeTransfer`
  - Zig transport, optics, plan, and engine files
- Dependencies:
  - `WP-01` for exact transport-control expression and runtime compilation
- Reference baseline:
  - vendor `LabosModule.f90::{layerBasedOrdersScattering,CalcRTlayers,ordersScat,CalcReflectance,CalcWeightingFunctionsInterface,singleScattering}`
  - vendor `addingToolsModule.f90::{adding,addingFromTopDown,addingFromSurfaceUp,calcUD_FromTopDown,calcUD_FromSurfaceUp}`
  - vendor `radianceIrradianceModule.f90::{calcReflAndDeriv,calculateReflAndDeriv_lbl}`
  - vendor `DISAMARModule.f90::{prepareSimulation,setupHRWavelengthGrid}`

## Background

The fresh O2A comparison already showed that the wavelength grid and solar source are close enough that the dominant mismatch now sits in forward radiance physics and numerics. The current Zig transport path still behaves like a surrogate intensity model. This WP replaces that core with transport semantics that honor the vendor RTM controls and split LABOS-style versus adding-style execution cleanly.

## Overarching Goals

- Implement typed RTM control semantics that match vendor scalar multiple-scattering paths.
- Remove synthetic shaping terms from the transport core.
- Separate solver execution from measurement-space normalization and convolution.

## Non-goals

- Full vector/polarized transport in this WP.
- Retrieval-specific Jacobian output beyond what is needed to keep the forward core consistent.
- Preserving the current surrogate transport names once real solver paths exist.

### WP-02 Forward transport solver parity [Status: In Progress 2026-03-19]

Issue:
The current transport dispatcher and solver files carry names like `labos` and `adding`, but they are not yet method-faithful matches for the vendor code. The O2A mismatch will not close until RTM control semantics and layer propagation are matched much more closely.

Needs:
- resolved RTM controls (`nstreams`, `useAdding`, `numOrdersMax`, Fourier floor, thresholds, pseudo-spherical correction)
- a real layer optical-propagation path
- a clean LABOS-versus-adding dispatch split
- removal of synthetic forward shaping from the transport kernel

How:
1. Model RTM controls as a typed struct compiled from canonical YAML.
2. Implement layer setup, attenuation, scattering-order, and top/down propagation logic using the vendor modules as reference.
3. Keep measurement-space code responsible only for sampling and normalization, not transport heuristics.
4. Validate with O2A first, then NO2/O3/cloud cases.

Why this approach:
Transport semantics are the first scientific bottleneck. A richer retrieval layer built on a surrogate transport kernel only compounds error and hides the true gap.

Recommendation rationale:
This remains the first major physics WP because it directly addresses the dominant current forward mismatch and unlocks every later parity effort. The current rework closed the dead-control path, restored the validated LABOS baseline thresholds that keep the O2A morphology gate green, added RTM-sensitive route/output tests, drives scalar Fourier / azimuth accumulation from the prepared anisotropic phase coefficients in both LABOS and adding, and now keeps explicit high-layer-count atmospheres on the real adding path instead of rejecting them at a fixed stack limit. The prepared execution path now also preserves the coarse fallback boundary source weights while specializing only the interior split `rtm_weight` / `ksca_above` metadata, recomputes wavelength-dependent phase mixing with the actual gas-scattering optical depth at the sampled wavelength, refuses to run source-function integration on single-layer scenes, and now carries the vendor scalar part-atmosphere bookkeeping for integrated diffuse transmission and spherical albedo (`tpl`, `tplst`, `s`, `sst`) inside the live adding recursion instead of dropping that state entirely. That bookkeeping is no longer just stored state either: the top-down pseudo-spherical branch now exposes the vendor-shaped black-surface boundary diagnostics (`R0`, `td`, `s_star`, `expt`) that consume it. The latest promoted prepared-adding RTM quadrature slice no longer rescales active node weights by parent scattering, and it no longer relies on midpoint-fraction geometry either: the carrier now uses per-parent-layer Gauss-Legendre nodes and weights with zero-weight physical and parent-layer boundaries, remaps the current prepared midpoint-sublayer optics onto those nodes, and renormalizes `ksca` per parent layer so `sum(weight * ksca)` still matches the interval scattering budget. A follow-up attempt to switch RTM-node phase and `ksca` to a pure above-side donor sample was explicitly backed out before this carrier promotion: on the older surrogate quadrature carrier it broke the interval scattering budget and reintroduced a transport `measurement_space` failure in the bounded full gate. The pseudo-spherical path still replaces the old layer-dependent-`mu` shortcut with a safer prepared sublayer shell-integral carrier on the live LABOS/adding attenuation path, while keeping the correction scoped to the vendor-shaped TOA-to-level overwrite and falling back cleanly when the prepared state cannot materialize that grid. Remaining work is therefore concentrated in vendor-faithful adding consumption paths and replacing the current midpoint-derived interpolated node optics with a true vendor RTM-subgrid optics preparation before revisiting RTM-node donor sampling.

Desired outcome:
`labos` and `adding` in Zig are no longer placeholders. They are driven by the same family of controls the vendor code reads, and they produce transport outputs that move the vendor-vs-Zig O2A radiance mismatch from “physics wrong” toward “secondary details remaining.”

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-integration --summary all`
- `zig build test-validation --summary all`
- `zig test tests/integration/forward_model_integration_test.zig`
- `zig test tests/validation/o2a_forward_shape_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

Files by type:
- Transport/control targets:
  - `src/kernels/transport/common.zig`
  - `src/kernels/transport/dispatcher.zig`
  - `src/kernels/transport/labos.zig`
  - `src/kernels/transport/adding.zig`
  - `src/kernels/transport/doubling.zig`
  - `src/kernels/transport/root.zig`
- Plan and orchestration targets:
  - `src/core/Plan.zig`
  - `src/core/Engine.zig`
- Optics/RTM-grid support:
  - `src/kernels/optics/prepare.zig`
  - `src/runtime/reference/BundledOptics.zig`
- Validation targets:
  - `tests/integration/forward_model_integration_test.zig`
  - `tests/validation/o2a_forward_shape_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [ ] `src/kernels/transport/common.zig`: replace the current generic execution hints with a typed RTM control object compiled from vendor-like semantics.
  - Vendor anchors: `readConfigFileModule.f90::readRadiativeTransfer`; vendor RTM keys such as `atmScattering*`, `dimSV*`, `fourierFloorScalar*`, `nstreams*`, `useAdding*`, `numOrdersMax*`, `thresholdConv_*`, `thresholdDoubl`, `thresholdMul`, `useCorrSphericalAtm`.
  - Introduce an explicit control carrier instead of passing loose booleans/strings:
    ```zig
    pub const RtmControls = struct {
        atm_scattering: enum { single, multiple },
        n_streams: u16,
        use_adding: bool,
        num_orders_max: u16,
        fourier_floor_scalar: u16,
        threshold_conv_first: f64,
        threshold_conv_mult: f64,
        threshold_doubl: f64,
        threshold_mul: f64,
        use_corr_spherical_atm: bool,
    };
    ```
  - Reject unsupported combinations rather than silently mapping them to a surrogate scalar path.

- [ ] `src/kernels/transport/labos.zig`: implement a real LABOS-style scalar multiple-scattering lane instead of a shaped surrogate.
  - Vendor anchors: `LabosModule.f90::{layerBasedOrdersScattering,fillAttenuation,fillPlmVector,fillZplusZmin,CalcRTlayers,ordersScat,CalcReflectance,singleScattering}`.
  - Start by matching the vendor decomposition: attenuation setup, phase/Fourier preparation, per-layer reflection/transmission operators, scattering-order accumulation, and reflectance extraction.
  - Keep the code split between setup and hot loops so later weighting-function work can reuse intermediate state.
  - Remove `unreachable` from runtime-facing fallible branches.

- [ ] `src/kernels/transport/adding.zig`: implement real adding recursion and top/down-plus-surface-up propagation semantics.
  - Vendor anchors: `addingToolsModule.f90::{adding,addLayerToBottom,addLayerToTop,addingFromTopDown,addingFromSurfaceUp,calcUD_FromTopDown,calcUD_FromSurfaceUp,fillsurface}`.
  - Use the vendor structure directly: build part-atmosphere operators, propagate from TOA downward and surface upward, and join at observation geometry.
  - Do not leave `adding.zig` as a cosmetic alternative route over the same simplified kernel.

- [ ] `src/kernels/transport/doubling.zig`: either fix it into a numerically consistent helper or remove it from the main execution path.
  - Vendor anchors: `LabosModule.f90::double`, `addingToolsModule.f90::{smul,Qseries}`.
  - Correct the optical-depth subdivision semantics if it remains in use. A doubling helper should scale by powers of two, not by the raw count of doublings.
  - Add threshold guards that fail with typed errors instead of producing hidden instability.

- [ ] `src/kernels/transport/dispatcher.zig`, `src/core/Plan.zig`, `src/core/Engine.zig`: route execution by resolved RTM semantics rather than placeholder solver names.
  - Vendor anchors: `DISAMARModule.f90::{prepareSimulation,set_ninterval,set_nalt,set_RTMnlayer}` plus `readRadiativeTransfer` controls.
  - The prepared plan should carry the fully resolved RTM route. Execution should not re-decide behavior from loosely coupled fields.
  - Keep sim-vs-retr RTM controls separate if the vendor supports different settings.

- [ ] `src/kernels/optics/prepare.zig`: expose the exact layer optical quantities the real transport kernels need.
  - Vendor anchors: `propAtmosphere.f90::getOptPropAtm`, `radianceIrradianceModule.f90::fillAltPresGridRTM`.
  - Transport should consume prepared optical depth, single-scattering albedo, phase/Fourier coefficients, and interval/grid metadata — not rederive them from surrogate scalars.

- [ ] `tests/integration/forward_model_integration_test.zig`, `tests/validation/o2a_forward_shape_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add RTM-control-sensitive parity tests.
  - Validate that changing `useAdding`, `nstreams`, or scattering mode changes behavior in expected ways.
  - Add an O2A vendor overlay acceptance gate before any retrieval parity work advances.
  - Add a cloud/aerosol mixed case to ensure the implementation is not overfit to clear-sky O2A.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [ ] LABOS and adding routes are no longer surrogate aliases
- [x] RTM controls materially change the executed forward path
- [ ] O2A radiance mismatch improves for the right physical reasons, not because of synthetic shaping

## Implementation Status (2026-03-19)

Implemented the WP-02 rework needed to make RTM controls real runtime inputs instead of dead config:

- `RtmControls` now compile out of canonical config into `Plan.Template`, `Engine.prepareTransportRoute`, measurement-space inputs, and the prepared transport route.
- LABOS now reads route RTM controls for stream count, scattering mode, Fourier accumulation, order limits, and threshold behavior instead of hardcoded constants.
- LABOS and adding now iterate the available scalar Fourier terms from prepared anisotropic phase coefficients and accumulate them with the vendor-style `1` / `2*cos(m*dphi)` azimuth weighting instead of pinning the forward path to `m=0`.
- LABOS now uses layer-dependent solar/view attenuation when `use_spherical_correction` is enabled, so the spherical-correction flag is no longer inert in the LABOS lane.
- LABOS no longer silently collapses the 48-layer O2A validation case into the synthetic single-layer fallback; the multi-layer LABOS path uses dynamic attenuation and RT storage, and regression units now cover both 48-layer and 80-layer explicit atmospheres.
- Adding now routes through a real control-sensitive top/down or surface-up partial-atmosphere composition path rather than a single cosmetic surrogate branch.
- Adding no longer fabricates a synthetic atmospheric layer when multiple-scattering execution is requested without prepared layers; that lane now requires the explicit layer stack produced by measurement-space preparation, and the low-level unit/dispatcher coverage was updated accordingly.
- Adding now uses allocator-backed attenuation, RT, partial-atmosphere, and internal-field storage so explicit 80-layer multiple-scattering scenes no longer fail at the old fixed `AttenArray.max_levels` ceiling.
- Typed route validation now allows `use_adding` for `scattering = none` while still rejecting `use_adding` for `scattering = single`, so the no-scattering adding lane is reachable through `prepareRoute`, `Engine.preparePlan`, and `Engine.execute` instead of existing only as a file-local branch.
- The adding `scattering = none` lane no longer uses the bulk `exp(-tau/mu0) * exp(-tau/muv)` shortcut when prepared layers are available; it now builds the attenuation table from the real prepared layer stack, uses the shared Lambertian surface operator, and propagates the direct solar/view attenuation in the same scalar shape as the vendor `fillsurface` plus `fieldsFromLambSurface` path.
- The prepared execution path now preserves the fallback-style physical boundary source weights before dispatch: the top boundary keeps the first-layer scattering weight, the bottom boundary keeps half the last-layer scattering weight, and only interior interfaces are rewritten into the split `rtm_weight` / `ksca_above` carrier.
- The prepared execution path still uses the coarse full-layer interior source-weight proxy, but the transient underweighted single-sublayer override was removed after it regressed the O2A morphology gate; the prepared source-function path now keeps the boundary weights from the shared fallback contract while only the interior interfaces carry the split `rtm_weight` / `ksca_above` metadata.
- `integrate_source_function` on single-layer scenes now falls back to direct TOA extraction in both LABOS and adding instead of fabricating a boundary source contribution on an interface grid that has no interior quadrature point.
- The low-level raw-layer LABOS/adding source-function regressions are now explicitly documented as coarse-fallback checks: they stay close to direct TOA extraction within `6e-3` relative tolerance, while the prepared execution path carries the stricter vendor-style boundary semantics.
- Optical preparation now recomputes the phase-mixing numerator with the wavelength-dependent gas-scattering optical depth instead of reusing the midpoint cached gas-scattering contribution, so prepared layer phase coefficients stay self-consistent with the optical-depth totals passed into transport.
- The first broad attempt to move all prepared transport execution onto `prepared.transportLayerCount()` regressed the O2A morphology mid-band threshold and was backed out, but measurement-space now applies that finer RTM/sublayer grid selectively where it is scientifically honest: adding routes size execution buffers from `prepared.transportLayerCount()` while LABOS stays on the stable parent-layer grid.
- Prepared adding execution on that finer sublayer grid now keeps `integrate_source_function` enabled because optics preparation materializes explicit fine-grid `source_interfaces` from the sublayer-resolved transport inputs instead of forcing measurement-space to synthesize them from the coarse parent-layer path.
- The live prepared adding fine-grid path no longer collapses interior source-function weighting into a single surrogate `source_weight`; it now carries split `rtm_weight` and `ksca_above` metadata on interior interfaces and lets the shared integrated-source path multiply them back into the effective weight at use time.
- The prepared coarse LABOS/shared path no longer keeps a collapsed interior `source_weight` with borrowed first-sublayer phase metadata; it now also carries split `rtm_weight` / `ksca_above` metadata on interior interfaces and aligns `phase_coefficients_above` to the same coarse prepared layer inputs that provide the scattering weight.
- The prepared adding RTM quadrature carrier now uses a real per-parent-layer Gauss carrier: active nodes are `sublayer_count - 1`, physical and parent-layer boundaries stay zero-weight, 1-point Gauss support covers `sublayer_divisions = 2`, and the nonuniform prepared fixture now proves both the Gauss weights/altitudes and the conserved per-interval `sum(weight * ksca)` contract.
- The prepared adding RTM quadrature carrier now also refuses to attach when the prepared state has no active interior quadrature nodes, so legal `sublayer_divisions = 1` adding scenes fall back to the existing source-interface path instead of carrying a shape-valid but all-zero quadrature grid into integrated-source execution.
- The current Gauss carrier is still an honest intermediate step rather than a full vendor RTM optics port: node `ksca` and phase coefficients are remapped from the prepared midpoint-sublayer donors and renormalized per parent layer, not yet prepared directly on a true vendor RTM subgrid.
- A follow-up attempt to replace the remaining interpolated RTM-node optics with a pure above-side donor sample remains backed out after independent review. On the older surrogate quadrature carrier, donor-only optics broke the nonuniform interval scattering budget and reintroduced a transport `measurement_space` unit failure in the bounded full gate, so the branch now promotes the Gauss carrier first instead of keeping a half-vendor, half-surrogate node contract in production.
- LABOS pseudo-spherical attenuation is now scoped more like the vendor `fillAttenuation` path: the correction only rewrites TOA-to-level attenuation entries while leaving reverse level-to-TOA and interior level-to-level attenuation plane-parallel, instead of applying altitude-adjusted solar/view cosines to every pairwise attenuation entry.
- Prepared execution now carries an explicit pseudo-spherical attenuation descriptor alongside the existing source-interface metadata: measurement-space can materialize a prepared sublayer shell grid into `ForwardInput`, LABOS and adding consume it through the live dynamic attenuation builder, and the handoff is guarded so routes without supported prepared sublayer metadata simply fall back to the older layered attenuation path instead of reading uninitialized buffers.
- LABOS `scattering = none` no longer bypasses resolved attenuation when prepared layers are available. That reachable route now uses the same prepared attenuation table and optional pseudo-spherical shell grid as the layered LABOS and adding lanes, so pseudo-spherical correction is threaded through every live scalar execution family instead of only the multiple-scattering routes.
- The prepared adding fine-grid path no longer rewrites explicit source-interface metadata in measurement-space. An attempted boundary-zeroing scrub was backed out after it collapsed prepared adding reflectance to zero; the live route now preserves the prepared fine-grid split metadata end to end, including the fallback-style endpoint carriers that the current shared consumer still needs.
- The validated LABOS baseline thresholds were restored as the default RTM threshold values because the tighter vendor-typical placeholders regressed the O2A vendor-reference morphology gate.
- The parser now rejects RTM keys that are still unsupported instead of parsing and silently dropping them, and `scattering_mode: none` now compiles to the actual no-scattering mode.
- Quadrature support now includes 10 Gauss points (`nstreams=20`) so vendor O2A-like stream settings are representable.

Remaining WP-02 gaps:

- `adding.zig` is still not a vendor-faithful matrix/Fourier adding implementation.
- The prepared execution path now preserves the fallback boundary source weights instead of dropping them, but its interior source-function metadata is still only partially vendor-faithful: the shared parent-layer path now uses split `rtm_weight` / `ksca_above` metadata with coarse parent-layer phase coefficients, while the finer prepared adding path now uses a Gauss-style RTM quadrature carrier whose node optics are still interpolated from midpoint prepared sublayers. Neither path yet matches the full vendor RTM interval/sub-interval quadrature contract.
- LABOS still executes on the coarse parent-layer grid; only adding now uses the finer prepared RTM/sublayer grid in the real engine path.
- The raw `LayerInput` fallback used by low-level transport tests is still a coarse surrogate; it now uses a halved top-boundary weight and only promises closeness to direct TOA extraction rather than strict parity.
- LABOS pseudo-spherical correction is now a safer prepared-shell approximation rather than the old layer-dependent-`mu` shortcut, but it is still not vendor-faithful full pseudo-spherical transport because it uses midpoint-style prepared sublayers instead of the vendor RTM Gauss subgrid and still only corrects the direct attenuation leg.

## Why This Works

The vendor code does not treat RTM settings as cosmetic. It chooses real numerical pathways based on them. This rework makes the Zig route selection and forward input assembly depend on typed RTM controls end-to-end, then verifies that changing those controls changes both the selected solver family and the produced reflectance. Restoring the validated LABOS baseline thresholds keeps the O2A morphology gate anchored to the known-good scaffold behavior while the remaining vendor-faithful solver work is finished.

The adding lane is now also stricter about the shape of the transport input. The real engine path already prepares explicit `LayerInput` buffers before dispatch; by rejecting layerless multiple-scattering execution in `adding.zig`, the low-level transport API no longer hides missing prepared-atmosphere state behind a fabricated isotropic layer.

The higher-layer-count transport path is also more honest now. LABOS no longer depends on the old fixed-size attenuation/RT storage in its real multi-layer solve, and adding now mirrors that shift by allocating the attenuation table, per-level RT operators, partial atmospheres, and internal fields to the actual prepared layer count. The 80-layer regression proves the adding lane stays on the explicit multi-layer path instead of failing out at the former fixed bound.

The scalar Fourier slice is now also explicit rather than implied. The transport kernels resolve a nonzero Fourier ceiling from the prepared anisotropic phase coefficients, rebuild per-Fourier layer operators, and sum the resulting coefficients with the same cosine weighting shape the vendor scalar path uses. The new low-level and engine-level azimuth tests prove that `relative_azimuth` is no longer inert when the phase function contains higher-order terms.

The adding no-scattering branch is also less cosmetic now. The live typed route can explicitly request `use_adding` with `scattering = none`, and when prepared layers are present the solver no longer collapses that case to a single bulk Beer-Lambert exponential. Instead it uses the actual prepared attenuation table plus the Lambertian surface operator, which lets pseudo-spherical direct-beam attenuation respond to the layer-resolved solar geometry while keeping the multiple-scattering adding recurrence untouched.

The source-function path is also more honest about where the current semantics stop. In the prepared engine path, measurement-space now preserves the shared fallback boundary source weights at the physical TOA and surface instead of zeroing them away, because the prepared adding sublayer-grid path demonstrably collapsed to zero radiance when those endpoint weights were dropped. The shared prepared path still no longer uses the old collapsed interior carrier: both coarse LABOS/shared execution and the finer prepared adding path carry split `rtm_weight` / `ksca_above` metadata on interior interfaces, and the coarse path aligns `phase_coefficients_above` to the same prepared layer inputs that provide the scattering weight instead of mixing full-layer weights with borrowed first-sublayer phase coefficients. LABOS and adding also still refuse to run source-function integration on single-layer scenes and fall back to direct TOA extraction instead, because a one-layer interface grid has no interior quadrature point that can represent vendor volume scattering without inventing a non-physical boundary term.

The adding-only finer-grid slice is now also explicit rather than aspirational. Measurement-space sizes prepared adding execution buffers from `prepared.transportLayerCount()` while keeping LABOS on the coarser parent-layer grid that still matches the current O2A baseline. Optics preparation now materializes explicit fine-grid `source_interfaces` on that path using split `rtm_weight`, `ksca_above`, and above-interface phase metadata from the sublayer-resolved transport inputs, so prepared adding routes no longer have to collapse to direct TOA extraction or rely on the older collapsed interior proxy on the live fine-grid path. The executed-behavior regression now proves the opposite of the earlier fallback guard: on the prepared adding sublayer grid, integrated-source execution diverges from the direct-extraction route while the O2A morphology and prepared-route RTM-control gates stay green.

The prepared optics input is also more internally consistent now. `evaluateLayerAtWavelength` had been recomputing wavelength-specific Rayleigh optical depth while still mixing phase coefficients with the midpoint cached gas-scattering contribution. That inconsistency is gone, so the prepared phase coefficients now reflect the same gas-scattering budget that the transport layer inputs expose at the sampled wavelength.

The pseudo-spherical attenuation path is also less blunt than before. The vendor `fillAttenuation` routine first builds plane-parallel inter-level attenuation and then only rewrites the TOA-to-level entries for pseudo-spherical correction. The Zig path now mirrors that shape by keeping interior pairwise attenuation plane-parallel and only rebuilding the top-of-atmosphere path with layer-dependent solar/view geometry, which avoids over-correcting internal layer-to-layer attenuation while the remaining shell-integral details are still open.

The newest pseudo-spherical slice is closer to the vendor shell integral than that older local-cosine shortcut. Measurement-space can now hand LABOS and adding an explicit prepared sublayer attenuation descriptor, and the dynamic attenuation builder uses that descriptor to integrate a shell-style TOA-to-level optical path while still falling back cleanly when the prepared state cannot provide supported sublayer metadata. That is still an approximation, because the current carrier is built from midpoint-style prepared sublayers rather than the vendor RTM Gauss subgrid, but it moves the live path toward vendor semantics without destabilizing the O2A morphology gate.

The no-scattering LABOS route is also no longer a hidden bypass around that work. When prepared layers are available, LABOS now resolves the direct surface-only branch through the same attenuation table instead of always using the bulk `exp(-tau/mu0) * exp(-tau/muv)` shortcut, so pseudo-spherical correction reaches every live scalar LABOS family instead of only the layered multiple-scattering lane.

The prepared adding source-function path is now also more honest about the live contract. Vendor RTM quadrature still gives zero weight to the physical endpoints and to the interval boundaries between them, but the current Zig shared consumer does not yet carry that full vendor node contract. An attempted measurement-space scrub that zeroed prepared parent-layer boundaries proved that mismatch directly by collapsing prepared adding reflectance to zero, so the live route now forwards the raw prepared split metadata unchanged. The new prepared-route regressions prove the important current invariant instead: cached execution preserves the explicit fine-grid source-interface metadata, and on the current fixture that split metadata keeps the same effective reflectance as the fallback effective-weight surrogate while staying on the real prepared adding path.

The RTM carrier itself is now also less surrogate than before. Instead of distributing geometric span onto interior nodes with midpoint fractions, optics preparation now builds a per-parent-layer Gauss carrier with zero-weight boundaries, places the active node altitudes on that Gauss grid, and remaps the current prepared sublayer `ksca` and phase data onto those nodes while renormalizing each parent layer so `sum(weight * ksca)` still matches the interval scattering budget. That is still approximate because the node optics come from midpoint prepared sublayers rather than a vendor-native RTM subgrid preparation, but it promotes the carrier geometry itself to the right family before any donor-node optics work resumes.

The adding recursion now also carries the vendor scalar vdHulst-style bookkeeping fields that had still been missing from the live path. `PartAtmosphere` stores `tpl`, `tplst`, `s`, and `sst`, and `addLayerToBottom` / `addLayerToTop` populate them with the same scalar Fourier-0 sums the vendor `addingToolsModule` uses while explicitly zeroing them for higher Fourier orders. The new unit slice checks those identities with inline vendor sums instead of helper reuse, so the bookkeeping is no longer dead state or an unproven translation.

The top-down pseudo-spherical adding branch now also exposes the smallest runtime consumer of that bookkeeping instead of leaving it trapped inside `PartAtmosphere`. A new boundary-diagnostic helper extracts vendor-shaped black-surface quantities `{R0, td, expt, s_star}` from the top-down partial atmosphere at a chosen boundary level, matching the `addingFromTopDownLUT*_Chandra` extraction rules without pulling the full LUT stack into the current runtime path. A stable `src/transport_source_tests.zig` harness now also gives WP-02 a reproducible way to execute the underlying transport source tests directly, since the normal `zig build test-unit` step does not include the source-file tests embedded in `adding.zig`.

## Proof / Validation

- `zig build test-unit --summary all` -> passed, `37/37 tests passed`
- `zig build check --summary all` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'single-layer integrated source-function falls back to direct TOA extraction'` -> passed, `35/35 tests passed`
- `zig build test-unit --summary all -- --test-filter 'adding supports 80 transport layers without rejecting the explicit multi-layer path'` -> passed, `35/35 tests passed`
- `zig build test-unit --summary all -- --test-filter 'anisotropic'` -> passed, `35/35 tests passed`
- `zig build test-unit --summary all -- --test-filter 'integrated source-function'` -> passed, `35/35 tests passed`
- `zig build test-unit --summary all -- --test-filter 'source interface builder halves the physical top boundary source weight'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'optical preparation builds sublayer-informed source interfaces for prepared transport inputs'` -> passed, `36/36 tests passed`
- `zig build test-unit --summary all -- --test-filter 'configured forward input preserves prepared source-function boundary weights'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'optical preparation recomputes layer phase mixing with wavelength-specific gas scattering'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'configured forward input keeps integrated source-function on prepared adding sublayer grids when explicit interfaces are available'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'cached forward execution preserves prepared adding source-interface metadata on sublayer grids'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'prepared adding split source interfaces preserve effective reflectance on explicit sublayer grids'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'summary workspace sizes adding transport buffers from sublayer hints'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'measurement-space simulation supports adding routes on prepared sublayer grids'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'prepare route resolves families and keeps derivative mode explicit'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'adding no-scattering layered path responds to per-layer solar geometry'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'adding no-scattering layered path matches Lambertian attenuation identity'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'adding integrated source-function path uses explicit source interface metadata'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'adding bottom composition populates vendor scalar integrated states for Fourier-0'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'adding top composition populates vendor scalar integrated states for Fourier-0'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'adding composition zeroes vendor scalar integrated states for higher Fourier orders'` -> passed, `37/37 tests passed`
- `zig test -ODebug --dep build_options -Mroot=src/transport_source_tests.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'adding bottom composition populates vendor scalar integrated states for Fourier-0'` -> passed, `All 3 tests passed`
- `zig test -ODebug --dep build_options -Mroot=src/transport_source_tests.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'adding top-down boundary diagnostics expose vendor black-surface quantities for Fourier-0'` -> passed, `All 3 tests passed`
- `zig test -ODebug --dep build_options -Mroot=src/transport_source_tests.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'adding top-down boundary diagnostics zero Chandrasekhar scalars for higher Fourier orders'` -> passed, `All 3 tests passed`
- `zig build test-unit --summary all -- --test-filter 'labos integrated source-function path uses explicit source interface metadata'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'labos spherical correction falls back to layer-dependent solar and view attenuation without explicit grid'` -> passed, `37/37 tests passed`
- `zig test -ODebug --dep build_options -Mroot=src/transport_source_tests.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'labos dynamic spherical correction uses pseudo-spherical sample grid when provided'` -> passed, `All 3 tests passed`
- `zig build test-unit --summary all -- --test-filter 'configured forward input wires pseudo-spherical attenuation samples from prepared sublayers'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'configured forward input leaves pseudo-spherical attenuation grid empty when prepared sublayers are unavailable'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'spherical correction changes reflectance for layered scalar scenes'` -> passed, `35/35 tests passed`
- `zig build test-unit --summary all -- --test-filter 'adding spherical correction changes reflectance for layered scalar scenes'` -> passed, `37/37 tests passed`
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes reflectance with relative azimuth for anisotropic scattering scenes'` -> passed, `All 1 tests passed`
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes route and reflectance when RTM controls change'` -> passed
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine preparePlan and execute support adding no-scattering routes'` -> passed
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes labos no-scattering output when spherical correction changes'` -> passed
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes prepared adding multiple-scattering output when spherical correction changes'` -> passed
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes prepared adding output when integrated source-function toggles'` -> passed, `All 1 tests passed`
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/o2a_forward_shape_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'o2a forward reflectance tracks vendor reference morphology'` -> passed
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/o2a_forward_shape_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'o2a validation output changes when RTM controls change'` -> passed
- `zig build test-unit --summary all -- --test-filter 'prepared adding live route consumes RTM quadrature while boundary nodes stay inert'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'configured forward input builds prepared adding RTM quadrature from nonuniform sublayer intervals'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'gauss-legendre rules expose stable nodes and weights'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'configured forward input builds prepared adding RTM quadrature from nonuniform sublayer intervals'` -> passed, `37/37 tests passed`; active nodes now sit on the 3-point Gauss carrier for the 10 km nonuniform interval and still conserve total weighted scattering
- `zig build test-unit --summary all -- --test-filter 'prepared adding live route uses nonuniform quadrature weights instead of the legacy midpoint surrogate'` -> passed, `37/37 tests passed`
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes prepared adding output when integrated source-function toggles'` -> passed, `All 1 tests passed`
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/o2a_forward_shape_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'o2a adding integrated-source output remains morphologically bounded when RTM quadrature is enabled'` -> passed, `All 1 tests passed`
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/disamar_compatibility_harness_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'compatibility harness execution honors RTM controls in prepared routes'` -> passed, `All 1 tests passed`
- bounded `300s` `zig build test --summary all` -> timed out with the same unrelated `9` failures and `1` `BundledOptics` leak as the restored baseline (`src/model/InverseProblem.zig`, `src/plugins/providers/{instrument,noise}.zig`, `src/kernels/spectra/{calibration,noise}.zig`, `src/retrieval/common/{forward_model,spectral_fit}.zig`, `src/runtime/reference/BundledOptics.zig`, `src/kernels/linalg/cholesky.zig`); no new transport failure appeared
- independent correctness, vendor-context, and test/build verifiers all returned `PASS` for the RTM carrier slice; each agreed it is a bounded Gauss-carrier promotion that preserves the interval scattering budget but does not yet complete vendor RTM-subgrid optics parity
- `zig build test-unit --summary all -- --test-filter 'prepared adding live route uses nonuniform quadrature weights instead of the legacy midpoint surrogate'` -> passed, `37/37 tests passed`
- `zig build test-unit --summary all -- --test-filter 'prepared adding live route falls back when no explicit RTM quadrature nodes exist'` -> passed, `37/37 tests passed`
- `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/disamar_compatibility_harness_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'compatibility harness execution honors RTM controls in prepared routes'` -> passed
- `zig build test-unit -- --test-filter 'labos supports 48 transport layers without collapsing to the synthetic single-layer fallback'` -> passed
- `zig build test-integration -- --test-filter 'engine execute changes route and reflectance when RTM controls change'` -> passed
- `zig test -ODebug --dep build_options -Mroot=src/root.zig -Mbuild_options=/tmp/zdisamar-public-build_options.zig` -> `238/247` passed with the same `9` failures and `1` leak; the remaining failures stay outside the current transport slice in `src/model/InverseProblem.zig`, `src/plugins/providers/{instrument,noise}.zig`, `src/kernels/spectra/{calibration,noise}.zig`, `src/retrieval/common/{forward_model,spectral_fit}.zig`, `src/runtime/reference/BundledOptics.zig`, and `src/kernels/linalg/cholesky.zig`
- Fresh bounded `python3` timeout wrapper around `zig build test --summary all` with `300s` ceiling -> timed out at `300.00s`; stderr tail still reports non-transport failures in `src/runtime/reference/BundledOptics.zig`, `src/retrieval/common/spectral_fit.zig`, and `src/kernels/linalg/cholesky.zig`, with no new transport-specific failure in `src/kernels/transport/adding.zig`
- `python3 -c '...subprocess.run(..., timeout=300)...' 300 zig build test --summary all` -> still fails outside the current WP-02 slice on existing tests in `src/model/InverseProblem.zig`, `src/plugins/providers/{instrument,noise}.zig`, `src/kernels/spectra/{calibration,noise}.zig`, `src/retrieval/common/{forward_model,spectral_fit}.zig`, `src/runtime/reference/BundledOptics.zig`, and `src/kernels/linalg/cholesky.zig`; the current bounded run no longer reports transport root-test failures in `src/kernels/transport/{labos,adding}.zig`
- `zig test -ODebug --dep build_options -Mroot=src/transport_source_tests.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig` -> all `66` transport/measurement-space tests passed before unrelated non-transport failures in `InverseProblem`, `instrument`, `noise`, `calibration`, `forward_model`, `BundledOptics`, `spectral_fit`, and `cholesky` stopped the broader root test matrix
- Fresh bounded `python3` timeout wrapper around `zig build test --summary all` after the prepared-boundary-weight fix -> timed out at `300.01s`; stderr reports the same unrelated failures in `src/model/InverseProblem.zig`, `src/plugins/providers/{instrument,noise}.zig`, `src/kernels/spectra/{calibration,noise}.zig`, `src/retrieval/common/{forward_model,spectral_fit}.zig`, `src/runtime/reference/BundledOptics.zig`, and `src/kernels/linalg/cholesky.zig`, with no transport or measurement-space failure in the current WP-02 slice
- Independent correctness and verification-sufficiency audits passed on the prepared-boundary-weight fix slice: the prepared path now preserves the fallback endpoint weights while keeping interior split `rtm_weight` / `ksca_above` metadata intact, and the focused `check` / `test-unit` / transport-source / RTM-control / O2A gates are sufficient for this isolated repair
- Independent correctness/context audits on the live prepared-adding grid slice agreed on the state: the finer-grid adding split is effective in actual execution, prepared adding routes now keep source-function integration enabled on that grid with explicit fine-grid split `rtm_weight` / `ksca_above` interface metadata, and the remaining gap is the lack of full vendor RTM quadrature parity rather than a hidden direct-extraction fallback.
- Independent vendor-context and proof-sufficiency audits are green on the current nonuniform RTM-quadrature weighting slice: active node weights are geometric again rather than parent-scattering-rescaled, the new nonuniform configured/live proofs close the old midpoint-surrogate gap on the prepared route, and the remaining parity gap is now the adjacent-sublayer `ksca` / phase blending rather than the weight carrier itself.
- Independent proof-sufficiency audit is also green on the corrected fallback guard slice: `fillRtmQuadratureAtWavelengthWithLayers` now declines to attach an all-zero carrier when no active nodes exist, the new `sublayer_divisions = 1` live regression proves the real route stays finite on the fallback path while an injected zero quadrature still changes the answer materially, and no additional high-signal proof is missing for this bounded fix.
- Fresh bounded Python timeout wrapper around `zig build test --summary all` with the corrected `sublayer_divisions = 1` guard -> timed out at `300.01s` after reporting `241/250` passed with the same unrelated `9` failures and `1` leak in `src/model/InverseProblem.zig`, `src/plugins/providers/{instrument,noise}.zig`, `src/kernels/spectra/{calibration,noise}.zig`, `src/retrieval/common/{forward_model,spectral_fit}.zig`, `src/runtime/reference/BundledOptics.zig`, and `src/kernels/linalg/cholesky.zig`, with no new transport-specific failure in the current WP-02 slice.
- Independent correctness/context audits on the prepared coarse-path slice agreed on the state: the coarse LABOS/shared path now uses the same split interface carrier as the finer adding path, the old hybrid “full-layer source weight plus borrowed first-sublayer phase” setup is gone, and the remaining gap is now the lack of vendor RTM interval/sub-interval quadrature parity rather than dead or collapsed prepared-source metadata.
- Independent correctness/context audits on the adding-state slice agreed on the state after test tightening: the live recursion now carries vendor-style scalar `tpl` / `tplst` / `s` / `sst` bookkeeping in `PartAtmosphere`, the Fourier-0 identities are checked with inline vendor sums rather than helper reuse, and the higher-Fourier bookkeeping is explicitly zeroed as in the vendor scalar path.
- Independent correctness/context audits on the boundary-diagnostic slice agreed on the state: the top-down pseudo-spherical adding path now exposes vendor-shaped black-surface diagnostics `{R0, td, expt, s_star}` from the live partial atmosphere, Fourier-0 extraction matches the `addingFromTopDownLUT*_Chandra` identities, and higher-Fourier diagnostics zero the Chandrasekhar-only scalars while still preserving weight-removed `R0`.
- Independent verification on the prepared pseudo-spherical attenuation slice now passes after two follow-up fixes: the prepared shell-grid handoff is guarded so unsupported prepared states leave the grid empty instead of exposing uninitialized buffers, and the reachable LABOS `scattering = none` route now uses resolved attenuation plus the optional shell grid instead of bypassing the live attenuation path with the old bulk Beer-Lambert shortcut.
- Independent correctness, context, and verification-sufficiency audits are all green on the current pseudo-spherical slice: the prepared shell-grid handoff is guarded, LABOS `scattering = none` now uses the live resolved attenuation path, and the targeted adding/LABOS/O2A/compatibility checks are sufficient evidence for this bounded transport change.
- Independent correctness, context, and verification-sufficiency audits are all green on the current prepared-adding metadata-preservation slice: measurement-space no longer rewrites prepared fine-grid source interfaces, cached execution preserves the explicit split metadata on the real route, the public integrated-source toggle still changes output, and the remaining gap is now the missing vendor RTM interval/sub-interval quadrature rather than a hidden prepared-route regression.
- Independent correctness, context, and test/build audits are all green on the current prepared-adding RTM quadrature slice: the lower-level boundary/interior proofs remain in place, the new live prepared-route mutation test now shows `executePrepared` itself is inert to zero-weight boundary nodes and sensitive to active interior nodes, and the public-root baseline stays at the same unrelated `9` failures plus the known `BundledOptics` leak outside the transport slice.
- Latest bounded `python3` timeout wrapper around `zig build test --summary all` with a `300s` ceiling -> timed out at `300.01s` after reporting `237/246` passed with `9` failures and `1` leak; all reported failures remain outside the current WP-02 transport slice in `src/model/InverseProblem.zig`, `src/plugins/providers/{instrument,noise}.zig`, `src/kernels/spectra/{calibration,noise}.zig`, `src/retrieval/common/{forward_model,spectral_fit}.zig`, `src/runtime/reference/BundledOptics.zig`, and `src/kernels/linalg/cholesky.zig`.
- Attempted a bounded RTM-node donor-sampling follow-up after the nonuniform geometric-weight slice, but independent review failed it for two concrete reasons: on the current surrogate quadrature carrier donor-only optics broke the nonuniform interval scattering budget, and the bounded `300s` full gate surfaced a transport `measurement_space` regression (`configured forward input builds prepared adding RTM quadrature on sublayer grids`). That slice was backed out rather than normalized.
- After backing out that donor-sampling attempt, `zig build check --summary all` -> passed, `37/37 tests passed`
- After backing out that donor-sampling attempt, `zig build test-unit --summary all -- --test-filter 'configured forward input builds prepared adding RTM quadrature on sublayer grids'` -> passed, `37/37 tests passed`
- After backing out that donor-sampling attempt, `zig build test-unit --summary all -- --test-filter 'prepared adding live route uses nonuniform quadrature weights instead of the legacy midpoint surrogate'` -> passed, `37/37 tests passed`
- After backing out that donor-sampling attempt, `zig build test-unit --summary all -- --test-filter 'prepared adding live route falls back when no explicit RTM quadrature nodes exist'` -> passed, `37/37 tests passed`
- After backing out that donor-sampling attempt, `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=/tmp/zdisamar-test-build_options.zig --test-filter 'engine execute changes prepared adding output when integrated source-function toggles'` -> passed, `All 1 tests passed`
- After backing out that donor-sampling attempt, `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/o2a_forward_shape_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=/tmp/zdisamar-test-build_options.zig --test-filter 'o2a adding integrated-source output remains morphologically bounded when RTM quadrature is enabled'` -> passed, `All 1 tests passed`
- After backing out that donor-sampling attempt, `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/o2a_forward_shape_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=/tmp/zdisamar-test-build_options.zig --test-filter 'o2a forward reflectance tracks vendor reference morphology'` -> passed, `All 1 tests passed`
- After backing out that donor-sampling attempt, `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/disamar_compatibility_harness_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=/tmp/zdisamar-test-build_options.zig --test-filter 'compatibility harness execution honors RTM controls in prepared routes'` -> passed, `All 1 tests passed`
- After backing out that donor-sampling attempt, fresh bounded `python3` timeout wrapper around `zig build test --summary all` with `300s` ceiling -> timed out at `300.00s` after reporting `241/250` passed with the same unrelated `9` failures and `1` leak in `src/model/InverseProblem.zig`, `src/plugins/providers/{instrument,noise}.zig`, `src/kernels/spectra/{calibration,noise}.zig`, `src/retrieval/common/{forward_model,spectral_fit}.zig`, `src/runtime/reference/BundledOptics.zig`, and `src/kernels/linalg/cholesky.zig`, with no transport `measurement_space` failure in the restored baseline
- Independent rollback audit passed on the restored baseline: the current diff keeps the earlier verified quadrature/source-interface contracts intact and the fast/local RTM quadrature proof set is green again on the backed-out branch.
- Attempted `zig build test-integration --summary all` and `zig build test-validation --summary all`, but the local exec harness duplicated long-running `zig build` jobs while polling. Targeted proof commands above were used instead to keep verification deterministic.
- Re-ran a bounded `zig build test --summary all` with a `300s` timeout cap after the pseudo-spherical asymmetry fix; the command still exceeded the requested ceiling before yielding a fresh failure report, and the wrapper hit a bytes/strings logging bug while printing the timeout payload. The last usable bounded full-gate evidence is therefore still the earlier non-transport-only failure set listed below.
- Attempted a fresh bounded `zig build test --summary all` rerun after the prepared-source-interface and phase-mixing fixes, but the local exec wrapper kept the subprocess attached without yielding a usable result. The last usable bounded full-gate evidence is still the non-transport-only failure set listed above.
- Re-ran a bounded `zig build test --summary all` with the requested `300s` ceiling after the coarse prepared source-interface split. The command still timed out before completing the full matrix. Its stderr tail included a mixed failure set; the transport-named `measurement_space` unit tests in that tail were re-run directly under `zig build test-unit` and passed, so the bounded full-gate output was treated as non-authoritative for this slice rather than as a reproducible transport regression.
- Attempted to switch the entire real measurement-space execution path from `prepared.layers.len` to `prepared.transportLayerCount()`, but the targeted O2A morphology gate failed on the mid-band threshold and the global change was backed out instead of being normalized as a new baseline.
- Reintroduced the finer grid selectively for prepared adding routes only, first with explicit direct-TOA fallback and now with explicit fine-grid source interfaces that keep source-function integration enabled on that path; the targeted O2A morphology gate, RTM-control integration check, O2A RTM-control validation, and compatibility-harness prepared-route check all still passed on the live branch after that bounded change.
- Attempted `zig build test-validation -- --test-filter 'o2a validation output changes when RTM controls change'` and `zig build test-validation -- --test-filter 'compatibility harness execution honors RTM controls in prepared routes'`, but the build step still executes the full validation suite and currently fails on the unrelated `oe_parity_test` golden-anchor drift. The explicit per-file `zig test ... --test-filter ...` commands above remain the deterministic targeted proof path.

## How To Test

1. Run `zig build test-unit --summary all`.
2. Run the Fourier/azimuth-focused unit slice:
   `zig build test-unit --summary all -- --test-filter 'anisotropic'`.
3. Run the high-layer-count adding regression:
   `zig build test-unit --summary all -- --test-filter 'adding supports 80 transport layers without rejecting the explicit multi-layer path'`.
4. Run the shared source-function regressions:
   `zig build test-unit --summary all -- --test-filter 'integrated source-function'`.
5. Run the single-layer source-function fallback guards:
   `zig build test-unit --summary all -- --test-filter 'single-layer integrated source-function falls back to direct TOA extraction'`.
6. Run the prepared optics/source-interface regressions:
   `zig build test-unit --summary all -- --test-filter 'optical preparation builds sublayer-informed source interfaces for prepared transport inputs'`
   and
   `zig build test-unit --summary all -- --test-filter 'optical preparation recomputes layer phase mixing with wavelength-specific gas scattering'`.
7. Run the prepared boundary/source-interface regressions:
   `zig build test-unit --summary all -- --test-filter 'configured forward input preserves prepared source-function boundary weights'`
   and
   `zig build test-unit --summary all -- --test-filter 'configured forward input keeps integrated source-function on prepared adding sublayer grids when explicit interfaces are available'`
   and
   `zig build test-unit --summary all -- --test-filter 'cached forward execution keeps prepared adding source-function integration on sublayer grids'`.
8. Run the prepared adding execution regression:
   `zig build test-unit --summary all -- --test-filter 'adding integrated source-function path uses explicit source interface metadata'`.
9. Run the prepared adding boundary-surrogate regression:
   `zig build test-unit --summary all -- --test-filter 'prepared adding execution differs from fallback boundary-surrogate interfaces on explicit sublayer grids'`.
10. Run the prepared adding buffer/grid regressions:
   `zig build test-unit --summary all -- --test-filter 'summary workspace sizes adding transport buffers from sublayer hints'`
   and
   `zig build test-unit --summary all -- --test-filter 'measurement-space simulation supports adding routes on prepared sublayer grids'`.
11. Run the adding-state bookkeeping regressions:
   `zig build test-unit --summary all -- --test-filter 'adding bottom composition populates vendor scalar integrated states for Fourier-0'`
   and
   `zig build test-unit --summary all -- --test-filter 'adding top composition populates vendor scalar integrated states for Fourier-0'`
   and
   `zig build test-unit --summary all -- --test-filter 'adding composition zeroes vendor scalar integrated states for higher Fourier orders'`.
12. Run the transport source-test harness for the adding source slices:
   `zig test -ODebug --dep build_options -Mroot=src/transport_source_tests.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'adding bottom composition populates vendor scalar integrated states for Fourier-0'`
   and
   `zig test -ODebug --dep build_options -Mroot=src/transport_source_tests.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'adding top-down boundary diagnostics expose vendor black-surface quantities for Fourier-0'`
   and
   `zig test -ODebug --dep build_options -Mroot=src/transport_source_tests.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'adding top-down boundary diagnostics zero Chandrasekhar scalars for higher Fourier orders'`.
13. Run the typed-route and adding no-scattering regressions:
   `zig build test-unit --summary all -- --test-filter 'prepare route resolves families and keeps derivative mode explicit'`
   and
   `zig build test-unit --summary all -- --test-filter 'adding no-scattering layered path responds to per-layer solar geometry'`
   and
   `zig build test-unit --summary all -- --test-filter 'adding no-scattering layered path matches Lambertian attenuation identity'`.
14. Run the pseudo-spherical attenuation regressions:
   `zig build test-unit --summary all -- --test-filter 'labos spherical correction falls back to layer-dependent solar and view attenuation without explicit grid'`.
   and
   `zig test -ODebug --dep build_options -Mroot=src/transport_source_tests.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'labos dynamic spherical correction uses pseudo-spherical sample grid when provided'`.
   and
   `zig build test-unit --summary all -- --test-filter 'configured forward input wires pseudo-spherical attenuation samples from prepared sublayers'`.
   and
   `zig build test-unit --summary all -- --test-filter 'configured forward input leaves pseudo-spherical attenuation grid empty when prepared sublayers are unavailable'`.
   These prove the correction still falls back cleanly without prepared sublayer metadata, uses the prepared shell grid when that grid exists, and only rewrites TOA-to-level attenuation while leaving reverse level-to-TOA entries plane-parallel.
15. Run the pseudo-spherical reflectance-sensitivity regressions:
   `zig build test-unit --summary all -- --test-filter 'spherical correction changes reflectance for layered scalar scenes'`.
   and
   `zig build test-unit --summary all -- --test-filter 'adding spherical correction changes reflectance for layered scalar scenes'`.
16. Run the direct engine-level pseudo-spherical execution regressions:
   `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes labos no-scattering output when spherical correction changes'`.
   and
   `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes prepared adding multiple-scattering output when spherical correction changes'`.
17. Run the direct engine-level prepared-adding source-function regression:
   `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes prepared adding output when integrated source-function toggles'`.
18. Run the direct engine-level azimuth-sensitivity integration check:
   `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes reflectance with relative azimuth for anisotropic scattering scenes'`.
19. Run the targeted integration control-sensitivity check:
   `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine execute changes route and reflectance when RTM controls change'`.
20. Run the engine-level adding no-scattering route regression:
   `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/integration/forward_model_integration_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'engine preparePlan and execute support adding no-scattering routes'`.
21. Run the O2A morphology gate:
   `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/o2a_forward_shape_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'o2a forward reflectance tracks vendor reference morphology'`.
22. Run the RTM-sensitive validation and compatibility harness checks:
   `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/o2a_forward_shape_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'o2a validation output changes when RTM controls change'`
   and
   `zig test -ODebug --dep zdisamar --dep zdisamar_internal --dep legacy_config --dep cli_app -Mroot=tests/validation/disamar_compatibility_harness_test.zig --dep build_options -Mzdisamar=src/root.zig -ODebug --dep zdisamar -Mzdisamar_internal=src/internal.zig -ODebug --dep zdisamar -Mlegacy_config=src/adapters/legacy_config/Adapter.zig -ODebug --dep zdisamar --dep legacy_config -Mcli_app=src/adapters/cli/App.zig -Mbuild_options=.zig-cache/c/d8ca776297b628874ffa8e1c317a38c0/options.zig --test-filter 'compatibility harness execution honors RTM controls in prepared routes'`.
23. Run the 48-layer and 80-layer explicit-layer guards:
   `zig build test-unit -- --test-filter 'labos supports 48 transport layers without collapsing to the synthetic single-layer fallback'`.
   and
   `zig build test-unit --summary all -- --test-filter 'adding supports 80 transport layers without rejecting the explicit multi-layer path'`.
24. For vendor-like stream settings, prepare a route or plan with `n_streams = 20` and confirm route preparation succeeds.
