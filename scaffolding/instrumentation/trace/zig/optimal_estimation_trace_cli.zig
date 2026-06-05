const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal");
const timing = internal.common.runtime_io;

const InstrumentGrid = internal.forward_model.instrument_grid;
const OptimalEstimation = internal.optimal_estimation;
const Trace = internal.forward_model.performance_trace;
const o2a_reference = internal.o2a_reference;

const default_output_dir = "out/optimal-estimation-trace";
const measurement_sigma_reflectance = 1.0e-3;

const AtomicUsize = std.atomic.Value(usize);
const Allocator = std.mem.Allocator;
const max_allocation_site_count = 512;
const max_reported_allocation_sites = 12;

const Config = struct {
    output_dir: []const u8 = default_output_dir,
    max_iterations: usize = 3,
};

// Snapshot of the trace-only allocation counter.
// layout(64-bit):
//   size: 64 B, align: 8 B
//   field storage: 64 B across 8 usize fields; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 1 cache line(s) at 64 B per line
//   count: one stack value per measured phase boundary
//   footprint: per instance = 64 B (0.062 KiB)
const AllocationSnapshot = struct {
    alloc_count: usize,
    free_count: usize,
    resize_count: usize,
    remap_count: usize,
    allocated_bytes: usize,
    freed_bytes: usize,
    live_bytes: usize,
    phase_peak_live_bytes: usize,
};

// Difference between two allocation snapshots from the trace executable.
// layout(64-bit):
//   size: 72 B, align: 8 B
//   field storage: 72 B across 9 usize fields; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: one stack value per reported trace phase
//   footprint: per instance = 72 B (0.070 KiB)
const AllocationDelta = struct {
    alloc_count: usize,
    free_count: usize,
    resize_count: usize,
    remap_count: usize,
    allocated_bytes: usize,
    freed_bytes: usize,
    live_bytes_before: usize,
    live_bytes_after: usize,
    peak_live_bytes_over_start: usize,
};

const AllocationSiteKind = enum {
    alloc,
    resize_growth,
    remap_growth,
};

// Aggregated allocation call site captured by the trace-only allocator.
// layout(64-bit):
//   size: 40 B, align: 8 B
//   field storage: 40 B across 5 usize fields; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: one fixed-table slot per observed return address in a measured phase
//   footprint: per instance = 40 B (0.039 KiB)
const AllocationSite = struct {
    return_address: usize = 0,
    alloc_count: usize = 0,
    resize_growth_count: usize = 0,
    remap_growth_count: usize = 0,
    allocated_bytes: usize = 0,
};

// Top allocation sites copied out of the trace allocator before the next phase reset.
// layout(64-bit):
//   size: 504 B, align: 8 B
//   field storage: sites=480 B, count=8 B, untracked_alloc_count=8 B, untracked_allocated_bytes=8 B
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: one stack value for each reported phase
//   footprint: per instance = 504 B (0.492 KiB)
const AllocationSiteReport = struct {
    sites: [max_reported_allocation_sites]AllocationSite = [_]AllocationSite{.{}} ** max_reported_allocation_sites,
    count: usize = 0,
    untracked_alloc_count: usize = 0,
    untracked_allocated_bytes: usize = 0,

    fn include(self: *AllocationSiteReport, site: AllocationSite) void {
        if (site.allocated_bytes == 0) return;
        var insert_index: usize = 0;
        while (insert_index < self.count and self.sites[insert_index].allocated_bytes >= site.allocated_bytes) {
            insert_index += 1;
        }
        if (insert_index >= max_reported_allocation_sites) return;

        const last = @min(self.count, max_reported_allocation_sites - 1);
        var move_index = last;
        while (move_index > insert_index) : (move_index -= 1) {
            self.sites[move_index] = self.sites[move_index - 1];
        }
        self.sites[insert_index] = site;

        if (self.count < max_reported_allocation_sites) self.count += 1;
    }
};

