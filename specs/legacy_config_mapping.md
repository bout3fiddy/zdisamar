# Legacy `Config.in` Mapping

This note records how the supported historical `Config.in` concepts map into the
canonical YAML design and which concepts are importer-only approximations.

## Mapping Table

| Legacy concept | Canonical YAML concept | Rationale |
| --- | --- | --- |
| `workspace` | `metadata.workspace` | workspace labeling is runtime metadata, not scene physics |
| `scene_id` | `experiment.<stage>.scene.id` | stage-local scene identity stays with the canonical scene model |
| `model_family` | `templates.<name>.plan.model_family` | plan-level solver selection belongs in the typed plan template |
| `transport` | `templates.<name>.plan.transport.solver` plus optional provider normalization | transport routing is adapter-owned plan configuration |
| `solver_mode` | `templates.<name>.plan.execution.solver_mode` | execution mode remains typed and plan-scoped |
| `derivative_mode` | `templates.<name>.plan.execution.derivative_mode` | derivative policy is validated before execution and not left as a free-form flag |
| spectral start/end/sample count | `templates.<name>.scene.bands.*` | canonical YAML expresses science windows as named bands, not bare scalar triples |
| `atmosphere_layers` | `templates.<name>.scene.atmosphere.layering.layer_count` | atmosphere structure stays inside the typed scene |
| geometry angles | `templates.<name>.scene.geometry.*` | geometry is part of the physical scene state |
| `instrument`, `sampling`, `noise_model` | `templates.<name>.scene.measurement_model.*` | instrument and sampling controls stay under the typed measurement model |
| `requested_products` | `experiment.<stage>.products` | product routing is stage-local and explicit |
| `diagnostics.*` | `experiment.<stage>.diagnostics` | diagnostics remain requested per stage instead of hidden in exporter behavior |

## Import-Only Approximations

The currently supported flat adapter subset cannot reconstruct full historical
DISAMAR structure. The importer therefore emits canonical YAML plus warnings for
these cases:

- binary `has_clouds` and `has_aerosols` flags become placeholder cloud or
  aerosol blocks because the flat subset carries no microphysical parameters
- `retrieval` provider hints are preserved only as plan metadata because the
  flat subset does not encode an inverse problem
- untyped requested product names that have no canonical typed mapping are
  preserved as `kind: result` for traceability

## Policy

- Keep legacy `Config.in` support import-only.
- Do not add a second runtime execution path for the historical grammar.
- When the importer gains support for new historical concepts, update this file
  in the same change.
