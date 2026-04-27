# Kernels

- This subtree is for reusable numeric routines: quadrature, interpolation, polarization, spectra, radiative transfer, and linalg.
- No file I/O, text parsing, logging-heavy orchestration, or extension callback dispatch in innermost loops.
- Keep scalar, polarized, and derivative-enabled execution paths explicit when that avoids paying for unused machinery.
- Explicit execution paths are not a license to duplicate shared arithmetic, accumulation, interpolation, or struct-mapping logic. Prefer small pure helpers when behavior is identical across paths.
- A routine file should own one primary numerical responsibility. If a module mixes preparation, spectral evaluation, forward-model coupling, storage management, or synthetic fixture construction, split it into sibling modules even if the public API stays unified.
- Keep large synthetic fixtures and broad scenario tests out of production routine modules. Inline tests should stay local and small; move larger harnesses and canned states to `tests/` or dedicated support files.

## Kernel Regression Notes

- Temporary checklist: remove an item once the Zig routine and its tests prove that failure mode is impossible.
- Avoid linear-in-`n` optical-depth subdivision in doubling routines; homogeneous doubling must start from `tau / 2^n`, not `tau / n`, and must preserve pure-absorption transmittance exactly.
- Avoid wrong-sign or extra-attenuation radiative-transfer Jacobians; Beer-Lambert sensitivities for positive optical-depth contributions must reduce radiance and must not pick up an extra `exp(-tau)` factor from double-counting attenuation.
- Avoid TOA radiance closures that use layer transmittance only in reflected-sun radiative-transfer paths; scattering and reflectance/source terms must contribute explicitly.
- Avoid rank-blind QR or least-squares helpers in retrieval-facing routines; detect zero/collinear columns and return a typed singular or rank-deficient error instead of NaNs.
- Avoid reversing physical layer ordering when introducing explicit interval grids or alternate preparation routes; radiative-transfer-facing sublayer arrays and derived interfaces must stay monotonic in the direction each consumer expects.
- Avoid applying particulate fractions, attenuation factors, or normalized weights twice; once a sublayer or layer quantity includes a physical scale factor, downstream mixing logic must treat it as already scaled.
- Avoid sampling wavelength-dependent controls at reference-only wavelengths unless the contract says they are reference-only; simulated spectral behavior must be driven by the active wavelength path.
- Avoid silent legacy drift during explicit-path refactors; when intervals, alternate midpoints, or new preparation formulas are absent, legacy scenes should retain legacy numerical behavior unless the change is explicitly called out and tested.
- Avoid zeroing or skipping enabled optical-depth contributions when explicit placement or interval lookup fails; unmatched indices and unsupported placements must surface typed errors.
