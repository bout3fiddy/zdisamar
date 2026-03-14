# Fortran Mapping

The local upstream reference source is available in `vendor/disamar-fortran/src/`.

## Migration Map

- `staticDataModule.f90` -> `src/core/Engine.zig` and `src/runtime/cache/`
- `DISAMARModule.f90` -> `src/core/Plan.zig`, `src/runtime/scheduler/`, `src/adapters/cli/`
- `dataStructures.f90` -> `src/model/`, `src/core/`, `src/runtime/cache/`
- `inputModule.f90`, `readConfigFileModule.f90`, `verifyConfigFileModule.f90` -> `src/adapters/legacy_config/`
- `LabosModule.f90`, `addingToolsModule.f90`, `FourierCoefficientsModule.f90`, `radianceIrradianceModule.f90` transport pieces -> `src/kernels/transport/`
- `optimalEstimationModule.f90`, `doasModule.f90`, `classic_doasModule.f90`, `dismasModule.f90` -> `src/retrieval/`
- `S5PInterfaceModule.f90`, `S5POperationalModule.f90` -> `src/adapters/missions/s5p/`
- `writeModule.f90`, `asciiiHDFtoolsModule.f90`, `netcdfModule.f90` -> `src/adapters/exporters/` and `src/plugins/builtin/exporters/`
- `DISAMAR_interface.f90`, `DISAMAR_interface.h` -> `src/api/c/`

## Immediate Boundaries

- No new global mutable state.
- No file parsing or output file creation in `src/core` or `src/kernels`.
- No mission-specific logic in the core runtime tree.
- No string-keyed request mutation API in the new public surface.
