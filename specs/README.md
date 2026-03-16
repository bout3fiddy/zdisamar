# Tracked Specs

This directory stores version-controlled architecture, cutover, and migration
notes that must remain durable after local scratch designs in `docs/specs/`
change or disappear.

Current canonical-config references:

- `canonical_yaml_cutover.md` — final runtime and CLI contract for canonical
  YAML, acceptance criteria, and release gating notes.
- `legacy_config_mapping.md` — mapping from the historical `Config.in` control
  surface to canonical YAML concepts and importer policy.
