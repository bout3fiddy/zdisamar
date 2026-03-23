# Kernels

- This subtree is for reusable numeric kernels: quadrature, interpolation, polarization, spectra, transport, and linalg.
- No file I/O, text parsing, logging-heavy orchestration, or plugin callback dispatch in innermost loops.
- Keep scalar, polarized, and derivative-enabled execution paths explicit when that avoids paying for unused machinery.
- Explicit execution paths are not a license to duplicate shared arithmetic, accumulation, interpolation, or struct-mapping logic. Prefer small pure helpers when behavior is identical across paths.
- A kernel file should own one primary numerical responsibility. If a module mixes preparation, spectral evaluation, solver coupling, workspace management, or synthetic fixture construction, split it into sibling modules even if the public API stays unified.
- Keep large synthetic fixtures and broad scenario tests out of production kernel modules. Inline tests should stay local and small; move larger harnesses and canned states to `tests/` or dedicated support files.

## Kernel Regression Notes

- Temporary checklist: remove an item once the Zig kernel and its tests prove that failure mode is impossible.
- Avoid linear-in-`n` optical-depth subdivision in doubling kernels; homogeneous doubling must start from `tau / 2^n`, not `tau / n`, and must preserve pure-absorption transmittance exactly.
- Avoid wrong-sign or extra-attenuation transport Jacobians; Beer-Lambert sensitivities for positive optical-depth contributions must reduce radiance and must not pick up an extra `exp(-tau)` factor from double-counting attenuation.
- Avoid TOA radiance closures that use layer transmittance only in reflected-sun transport paths; scattering and reflectance/source terms must contribute explicitly.
- Avoid rank-blind QR or least-squares helpers in retrieval-facing kernels; detect zero/collinear columns and return a typed singular or rank-deficient error instead of NaNs.
