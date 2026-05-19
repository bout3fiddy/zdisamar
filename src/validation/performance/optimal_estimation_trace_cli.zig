const std = @import("std");
const internal = @import("internal");

const InstrumentGrid = internal.forward_model.instrument_grid;
const OptimalEstimation = internal.optimal_estimation;
const Trace = internal.forward_model.performance_trace;
const o2a_reference = internal.o2a_reference;

const default_output_dir = "out/optimal-estimation-trace";
const measurement_sigma_reflectance = 1.0e-3;

const AtomicUsize = std.atomic.Value(usize);
const Allocator = std.mem.Allocator;

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

// Trace-only allocator wrapper. Normal product builds never instantiate it; the
// build graph wires this file only into the explicit optimal-estimation trace executable.
// layout(64-bit):
//   size: 80 B, align: 8 B
//   field storage: child=16 B, eight atomic usize counters at 8 B each; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: child allocator owns the actual memory; counters are inline atomic scalars
//   cache span: 2 cache line(s) at 64 B per line
//   count: one live value in the trace executable
//   footprint: per instance = 80 B (0.078 KiB); no heap storage
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
        return ptr;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        _ = self.resize_count.fetchAdd(1, .monotonic);
        self.recordSizeChange(memory.len, new_len);
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        _ = self.remap_count.fetchAdd(1, .monotonic);
        self.recordSizeChange(memory.len, new_len);
        return ptr;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        self.child.rawFree(memory, alignment, ret_addr);
        _ = self.free_count.fetchAdd(1, .monotonic);
        _ = self.freed_bytes.fetchAdd(memory.len, .monotonic);
        _ = self.live_bytes.fetchSub(memory.len, .monotonic);
    }

    fn recordSizeChange(self: *CountingAllocator, old_len: usize, new_len: usize) void {
        if (new_len > old_len) {
            const delta_bytes = new_len - old_len;
            _ = self.allocated_bytes.fetchAdd(delta_bytes, .monotonic);
            self.addLiveBytes(delta_bytes);
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
};

pub fn main() !void {
    return mainInner() catch |err| {
        std.debug.print("optimal-estimation-trace failed: {}\n", .{err});
        return err;
    };
}

fn mainInner() !void {
    const main_zone = Trace.staticZone(@src(), "oe_trace.main");
    defer main_zone.end();
    Trace.message("zdisamar optimal estimation trace start");
    Trace.frameMark();
    defer Trace.frameMark();
    defer Trace.message("zdisamar optimal estimation trace end");

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    var counting_allocator = CountingAllocator.init(debug_allocator.allocator());
    const allocator = counting_allocator.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const config = try parseArgs(args);
    try std.fs.cwd().makePath(config.output_dir);

    const input = o2a_reference.defaultInput();

    var reference_timer = try std.time.Timer.start();
    const reference_alloc_start = counting_allocator.resetPhasePeak();
    var prepared_case = try o2a_reference.prepareResolvedVendorO2ACase(allocator, &input);
    const reference_prepare_ns = reference_timer.read();
    const reference_allocations = counting_allocator.delta(reference_alloc_start);
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

    var retrieval_timer = try std.time.Timer.start();
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
    defer result.deinit(allocator);

    try writeSummary(
        config.output_dir,
        reference_prepare_ns,
        retrieval_ns,
        sample_count,
        config.max_iterations,
        &input,
        reference_mid_pressure_hpa,
        &result,
        reference_allocations,
        retrieval_allocations,
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

fn parseArgs(args: []const []const u8) !Config {
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
    output_dir: []const u8,
    reference_prepare_ns: u64,
    retrieval_ns: u64,
    sample_count: usize,
    max_iterations: usize,
    input: *const o2a_reference.O2AInput,
    reference_mid_pressure_hpa: f64,
    result: *const OptimalEstimation.Result,
    reference_allocations: AllocationDelta,
    retrieval_allocations: AllocationDelta,
) !void {
    var file = try openOutputFile(std.heap.page_allocator, output_dir, "summary.json");
    defer file.close();

    const retrieved_aod = result.state[0];
    const retrieved_mid_pressure_hpa = result.state[1];
    const reference_aod = input.aerosol.optical_depth;
    var writer = file.writer(&.{});
    try writer.interface.print(
        \\{{
        \\  "trace_enabled": {},
        \\  "sample_count": {},
        \\  "max_iterations": {},
        \\  "iteration_count": {},
        \\  "converged": {},
        \\  "reference_prepare_ns": {},
        \\  "reference_prepare_s": {d:.9},
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
            reference_prepare_ns,
            @as(f64, @floatFromInt(reference_prepare_ns)) / 1.0e9,
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
    try writeAllocationDelta(&writer.interface, "retrieval", retrieval_allocations, false);
    try writer.interface.writeAll(
        \\  }
        \\}
        \\
    );
    try writer.interface.flush();
}

fn writeAllocationDelta(writer: *std.Io.Writer, name: []const u8, delta_value: AllocationDelta, needs_comma: bool) !void {
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

fn openOutputFile(allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.fs.cwd().createFile(path, .{ .truncate = true });
}
