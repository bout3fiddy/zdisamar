# Kernels

- This subtree is for reusable numeric kernels: quadrature, interpolation, polarization, spectra, transport, and linalg.
- No file I/O, text parsing, logging-heavy orchestration, or plugin callback dispatch in innermost loops.
- Keep scalar, polarized, and derivative-enabled execution paths explicit when that avoids paying for unused machinery.
