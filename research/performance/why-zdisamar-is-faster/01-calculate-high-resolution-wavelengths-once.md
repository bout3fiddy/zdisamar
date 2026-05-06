# 01. Calculate High-Resolution Wavelengths Once

Measured forward-time saving: part of `511061b -> e23035b`, 79.767901 s to 11.890893 s, saving 67.877008 s for one spectrum. That checkpoint combines this high-resolution wavelength change with the shared layer-geometry change in [02](02-reuse-shared-layer-geometry.md).

## Why This Step Exists

The requested O2 A output has 701 wavelengths. The radiance calculation is more expensive than that number suggests because each output wavelength is built from nearby high-resolution radiance samples. In the retained DISAMAR log, the high-resolution radiance grid has 3,874 wavelengths.

The expensive question is therefore not "how do we produce 701 output points?" It is "how many times do we calculate high-resolution radiance before the instrument integration reads those values?"

## What DISAMAR Does

DISAMAR fills broad wavelength, pressure, and geometry tables for each spectral band and Fourier term. That is a general design: the executable can run many products, many bands, and many retrieval paths. For the single O2 A forward spectrum we care about here, that general table flow does not first make the smallest possible list of high-resolution radiance wavelengths and calculate each one only once.

Source link: [DISAMAR GitLab source](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/DISAMARModule.f90#L2716-L2732)

Excerpt:

```fortran
! SLOW: DISAMAR is setting up a broad wavelength/pressure table indexed by
!       band and Fourier term. That is flexible, but it is not the speed
!       trick used by zdisamar: first ask exactly which high-resolution
!       radiance wavelengths the instrument integration will read.
do iband = 1, globalS%numSpectrBands
  do iFourier = 0, globalS%maxFourierTermLUT
    do iwave = 1, globalS%createLUTSimS(iFourier,iband)%nwavel
      ! SLOW: the wavelength table is repeated for each Fourier term because
      !       this LUT is organized around the general DISAMAR dimensions.
      globalS%createLUTSimS(iFourier,iband)%wavel(iwave) = globalS%wavelInstrRadSimS(iband)%wavel(iwave)
    end do ! iwave
    do iwave = 1, globalS%createLUTRetrS(iFourier,iband)%nwavel
      globalS%createLUTRetrS(iFourier,iband)%wavel(iwave) = globalS%wavelInstrRadRetrS(iband)%wavel(iwave)
    end do ! iwave
    do ipressure = 0, globalS%createLUTSimS(iFourier,iband)%npressure
      globalS%createLUTSimS(iFourier,iband)%pressure(ipressure) = &
      globalS%cloudAerosolRTMgridSimS%intervalBounds_P(ipressure)
    end do ! ipressure
```

This excerpt does not by itself prove duplicate radiance recomputation inside DISAMAR. What it shows is the shape of the reference executable: it prepares general band/Fourier/wavelength tables. The zdisamar change is narrower: before radiance transport runs, it starts from the actual 701 output wavelengths, expands them to the high-resolution samples the instrument integration needs, removes duplicate wavelengths, and calculates that unique list once.

## What zdisamar Does

zdisamar builds the O2 A wavelength work first. It finds every high-resolution radiance wavelength that will be needed by the 701 output wavelengths, removes duplicates, calculates each missing radiance value once, stores it, and then lets the 701 output wavelengths read from that stored set.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/instrument_grid/grid_calculation/simulate.zig#L51-L75)

Excerpt:

```zig
// FAST: build the integration plan first so we know exactly which
//       high-resolution wavelengths the 701 outputs will need.
const wavelength_sampling = try WavelengthSampling.buildWavelengthSampling(
    allocator,
    scene,
    prepared,
    &resolved_axis,
    radiance_calibration,
    irradiance_calibration,
    implementations,
);
defer allocator.free(wavelength_sampling);
// FAST: dedupe — collapse duplicate high-resolution wavelengths to a
//       single unique list. The transport step receives each needed
//       high-resolution wavelength once.
const forward_misses = try WavelengthSampling.collectUniqueForwardMisses(
    allocator,
    wavelength_sampling,
);
defer allocator.free(forward_misses);
// FAST: calculate radiance for the unique list once, store the results
//       in the evaluation_cache so the integration loop just looks them up.
try SpectralEval.prefetchForwardSamples(
    allocator,
    scene,
    route,
    prepared,
    implementations,
    safe_span,
    forward_misses,
    evaluation_cache,
);
```

The duplicate removal is explicit.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig#L109-L135)

```zig
pub fn collectUniqueForwardMisses(
    allocator: Allocator,
    plans: []const WavelengthSampling,
) ![]SpectralEval.ForwardCacheMiss {
    // FAST: a hash set keeps each high-resolution wavelength only once.
    var seen = std.AutoHashMap(u64, void).init(allocator);
    defer seen.deinit();
    var misses = std.ArrayList(SpectralEval.ForwardCacheMiss).empty;
    errdefer misses.deinit(allocator);

    for (plans) |plan| {
        const integration_sample_count = if (plan.radiance_integration.enabled) plan.radiance_integration.sample_count else 1;
        for (0..integration_sample_count) |sample_index| {
            const wavelength_nm = if (plan.radiance_integration.enabled)
                plan.radiance_wavelength_nm + plan.radiance_integration.offsets_nm[sample_index]
            else
                plan.radiance_wavelength_nm;
            const key = SpectralEval.SpectralEvaluationCache.keyFor(wavelength_nm);
            const entry = try seen.getOrPut(key);
            // FAST: this is the dedup decision — a duplicate is dropped here,
            //       so the unique list grows by at most one entry per wavelength.
            if (entry.found_existing) continue;
            try misses.append(allocator, .{
                .key = key,
                .wavelength_nm = wavelength_nm,
            });
        }
    }
```

Those high-resolution radiance calculations are independent of one another, so zdisamar can split the list across CPU cores.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig#L339-L386)

```zig
// FAST: the unique list is independent across entries (no entry depends on
//       another's result), so split it across worker threads. Each worker
//       owns a slice of the work and a slice of the result buffer.
var error_state = ForwardPrefetchErrorState{};
const workers = try allocator.alloc(ForwardPrefetchWorker, worker_count);
defer allocator.free(workers);
const threads = try allocator.alloc(std.Thread, worker_count - 1);
defer allocator.free(threads);

const base_count = misses.len / worker_count;
const remainder = misses.len % worker_count;
var start_index: usize = 0;
var started_thread_count: usize = 0;
for (0..worker_count) |worker_index| {
    const batch_count = base_count + @as(usize, if (worker_index < remainder) 1 else 0);
    const end_index = start_index + batch_count;
    workers[worker_index] = .{
        .scene = scene,
        .route = route,
        .prepared = prepared,
        .implementations = implementations,
        .safe_span = safe_span,
        .misses = misses[start_index..end_index],
        .results = results[start_index..end_index],
        .error_state = &error_state,
    };
    if (worker_index + 1 < worker_count) {
        threads[started_thread_count] = std.Thread.spawn(
            .{},
            prefetchForwardWorkerMain,
            .{&workers[worker_index]},
        ) catch {
            prefetchForwardWorkerMain(&workers[worker_index]);
            start_index = end_index;
            continue;
        };
        started_thread_count += 1;
    } else {
        prefetchForwardWorkerMain(&workers[worker_index]);
    }
    start_index = end_index;
}
for (threads[0..started_thread_count]) |thread| thread.join();
if (error_state.err) |err| return err;
```

The number of CPU batches is capped by the machine's available CPU count.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig#L383-L387)

```zig
pub fn preferredForwardWorkerCount(miss_count: usize) usize {
    if (miss_count < min_parallel_forward_miss_count) return 1;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return @min(cpu_count, @max(@as(usize, 1), miss_count / min_parallel_forward_miss_count));
}
```

After that, the output loop reads the stored high-resolution radiance values during instrument integration.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/instrument_grid/grid_calculation/simulate.zig#L91-L114)

```zig
// FAST: at this point every unique high-resolution wavelength is in the
//       evaluation_cache. The output loop only *integrates* over cached
//       values — no new radiance work happens here.
for (wavelength_sampling, 0..) |plan, index| {
    const nominal_wavelength_nm = plan.nominal_wavelength_nm;
    buffers.wavelengths[index] = nominal_wavelength_nm;

    const integrated = try SpectralEval.integrateForwardAtNominal(
        allocator,
        scene,
        route,
        prepared,
        plan.radiance_wavelength_nm,
        safe_span,
        implementations,
        buffers.layer_inputs[0..transport_layer_count],
        buffers.pseudo_spherical_layers,
        buffers.source_interfaces[0 .. transport_layer_count + 1],
        buffers.rtm_quadrature_levels[0 .. transport_layer_count + 1],
        buffers.pseudo_spherical_samples,
        buffers.pseudo_spherical_level_starts[0 .. transport_layer_count + 1],
        buffers.pseudo_spherical_level_altitudes[0 .. transport_layer_count + 1],
        evaluation_cache,
        &plan.radiance_integration,
    );
```

## Why It Matters

Each of the 701 output wavelengths is built from a few nearby high-resolution samples, and many output points can ask for the same high-resolution wavelength. Without a unique-list cache, repeated requests can turn into repeated transport work.

The fix is the same trick you would use to speed up any slow function: compute each unique input once, then look it up.

```python
# Slow: every output recomputes its high-resolution samples,
# so the same wavelength gets calculated many times.
results = []
for output_wavelength in outputs:
    for hr in samples_needed_for(output_wavelength):
        results.append(expensive_radiance(hr))

# Fast: collect the unique list, calculate once, then look up.
unique = {hr for o in outputs for hr in samples_needed_for(o)}
cache  = {hr: expensive_radiance(hr) for hr in unique}
results = [cache[hr] for o in outputs for hr in samples_needed_for(o)]
```

Each entry in `unique` is independent, so zdisamar also splits the work across CPU cores. The checkpoint that includes this change and the shared layer-geometry change saved about 67.88 s; the timing table does not split the two changes.
