# Retrieval

- Retrieval code layers on the canonical scene model from `src/model/`.
- Do not rebuild the old simulation-vs-retrieval type split here.
- Keep priors, covariance handling, Jacobian flow, and solver-specific logic separable.
