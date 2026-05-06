# 09. Keep Full-Program Setup Out Of The Forward Timer

Forward-time saving: this mechanism mainly affects preparation and repeated setup, not the measured forward-pass wall. In the checkpoint table, preparation falls from 2.475131 s at `5ef6c71` to 0.509849 s at `862511b`, saving 1.965282 s before the forward run starts.

## What DISAMAR Does

DISAMAR is designed as a flexible executable. Its top-level program reads `Config.in`, sets static input, allocates dynamic workspace, and calls the retrieval program entrypoint.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/main_DISAMAR.f90#L101-L119)

Excerpt:

```fortran
status = disamar_load_file('Config.in', buffer)
if (status .ne. 0) then
    call disamar_logger('Failed to read Config.in', LOG_ERROR)
    goto 99999
end if

status = disamar_set_static_input_c('config', 0, buffer, 0)
if (status .ne. 0) then
    call disamar_logger('Failed to set static input', LOG_ERROR)
    goto 99999
end if

status = disamar_allocate_dynamic_workspace(dynamic_workspace)
if (status .ne. 0) then
    call disamar_logger('Failed to allocate dynamic workspace', LOG_ERROR)
    goto 99999
end if

status = disamar_retrieval(dynamic_workspace)
```

The executable also builds cross-section tables as part of the broader simulation setup.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/DISAMARModule.f90#L2100-L2115)

Excerpt:

```fortran
do iband = 1, globalS%numSpectrBands
  do iTrace = 1, globalS%nTrace
    ! DISAMAR prepares cross-section expansion coefficients during broad setup.
    ! zdisamar keeps fixed O2 A line/profile state outside repeated forward runs.
    if (  globalS%XsecHRLUTSimS(iband,iTrace)%createXsecPolyLUT  ) then
      prev_time = current_time(current_time_values)
      call createXsecLUT (errS, staticS, globalS%controlSimS, globalS%wavelHRSimS(iband),               &
                          globalS%weakAbsRetrS(iband), globalS%gasPTSimS, globalS%traceGasSimS(iTrace), &
                          globalS%XsecHRSimS(iband,iTrace), globalS%XsecHRLUTSimS(iband,iTrace))
      time = current_time(current_time_values)
      write(errS%temp,'(A,F14.3)') 'time for expansion coefficients simulation (sec) = ', time - prev_time
      call logDebug(errS%temp)
    end if
```

## What zdisamar Does

zdisamar separates preparation from the forward run. Fixed input files are cached by key.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/input/o2a_reference/fixed_asset_cache.zig#L83-L103)

Excerpt:

```zig
pub fn loadLineList(allocator: Allocator, spec: LineGasSpec) !?ReferenceData.SpectroscopyLineList {
    const key = lineListKey(spec);
    mutex.lock();
    defer mutex.unlock();

    const entry = cached_line_list orelse return null;
    if (entry.key != key) return null;
    return try entry.line_list.clone(allocator);
}

pub fn storeLineList(spec: LineGasSpec, line_list: ReferenceData.SpectroscopyLineList) !void {
    const allocator = std.heap.smp_allocator;
    const entry = LineListEntry{
        .key = lineListKey(spec),
        .line_list = try line_list.clone(allocator),
    };
    mutex.lock();
    defer mutex.unlock();
    if (cached_line_list) |*old| old.deinit(allocator);
    cached_line_list = entry;
}
```

Prepared line/profile state is also reused.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/optical_properties/state_build/profile_state_cache.zig#L24-L60)

Excerpt:

```zig
pub fn load(
    allocator: Allocator,
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_out: []ReferenceData.WeakLinePreparedState,
    strong_out: []ReferenceData.StrongLinePreparedState,
) !bool {
    if (!compatibleShape(temperatures_k, pressures_hpa, weak_out, strong_out)) return false;

    const key = computeKey(line_list, temperatures_k, pressures_hpa);
    mutex.lock();
    defer mutex.unlock();

    const entry = cached_entry orelse return false;
    if (entry.key != key or entry.weak_states.len != weak_out.len or entry.strong_states.len != strong_out.len) return false;
```

## Why It Matters

If parsing a config file and loading reference line lists happens inside every forward call, those one-time costs masquerade as forward-pass time. The simple fix is to do them once, outside the timed function, and pass the prepared state in.

```python
# Slow: every call re-parses config and re-loads the line list
def run_spectrum():
    config = parse_config_file("Config.in")    # disk + parsing
    lines  = load_line_list(config)            # large file load
    return forward(config, lines)

# Fast: prepare once, reuse across calls
config = parse_config_file("Config.in")
lines  = load_line_list(config)

def run_spectrum():
    return forward(config, lines)              # only the actual physics
```

This does not explain the whole forward-time speedup, but it is why setup can be discussed separately from the ~1.9 s forward wall. Preparation fell from 2.48 s to 0.51 s, saving 1.97 s before the forward run starts.
