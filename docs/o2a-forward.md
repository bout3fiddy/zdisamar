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
    null,
);
defer result.deinit(allocator);
```

`Prepared` owns the resolved case, bundled data, prepared optics, and reusable
measurement workspace. Callers should not pass a separate original case into the
run step; `prepared.case` is the authoritative resolved scene.

The public root intentionally keeps only the literal O2A surface:

- `Case`
- `Prepared`
- `Data`
- `Optics`
- `Method`
- `Work`
- `Result`
- `Report`
- `prepare`
- `run`
- `writeReport`
- `parity`
- `profile`

The old split `loadData -> buildOptics -> runSpectrum` lifecycle is no longer
public.
