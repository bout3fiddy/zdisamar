# O2A Forward

`zdisamar` exposes a narrow O2A forward-model lifecycle:

```zig
var input: zdisamar.Input = .{
    .spectral_grid = .{ .start_nm = 758.0, .end_nm = 771.0, .sample_count = 121 },
};

var prepared = try zdisamar.prepare(allocator, &input);
defer prepared.deinit(allocator);

var result = try zdisamar.run(
    allocator,
    &prepared,
    .exact,
    .{},
);
defer result.deinit(allocator);
```

`PreparedInput` owns the resolved input, bundled data, prepared optics, and
reusable internal storage. Callers should not pass a separate original input
into the run step; `prepared.input` is the authoritative resolved scene.

The public root intentionally keeps only the literal O2A surface:

- `Input`
- `PreparedInput`
- `ReferenceData`
- `OpticalProperties`
- `Method`
- `CalculationStorage`
- `RadiativeTransferControls`
- `Output`
- `DiagnosticReport`
- `prepare`
- `run`
- `writeReport`
- `disamar_reference`
- `report`

Data loading, optical-property preparation, and spectrum generation are not
separate public entrypoints.
