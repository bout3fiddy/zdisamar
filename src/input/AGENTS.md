# Model

- Maintain one canonical scene and observation model for both forward and inverse paths.
- Prefer layouts that separate hot numeric tensors from cold metadata.
- Add domain types here when they are reusable across radiative transfer, retrieval, and export layers.
