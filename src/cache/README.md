# `cache/` — the memory a retrieval reuses

A retrieval runs the forward model many times, and between runs only the aerosol
state changes. Everything that does not depend on that state, the wavelength grid,
the gas spectroscopy, the solar flux, the radiative-transfer scratch, is built
once and reused. This directory holds that memory. The parent `src/README.md`
lists what a session carries; this file covers where each buffer is allocated,
how long it lives, and when it is touched.

The subsystem reaches a steady state where it allocates nothing. A buffer grows to
the size it needs on the first run, or rebuilds when its inputs change, then is
overwritten in place on every later run and every retrieval iteration. All of it
lives on the one allocator the C API `Context` passes down. No module keeps a
private allocator, with one scoped exception covered below.

```
  +------------------------------------------------------------+
  | session allocator (one GeneralPurposeAllocator)            |
  +------------------------------+-----------------------------+
                                 |
                                 v
  +------------------------------------------------------------+
  | SessionMemory                              one per session |
  +------------------------------------------------------------+
  | spectrum          sampling rows, slit offsets and weights  |
  | radiance          wavelength list, radiance, Jacobian      |
  | profile_lines     O2 line cross-sections (the largest)     |
  | solar_irradiance  wavelength to solar-flux memo map        |
  | transport_workers per-worker rtm/ scratch, one per thread  |
  | worker_pool       helper threads for the dense loop        |
  +------------------------------------------------------------+
  freed once, in reverse order, at SessionMemory.deinit
```

## The owner and the grow-and-keep model (`session_memory.zig`, `common/memory.zig`)

`SessionMemory` is the top-level owner, a 416-byte value that holds the six
children inline and allocates nothing itself. `init` constructs
them empty and passes the allocator only to the solar map; `deinit` frees them in
reverse dependency order, the per-worker buffers first and the spectrum rows last.
Keeping the children as fields between requests removes the per-request rebuild a
retrieval would otherwise pay.

Three kinds of memory sit underneath it:

1. Retained workspace, grown once and reused in place. This holds nearly the whole
   footprint.
2. One scoped arena, alive only while the line cross-sections build.
3. Stack scratch on the per-wavelength read path, which touches no heap.

`ensureSliceCapacity` (`common/memory.zig`) decides on each run whether to keep a
buffer or replace it:

```
  ensureSliceCapacity(slice, n):

    n <= slice.len   ->  keep the buffer, hand it back        (no alloc)
    n  > slice.len   ->  allocate n, free the old buffer,     (one alloc)
                         swap the pointer
```

Callers refill the whole prefix each run, so the discarded contents cost nothing,
and a buffer settles at the largest size any run has asked for. Every buffer is
freed together at `SessionMemory.deinit`.

A retrieval stays cheap because most inputs hold still while the aerosol state
moves. Each retained table carries a `hashing.ReuseStamp`, and `prepareSessionRows`
in `root.zig` hashes the inputs a table depends on and compares: a match reuses the
table without allocating, a miss rebuilds it.

## Spectrum sampling table (`spectrum_memory.zig`)

`SpectrumMemory` holds the high-resolution sampling rows and two side arrays, the
offsets and weights that average the fine grid down to each product wavelength. A
miss replaces it: `takeTable` frees the previous arrays, moves the freshly built
arrays in by pointer without copying, and records the new stamp. A hit returns
borrowed slices of the retained arrays through `table()`. The two side arrays are
the large part of this table.

## Radiance work (`radiance_memory.zig`)

`RadianceMemory` holds two parts with different reuse rules. The wavelength list,
the rows, sample indices, and dense wavelengths the radiative transfer runs over,
moves in by pointer-swap in `takeWavelengthList`, which frees the old generation
and is gated by `wavelength_stamp`. The dense radiance column and the optional
Jacobian column grow through `ensureResultCapacity`, and the Jacobian column is
freed when a run wants no derivatives. A second stamp, `result_stamp`, records
whether the dense values are still valid and resets whenever the list moves or a
column grows, so stale values are never read against fresh storage.

## Line cross-sections (`profile_line_memory.zig`)

`profile_line_memory.zig` holds the largest table and the only arena in the
subsystem. `ProfileLineValues` keeps the O2 line cross-section data: a dense
support-profile sigma column, and, when diagnostics ask for it, a
wavelength-by-layer-node grid. It is the single biggest piece of session memory,
and building it sums Voigt and line-mixing terms over every line at every
wavelength, the most expensive step in setup.

