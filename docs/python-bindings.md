# Python Bindings

The first Python wrapper uses `ctypes` over the coarse C ABI in `src/api/c.zig`.
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