// Shape summary for the reusable wavelength plan retained in ProductStorage.
// layout(64-bit):
//   size: 64 B, align: 8 B
//   field storage: 64 B across 8 usize fields; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: one stack value in the trace report
//   footprint: per instance = 64 B (0.062 KiB)
const WavelengthPlanStats = struct {
    row_count: usize = 0,
    kernel_ref_count: usize = 0,
    disabled_kernel_count: usize = 0,
    inline_kernel_count: usize = 0,
    side_kernel_count: usize = 0,
    max_kernel_sample_count: usize = 0,
    side_sample_count: usize = 0,
    forward_miss_count: usize = 0,
};

// Trace-only allocator wrapper. Normal product builds never instantiate it; the
// build graph wires this file only into the explicit optimal-estimation trace executable.
// layout(64-bit):
//   size: 20592 B, align: 8 B
// field storage: child=16 B, eight atomic counters=64 B, site mutex=4 B, allocation_sites=20480 B, site counters=24 B;
// padding: 4 B
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   out-of-line: child allocator owns the actual memory; site buckets are fixed inline trace storage
//   cache span: 322 cache line(s) at 64 B per line
//   count: one live value in the trace executable
//   footprint: per instance = 20592 B (20.109 KiB); no heap storage
const CountingAllocator = struct {
    child: Allocator,
    alloc_count: AtomicUsize = AtomicUsize.init(0),
    free_count: AtomicUsize = AtomicUsize.init(0),
    resize_count: AtomicUsize = AtomicUsize.init(0),
    remap_count: AtomicUsize = AtomicUsize.init(0),
    allocated_bytes: AtomicUsize = AtomicUsize.init(0),
    freed_bytes: AtomicUsize = AtomicUsize.init(0),
    live_bytes: AtomicUsize = AtomicUsize.init(0),
    phase_peak_live_bytes: AtomicUsize = AtomicUsize.init(0),
    site_mutex: std.Io.Mutex = .init,
    allocation_sites: [max_allocation_site_count]AllocationSite = [_]AllocationSite{.{}} ** max_allocation_site_count,
    allocation_site_count: usize = 0,
    untracked_site_alloc_count: usize = 0,
    untracked_site_allocated_bytes: usize = 0,

    fn init(child: Allocator) CountingAllocator {
        return .{ .child = child };
    }

    fn allocator(self: *CountingAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn snapshot(self: *CountingAllocator) AllocationSnapshot {
        return .{
            .alloc_count = self.alloc_count.load(.monotonic),
            .free_count = self.free_count.load(.monotonic),
            .resize_count = self.resize_count.load(.monotonic),
            .remap_count = self.remap_count.load(.monotonic),
            .allocated_bytes = self.allocated_bytes.load(.monotonic),
            .freed_bytes = self.freed_bytes.load(.monotonic),
            .live_bytes = self.live_bytes.load(.monotonic),
            .phase_peak_live_bytes = self.phase_peak_live_bytes.load(.monotonic),
        };
    }

    fn resetPhasePeak(self: *CountingAllocator) AllocationSnapshot {
        const start = self.snapshot();
        self.phase_peak_live_bytes.store(start.live_bytes, .monotonic);
        self.resetAllocationSites();
        return start;
    }

    fn delta(self: *CountingAllocator, start: AllocationSnapshot) AllocationDelta {
        const finish = self.snapshot();
        return .{
            .alloc_count = finish.alloc_count - start.alloc_count,
            .free_count = finish.free_count - start.free_count,
            .resize_count = finish.resize_count - start.resize_count,
            .remap_count = finish.remap_count - start.remap_count,
            .allocated_bytes = finish.allocated_bytes - start.allocated_bytes,
            .freed_bytes = finish.freed_bytes - start.freed_bytes,
            .live_bytes_before = start.live_bytes,
            .live_bytes_after = finish.live_bytes,
            .peak_live_bytes_over_start = finish.phase_peak_live_bytes -| start.live_bytes,
        };
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        _ = self.alloc_count.fetchAdd(1, .monotonic);
        _ = self.allocated_bytes.fetchAdd(len, .monotonic);
        self.addLiveBytes(len);
        self.recordAllocationSite(ret_addr, len, .alloc);
        return ptr;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        _ = self.resize_count.fetchAdd(1, .monotonic);
        self.recordSizeChange(memory.len, new_len, ret_addr, .resize_growth);
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        _ = self.remap_count.fetchAdd(1, .monotonic);
        self.recordSizeChange(memory.len, new_len, ret_addr, .remap_growth);
        return ptr;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        self.child.rawFree(memory, alignment, ret_addr);
        _ = self.free_count.fetchAdd(1, .monotonic);
        _ = self.freed_bytes.fetchAdd(memory.len, .monotonic);
        _ = self.live_bytes.fetchSub(memory.len, .monotonic);
    }

    fn recordSizeChange(
        self: *CountingAllocator,
        old_len: usize,
        new_len: usize,
        ret_addr: usize,
        kind: AllocationSiteKind,
    ) void {
        if (new_len > old_len) {
            const delta_bytes = new_len - old_len;
            _ = self.allocated_bytes.fetchAdd(delta_bytes, .monotonic);
            self.addLiveBytes(delta_bytes);
            self.recordAllocationSite(ret_addr, delta_bytes, kind);
        } else if (old_len > new_len) {
            const delta_bytes = old_len - new_len;
            _ = self.freed_bytes.fetchAdd(delta_bytes, .monotonic);
            _ = self.live_bytes.fetchSub(delta_bytes, .monotonic);
        }
    }

    fn addLiveBytes(self: *CountingAllocator, byte_count: usize) void {
        const previous = self.live_bytes.fetchAdd(byte_count, .monotonic);
        const live = previous + byte_count;
        self.updatePeak(&self.phase_peak_live_bytes, live);
    }

    fn updatePeak(self: *CountingAllocator, counter: *AtomicUsize, candidate: usize) void {
        _ = self;
        var current = counter.load(.monotonic);
        while (candidate > current) {
            current = counter.cmpxchgWeak(current, candidate, .monotonic, .monotonic) orelse return;
        }
    }

    fn resetAllocationSites(self: *CountingAllocator) void {
        std.Io.Threaded.mutexLock(&self.site_mutex);
        defer std.Io.Threaded.mutexUnlock(&self.site_mutex);
        self.allocation_site_count = 0;
        self.untracked_site_alloc_count = 0;
        self.untracked_site_allocated_bytes = 0;
    }

    fn recordAllocationSite(
        self: *CountingAllocator,
        return_address: usize,
        allocated_bytes: usize,
        kind: AllocationSiteKind,
    ) void {
        std.Io.Threaded.mutexLock(&self.site_mutex);
        defer std.Io.Threaded.mutexUnlock(&self.site_mutex);

        for (self.allocation_sites[0..self.allocation_site_count]) |*site| {
            if (site.return_address != return_address) continue;
            switch (kind) {
                .alloc => site.alloc_count += 1,
                .resize_growth => site.resize_growth_count += 1,
                .remap_growth => site.remap_growth_count += 1,
            }
            site.allocated_bytes += allocated_bytes;
            return;
        }

        if (self.allocation_site_count >= self.allocation_sites.len) {
            self.untracked_site_alloc_count += 1;
            self.untracked_site_allocated_bytes += allocated_bytes;
            return;
        }

        var site: AllocationSite = .{ .return_address = return_address };
        switch (kind) {
            .alloc => site.alloc_count = 1,
            .resize_growth => site.resize_growth_count = 1,
            .remap_growth => site.remap_growth_count = 1,
        }
        site.allocated_bytes = allocated_bytes;
        self.allocation_sites[self.allocation_site_count] = site;
        self.allocation_site_count += 1;
    }

    fn allocationSiteReport(self: *CountingAllocator) AllocationSiteReport {
        std.Io.Threaded.mutexLock(&self.site_mutex);
        defer std.Io.Threaded.mutexUnlock(&self.site_mutex);

        var report: AllocationSiteReport = .{
            .untracked_alloc_count = self.untracked_site_alloc_count,
            .untracked_allocated_bytes = self.untracked_site_allocated_bytes,
        };
        for (self.allocation_sites[0..self.allocation_site_count]) |site| {
            report.include(site);
        }
        return report;
    }
};

pub fn main(init: std.process.Init) !void {
    return mainInner(init) catch |err| {
        std.debug.print("optimal-estimation-trace failed: {}\n", .{err});
        return err;
    };
}

fn mainInner(init: std.process.Init) !void {

    // instrumentation: OE trace frame
    // captures: retrieval run boundary, zones, and allocation deltas
    // why: split setup, warmup, and iteration costs.
    const main_zone = Trace.staticZone(@src(), "oe_trace.main");
    defer main_zone.end();

    // instrumentation: trace frame markers
    // captures: start/end messages and frame boundaries
    // why: make the retrieval run easy to find in Tracy captures.
    Trace.message("zdisamar optimal estimation trace start");
    Trace.frameMark();
    defer Trace.frameMark();
    defer Trace.message("zdisamar optimal estimation trace end");

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    var counting_allocator = CountingAllocator.init(debug_allocator.allocator());
    const allocator = counting_allocator.allocator();

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const config = try parseArgs(args);
    try std.Io.Dir.cwd().createDirPath(init.io, config.output_dir);

    const input = o2a_reference.defaultInput();

    // instrumentation: OE allocation trace
    // captures: reference preparation allocations
    // why: separate one-time setup memory from retrieval memory.
    var reference_timer = timing.Timer.start(init.io);
    const reference_alloc_start = counting_allocator.resetPhasePeak();
    var prepared_case = try o2a_reference.prepareResolvedVendorO2ACase(allocator, &input);
    const reference_prepare_ns = reference_timer.read();
    const reference_allocations = counting_allocator.delta(reference_alloc_start);
    const reference_allocation_sites = counting_allocator.allocationSiteReport();
    defer prepared_case.deinit(allocator);

    const sample_count = prepared_case.reference.len;
    var measurement_wavelength_nm = try allocator.alloc(f64, sample_count);
    defer allocator.free(measurement_wavelength_nm);
    var measurement_reflectance = try allocator.alloc(f64, sample_count);
    defer allocator.free(measurement_reflectance);
    var measurement_variance = try allocator.alloc(f64, sample_count);
    defer allocator.free(measurement_variance);
    for (prepared_case.reference, 0..) |sample, index| {
        measurement_wavelength_nm[index] = sample.wavelength_nm;
        measurement_reflectance[index] = sample.reflectance;
        measurement_variance[index] = measurement_sigma_reflectance * measurement_sigma_reflectance;
    }

    const profile_altitude_km = [_]f64{ 0.0, 5.0, 10.0, 20.0, 40.0 };
    const profile_pressure_hpa = [_]f64{ 1013.25, 540.48, 264.36, 54.75, 2.87 };
    const pressure_profile = try OptimalEstimation.buildPressureProfile(
        allocator,
        &profile_altitude_km,
        &profile_pressure_hpa,
    );
    defer OptimalEstimation.freePressureProfile(allocator, pressure_profile);

    const reference_mid_pressure_hpa =
        0.5 * (input.aerosol.placement.top_pressure_hpa + input.aerosol.placement.bottom_pressure_hpa);
    const layer_thickness_hpa =
        input.aerosol.placement.bottom_pressure_hpa - input.aerosol.placement.top_pressure_hpa;
    var state_specs = [_]OptimalEstimation.StateSpec{
        .{
            .state = .aerosol_optical_depth,
            .initial = 0.85 * input.aerosol.optical_depth + 0.02,
            .prior = 0.85 * input.aerosol.optical_depth + 0.02,
            .variance = 1.0,
            .lower_bound = 0.0,
            .upper_bound = OptimalEstimation.no_upper_bound,
        },
        .{
            .state = .aerosol_layer_mid_pressure_hpa,
            .initial = reference_mid_pressure_hpa + 20.0,
            .prior = reference_mid_pressure_hpa + 20.0,
            .variance = 150.0 * 150.0,
            .lower_bound = 225.0,
            .upper_bound = input.surface_pressure_hpa - 100.0,
            .thickness_hpa = layer_thickness_hpa,
            .interval_index_1based = input.aerosol.placement.interval_index_1based,
            .pressure_altitude_profile = pressure_profile,
        },
    };

    var product_storage: InstrumentGrid.ProductStorage = .{};
    defer product_storage.deinit(allocator);

    var warm_config = prepared_case.rtm_config;
    warm_config.derivative_mode = .semi_analytical;
    warm_config.derivative_state_mask = derivativeStateMask(&state_specs);

    // instrumentation: OE allocation trace
    // captures: session workspace warmup
    // why: measure reusable setup before retrieval iterations.
    var warm_timer = timing.Timer.start(init.io);
    const warm_alloc_start = counting_allocator.resetPhasePeak();
    try InstrumentGrid.warmProductWorkspace(
        allocator,
        &product_storage,
        &prepared_case.scene,
        warm_config,
        &prepared_case.prepared,
    );
    const session_warm_ns = warm_timer.read();
    const session_warm_allocations = counting_allocator.delta(warm_alloc_start);
    const session_warm_allocation_sites = counting_allocator.allocationSiteReport();

    // instrumentation: OE allocation trace
    // captures: retrieval wall time and allocation sites
    // why: find repeated memory cost inside the OE boundary.
    var retrieval_timer = timing.Timer.start(init.io);
    const retrieval_alloc_start = counting_allocator.resetPhasePeak();
    var result = try OptimalEstimation.runO2A(
        allocator,
        &input,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
        &state_specs,
        &product_storage,
        .{
            .max_iterations = config.max_iterations,
            .state_vector_convergence_threshold = 1.0,
            .max_change_transformed_state = 1.0,
        },
    );
    const retrieval_ns = retrieval_timer.read();
    const retrieval_allocations = counting_allocator.delta(retrieval_alloc_start);
    const retrieval_allocation_sites = counting_allocator.allocationSiteReport();
    const wavelength_plan_stats = collectWavelengthPlanStats(&product_storage);
    defer result.deinit(allocator);

    try writeSummary(
        init.io,
        config.output_dir,
        reference_prepare_ns,
        session_warm_ns,
        retrieval_ns,
        sample_count,
        config.max_iterations,
        &input,
        reference_mid_pressure_hpa,
        &result,
        reference_allocations,
        session_warm_allocations,
        retrieval_allocations,
        reference_allocation_sites,
        session_warm_allocation_sites,
        retrieval_allocation_sites,
        wavelength_plan_stats,
    );

    std.debug.print(
        "wrote optimal-estimation trace summary to {s} (retrieval_s={d:.6}, iterations={})\n",
        .{
            config.output_dir,
            @as(f64, @floatFromInt(retrieval_ns)) / 1.0e9,
            result.iteration_count,
        },
    );
}

fn derivativeStateMask(state_specs: []const OptimalEstimation.StateSpec) u8 {
    var mask: u8 = 0;
    for (state_specs) |spec| mask |= @as(u8, 1) << @intCast(@intFromEnum(spec.state));
    return mask;
}

fn parseArgs(args: []const [:0]const u8) !Config {
    var config: Config = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--output-dir")) {
            index += 1;

            if (index >= args.len) return error.MissingOutputDir;
            config.output_dir = args[index];
        } else if (std.mem.eql(u8, arg, "--max-iterations")) {
            index += 1;

            if (index >= args.len) return error.MissingMaxIterations;
            config.max_iterations = try std.fmt.parseInt(usize, args[index], 10);
        } else {
            return error.UnsupportedArgument;
        }
    }
    return config;
}