The build runs only on a stamp miss. `profileLineReuseStamp` hashes the scene id,
the exact wavelengths, the parsed line assets, and the fixed-node spectroscopy
profile, and excludes the dynamic layer grid. This is possible because the line
values sit at fixed spectroscopy nodes and are resampled per pressure state
downstream, so the cache survives the pressure changes a retrieval makes each
iteration.

The build's scratch runs through one `std.heap.ArenaAllocator`. The layer grid,
the line tables, the cutoff grid, the collected line lists, and every prepared
weak- and strong-line state allocate into it, and the whole arena drops in one
`deinit` when the build returns. The two buffers that outlive the build, the sigma
column and the diagnostic grid, allocate on the session allocator so they reach the
cache.

The per-wavelength reader, `fillSupportLineSigmaAtWavelengthIndex`, reads the
retained column and uses fixed stack arrays for the spline. It allocates nothing.

## Solar irradiance (`solar_irradiance_memory.zig`)

`SolarIrradianceMemory` maps the exact f64 bits of a wavelength to its solar flux.
It grows its capacity once with `ensureTotalCapacity`, then the per-wavelength
irradiance loop fills it with `putAssumeCapacity`, which never allocates, and reads
it with `get`. Between product simulations `reset` empties the entries with
`clearRetainingCapacity` and keeps the capacity, so the next run refills the same
storage. The only free is at teardown.

## Per-worker radiative-transfer scratch (`transport_worker_memory.zig`)

Each `TransportWorkerMemory` owns about 27 grown-and-kept slices: the attenuation
tables, the layer reflection and transmission rows, the scattering-order fields,
the phase rows, the optics rows, and the Fourier basis cache. `ensureCapacity` and
`ensureOpticsCapacity` grow them to their largest needed size once per run, and the
radiative transfer refills and rereads them per wavelength. `solveWorkArrays` hands
that code borrowed prefixes and never allocates.

Two caches inside survive across wavelengths and rebuild only when the sun and view
geometry change: the Fourier basis, about 14.2 KiB per Fourier term, and the cached
Gauss geometry. When a backing slice is reallocated or the geometry key changes,
the parallel validity flags reset, so the next read rebuilds. This is possible
because the geometry rarely moves across the dense grid, so the basis is built a
few times over a whole run rather than once per wavelength.

The collection keeps one private `TransportWorkerMemory` per worker thread.
`ensureWorkerCount` grows the outer array by moving the existing workers in by
value, so their buffers ride along, then frees only the old outer array. Each
worker keeps its own buffers and none is shared, so the dense wavelength loop runs
on all workers at once without contention.

## Worker pool (`forward_worker_pool.zig`)

`ForwardWorkerPool` owns the `std.Thread.Pool` the dense wavelength loop runs on,
or borrows a shared one. `poolForWorkerCount` returns the owned pool when the
requested worker count matches, and rebuilds it, tearing the old one down first,
when the count changes. Its one allocation is the thread-handle slice inside the
pool. It stores no physics state.

## Footprint

For the packaged reference scene a session holds roughly 22 MB, most of the
program's heap, allocated once and reused for its lifetime. A few tables account
for nearly all of it:

```
  largest first:

    slit offsets and weights   ~4.5 MB each
    line cross-section column   several MB
    per-worker scratch         ~1.4 MiB each (one per worker thread)
    dense radiance + Jacobian  ~93 KB
    Fourier basis              ~14.2 KiB per term
```

Once the stamps match and the buffers are at size, a forward run and every
retrieval iteration read only retained storage and stack scratch, and allocate
nothing.

## Where to start

- `session_memory.zig` — the owner and the teardown order, the shortest file and
  the map of the directory.
- `common/memory.zig` — `ensureSliceCapacity`, the grow-and-keep primitive
  everything here is built on.
- `profile_line_memory.zig` — the largest table, the one arena, and the reuse
  stamp; read `profileLineReuseStamp` and the build function.
- `transport_worker_memory.zig` — the per-worker scratch and the geometry and
  Fourier-basis caches.
- `prepareSessionRows` in `root.zig` — where the stamps are checked and the
  children are reused or rebuilt each run.
- the parent `src/README.md` for how these tables feed `optics/`, `rtm/`, and the
  retrieval loop.
