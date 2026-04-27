# Python Bindings

Python bindings are deferred. The future interface should follow
[`python-research-wrapper.md`](./python-research-wrapper.md) and use
DISAMAR-facing language before any wrapper is implemented.

The existing low-level C interface in `src/api/c.zig` is the native boundary.
The native library owns contexts and spectrum arrays until the matching free or
destroy call.

Build the shared library:

```bash
zig build
```

Use the wrapper from the repo:

```python
import zdisamar as zd

with zd.Context() as ctx:
    ctx.prepare_default_o2a()
    with ctx.run() as spectrum:
        print(spectrum.wavelength_nm)
        print(spectrum.reflectance)
```

The Python API exposes full-array operations. It does not provide scalar
per-wavelength calls because the native boundary is meant to stay coarse.
