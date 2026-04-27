# O2A Forward

`zdisamar` exposes a narrow O2A forward-model lifecycle:

```zig
var prepared = try zdisamar.prepare(allocator, &case);
defer prepared.deinit(allocator);

var result = try zdisamar.run(
    allocator,
    &prepared,
    .exact,
    .{},
);
defer result.deinit(allocator);
```

`Prepared` owns the resolved case, bundled data, prepared optics, and reusable
internal storage. Callers should not pass a separate original case into the run
step; `prepared.case` is the authoritative resolved scene.

The public root intentionally keeps only the literal O2A surface:

- `Case`
- `Prepared`
- `Data`
- `Optics`
- `Method`
- `RunStorage`
- `RadiativeTransferControls`
- `Result`
- `Report`
- `prepare`
- `run`
- `writeReport`
- `parity`

Data loading, optical-property preparation, and spectrum generation are not
separate public entrypoints.