fn writeSummary(
    io: std.Io,
    output_dir: []const u8,
    reference_prepare_ns: u64,
    session_warm_ns: u64,
    retrieval_ns: u64,
    sample_count: usize,
    max_iterations: usize,
    input: *const o2a_reference.O2AInput,
    reference_mid_pressure_hpa: f64,
    result: *const OptimalEstimation.Result,
    reference_allocations: AllocationDelta,
    session_warm_allocations: AllocationDelta,
    retrieval_allocations: AllocationDelta,
    reference_allocation_sites: AllocationSiteReport,
    session_warm_allocation_sites: AllocationSiteReport,
    retrieval_allocation_sites: AllocationSiteReport,
    wavelength_plan_stats: WavelengthPlanStats,
) !void {
    var file = try openOutputFile(io, std.heap.page_allocator, output_dir, "summary.json");
    defer file.close(io);

    const retrieved_aod = result.state[0];
    const retrieved_mid_pressure_hpa = result.state[1];
    const reference_aod = input.aerosol.optical_depth;
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.print(
        \\{{
        \\  "trace_enabled": {},
        \\  "sample_count": {},
        \\  "max_iterations": {},
        \\  "iteration_count": {},
        \\  "converged": {},
        \\  "executable_vmaddr_slide": "0x{x}",
        \\  "reference_prepare_ns": {},
        \\  "reference_prepare_s": {d:.9},
        \\  "session_warm_ns": {},
        \\  "session_warm_s": {d:.9},
        \\  "retrieval_wall_ns": {},
        \\  "retrieval_wall_s": {d:.9},
        \\  "measurement_sigma_reflectance": {e:.17},
        \\  "reference_state": {{
        \\    "aerosol_optical_depth": {e:.17},
        \\    "aerosol_layer_mid_pressure_hpa": {e:.17}
        \\  }},
        \\  "retrieved_state": {{
        \\    "aerosol_optical_depth": {e:.17},
        \\    "aerosol_layer_mid_pressure_hpa": {e:.17}
        \\  }},
        \\  "residuals": {{
        \\    "aerosol_optical_depth_abs_error": {e:.17},
        \\    "aerosol_layer_mid_pressure_abs_error_hpa": {e:.17}
        \\  }},
        \\  "allocation_stats": {{
        \\
    ,
        .{
            Trace.enabled,
            sample_count,
            max_iterations,
            result.iteration_count,
            result.converged,
            executableVmaddrSlide(),
            reference_prepare_ns,
            @as(f64, @floatFromInt(reference_prepare_ns)) / 1.0e9,
            session_warm_ns,
            @as(f64, @floatFromInt(session_warm_ns)) / 1.0e9,
            retrieval_ns,
            @as(f64, @floatFromInt(retrieval_ns)) / 1.0e9,
            measurement_sigma_reflectance,
            reference_aod,
            reference_mid_pressure_hpa,
            retrieved_aod,
            retrieved_mid_pressure_hpa,
            @abs(retrieved_aod - reference_aod),
            @abs(retrieved_mid_pressure_hpa - reference_mid_pressure_hpa),
        },
    );
    try writeAllocationDelta(&writer.interface, "reference_prepare", reference_allocations, true);
    try writeAllocationDelta(&writer.interface, "session_warm", session_warm_allocations, true);
    try writeAllocationDelta(&writer.interface, "retrieval", retrieval_allocations, false);
    try writer.interface.writeAll(
        \\  },
        \\  "allocation_top_sites": {
        \\
    );
    try writeAllocationSiteReport(&writer.interface, "reference_prepare", reference_allocation_sites, true);
    try writeAllocationSiteReport(&writer.interface, "session_warm", session_warm_allocation_sites, true);
    try writeAllocationSiteReport(&writer.interface, "retrieval", retrieval_allocation_sites, false);
    try writer.interface.writeAll(
        \\  },
        \\
    );
    try writeWavelengthPlanStats(&writer.interface, wavelength_plan_stats);
    try writer.interface.writeAll(
        \\}
        \\
    );
    try writer.interface.flush();
}

fn writeAllocationDelta(
    writer: *std.Io.Writer,
    name: []const u8,
    delta_value: AllocationDelta,
    needs_comma: bool,
) !void {
    try writer.print(
        \\    "{s}": {{
        \\      "alloc_count": {},
        \\      "free_count": {},
        \\      "resize_count": {},
        \\      "remap_count": {},
        \\      "allocated_bytes": {},
        \\      "freed_bytes": {},
        \\      "live_bytes_before": {},
        \\      "live_bytes_after": {},
        \\      "peak_live_bytes_over_start": {}
        \\    }}{s}
        \\
    ,
        .{
            name,
            delta_value.alloc_count,
            delta_value.free_count,
            delta_value.resize_count,
            delta_value.remap_count,
            delta_value.allocated_bytes,
            delta_value.freed_bytes,
            delta_value.live_bytes_before,
            delta_value.live_bytes_after,
            delta_value.peak_live_bytes_over_start,
            if (needs_comma) "," else "",
        },
    );
}

fn writeAllocationSiteReport(
    writer: *std.Io.Writer,
    name: []const u8,
    report: AllocationSiteReport,
    needs_comma: bool,
) !void {
    const vmaddr_slide = executableVmaddrSlide();
    try writer.print(
        \\    "{s}": {{
        \\      "untracked_alloc_count": {},
        \\      "untracked_allocated_bytes": {},
        \\      "sites": [
        \\
    ,
        .{ name, report.untracked_alloc_count, report.untracked_allocated_bytes },
    );
    for (report.sites[0..report.count], 0..) |site, index| {
        const unslid_return_address = site.return_address -| vmaddr_slide;
        try writer.print(
            \\        {{"return_address": "0x{x}", "unslid_return_address": "0x{x}",
            \\          "alloc_count": {}, "resize_growth_count": {},
            \\          "remap_growth_count": {}, "allocated_bytes": {}}}{s}
            \\
        ,
            .{
                site.return_address,
                unslid_return_address,
                site.alloc_count,
                site.resize_growth_count,
                site.remap_growth_count,
                site.allocated_bytes,
                if (index + 1 == report.count) "" else ",",
            },
        );
    }
    try writer.print(
        \\      ]
        \\    }}{s}
        \\
    ,
        .{if (needs_comma) "," else ""},
    );
}

fn collectWavelengthPlanStats(storage: *const InstrumentGrid.ProductStorage) WavelengthPlanStats {
    const plan = storage.wavelength_sampling.view();
    var stats: WavelengthPlanStats = .{
        .row_count = plan.rows.len,
        .kernel_ref_count = plan.rows.len * 2,
        .side_sample_count = plan.kernel_storage.offsets_nm.len,
        .forward_miss_count = storage.forward_miss_plan.misses.len,
    };
    for (plan.rows) |row| {
        updateWavelengthPlanStats(&stats, row.radiance_integration);
        updateWavelengthPlanStats(&stats, row.irradiance_integration);
    }
    return stats;
}

fn updateWavelengthPlanStats(
    stats: *WavelengthPlanStats,
    kernel: anytype,
) void {
    if (!kernel.enabled()) {
        stats.disabled_kernel_count += 1;
        stats.max_kernel_sample_count = @max(stats.max_kernel_sample_count, 1);
        return;
    }
    const sample_count = kernel.activeSampleCount();
    stats.max_kernel_sample_count = @max(stats.max_kernel_sample_count, sample_count);
    if (sample_count <= kernel.inline_offsets_nm.len) {
        stats.inline_kernel_count += 1;
    } else {
        stats.side_kernel_count += 1;
    }
}

fn writeWavelengthPlanStats(writer: *std.Io.Writer, stats: WavelengthPlanStats) !void {
    try writer.print(
        \\  "wavelength_plan": {{
        \\    "row_count": {},
        \\    "kernel_ref_count": {},
        \\    "disabled_kernel_count": {},
        \\    "inline_kernel_count": {},
        \\    "side_kernel_count": {},
        \\    "max_kernel_sample_count": {},
        \\    "side_sample_count": {},
        \\    "side_storage_bytes": {},
        \\    "forward_miss_count": {}
        \\  }}
        \\
    ,
        .{
            stats.row_count,
            stats.kernel_ref_count,
            stats.disabled_kernel_count,
            stats.inline_kernel_count,
            stats.side_kernel_count,
            stats.max_kernel_sample_count,
            stats.side_sample_count,
            stats.side_sample_count * @sizeOf(f64) * 2,
            stats.forward_miss_count,
        },
    );
}

fn executableVmaddrSlide() usize {
    return if (builtin.os.tag == .macos)
        std.c._dyld_get_image_vmaddr_slide(0)
    else
        0;
}

fn openOutputFile(io: std.Io, allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.Io.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
}
