# Retrieval Optimisation Notes

These notes keep the retrieval-specific mechanism details behind the short
retrieval performance summary. They use source links and Python-shaped examples,
not copied implementation excerpts.

Source snapshot convention:

```text
DISAMAR Fortran: d17c52884a875cb87b98e4c4ea7f722659e685ac
zdisamar:        aa3bdc776e605229b18b54a7999632fb276546e2
```

Notes:

- [01. Reuse the forward session](01-forward-session-reuse.md)
- [02. Keep Jacobians state-vector sized](02-state-vector-jacobians.md)
- [03. Isolate paired validation lanes](03-paired-validation-lanes.md)
- [04. Defer final-state evaluation](04-lazy-final-evaluation.md)
