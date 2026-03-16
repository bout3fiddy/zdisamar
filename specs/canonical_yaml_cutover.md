# Canonical YAML Cutover

## Status

- Effective date: 2026-03-16
- Runtime entrypoint: canonical YAML
- Legacy `Config.in` policy: import-only migration input

## Canonical CLI Surface

The supported CLI contract is:

```text
zdisamar run CONFIG.yaml
zdisamar config validate CONFIG.yaml
zdisamar config resolve CONFIG.yaml
zdisamar config import legacy_config.in
```

Normal execution must go through the canonical YAML compiler and staged
execution path in `src/adapters/canonical_config/`. Legacy execution through a
parallel `Config.in` runtime adapter is not part of the supported contract.

## Tracked Examples

Repository-owned canonical examples live in:

- `data/examples/canonical_config.yaml`
- `data/examples/zdisamar_common_use.yaml`
- `data/examples/zdisamar_expert_o2a.yaml`

These examples are the durable counterparts to the design inputs under
`docs/specs/config/`.

## Acceptance Criteria

The cutover is acceptable when all of the following remain true:

1. Canonical YAML examples resolve and execute without routing normal runtime
   execution through the legacy parser.
2. The same typed scene and inverse vocabulary is used for both simulation and
   retrieval stages.
3. Unknown fields, unresolved stage references, and inverse-crime warnings are
   validated before execution.
4. Release-readiness checks point at the canonical YAML CLI path.
5. Legacy `Config.in` remains bounded to importer-only migration support.

## Validation Gates

Required validation coverage includes:

- `zig build test`
- integration tests for tracked common-use and expert YAML execution
- validation-lane checks for tracked examples and release-readiness artifacts
- importer tests proving the supported flat legacy subset translates into
  canonical YAML with explicit warnings for approximations

## Notes

- Scratch design exploration remains in `docs/specs/config/`.
- Tracked changes to the canonical contract must update this file in the same
  change as code and test updates.
