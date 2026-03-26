//! Purpose:
//!   Compile canonical configuration documents into executable engine
//!   programs.
//!
//! Physics:
//!   This adapter wires typed experiment stages into the engine, then runs
//!   them to produce result objects and exports without altering the
//!   scientific meaning of the configured scenes.
//!
//! Vendor:
//!   Canonical execution / stage compilation adapter surface.
//!
//! Design:
//!   Separate program compilation from execution so stage validation and
//!   runtime binding happen before the engine is invoked.
//!
//! Invariants:
//!   Stage products must remain unique, retrieval stages must have valid
//!   bindings, and execution output targets must resolve to registered
//!   products.
//!
//! Validation:
//!   Canonical execution tests cover stage compilation, binding resolution,
//!   and export generation.

const std = @import("std");
const core_errors = @import("../../core/errors.zig");
const Engine = @import("../../core/Engine.zig").Engine;
const Request = @import("../../core/Request.zig").Request;
const Result = @import("../../core/Result.zig").Result;
const spectral_noise = @import("../../kernels/spectra/noise.zig");
const MeasurementSpaceProduct = @import("../../kernels/transport/measurement.zig").MeasurementSpaceProduct;
const SceneModel = @import("../../model/Scene.zig");
const MeasurementQuantity = @import("../../model/Measurement.zig").Quantity;
const export_spec = @import("../exporters/spec.zig");
const exporters = @import("../exporters/writer.zig");
const DocumentModule = @import("Document.zig");
const ResolvedExperiment = DocumentModule.ResolvedExperiment;
const Ingest = DocumentModule.Ingest;
const Stage = DocumentModule.Stage;
const StageKind = DocumentModule.StageKind;
const Product = DocumentModule.Product;
const ProductKind = DocumentModule.ProductKind;
const OutputSpec = DocumentModule.OutputSpec;
const ExportFormat = @import("../exporters/format.zig").ExportFormat;
const spectral_runtime = @import("../ingest/spectral_ascii_runtime.zig");
const Allocator = std.mem.Allocator;

pub const Error =
    core_errors.Error ||
    exporters.Error ||
    DocumentModule.Error ||
    error{
        DuplicateProduct,
        MissingOutputProduct,
        MissingMeasurementBinding,
        MissingNoiseSigma,
        MultipleMeasurementSpaceProducts,
        UnsupportedMeasurementBinding,
        UnsupportedOutputTarget,
        UnsupportedVendorControl,
    };

pub const StageExecution = struct {
    kind: StageKind,
    stage: Stage,
    product_requests: []const Request.RequestedProduct,
    diagnostics: @import("../../core/diagnostics.zig").DiagnosticsSpec,
};

pub const ProductRef = struct {
    name: []const u8,
    kind: ProductKind,
    stage_index: usize,
    observable: ?MeasurementQuantity = null,
    apply_noise: bool = false,
};

pub const ExportJob = struct {
    output: OutputSpec,
    target: ProductRef,
};

pub const StageOutcome = struct {
    kind: StageKind,
    result: Result,
};

pub const ExecutedOutput = struct {
    source_name: []const u8,
    kind: ProductKind,
    report: exporters.ExportReport,
};

pub const ExecutionOutcome = struct {
    allocator: Allocator,
    stage_outcomes: []StageOutcome,
    outputs: []ExecutedOutput,

    /// Purpose:
    ///   Release the owned stage outcomes and exporter reports.
    pub fn deinit(self: *ExecutionOutcome) void {
        for (self.stage_outcomes) |*stage_outcome| {
            stage_outcome.result.deinit(self.allocator);
        }
        if (self.stage_outcomes.len != 0) self.allocator.free(self.stage_outcomes);
        if (self.outputs.len != 0) self.allocator.free(self.outputs);
        self.* = undefined;
    }

    /// Purpose:
    ///   Return the result for a stage kind if it was executed.
    pub fn stageResult(self: *const ExecutionOutcome, kind: StageKind) ?*const Result {
        for (self.stage_outcomes) |*stage_outcome| {
            if (stage_outcome.kind == kind) return &stage_outcome.result;
        }
        return null;
    }
};

pub const ExecutionProgram = struct {
    allocator: Allocator,
    experiment: *ResolvedExperiment,
    stages: []StageExecution,
    products: []ProductRef,
    outputs: []ExportJob,

    /// Purpose:
    ///   Compile a resolved experiment into an execution program.
    pub fn init(allocator: Allocator, experiment: *ResolvedExperiment) !ExecutionProgram {
        var stage_count: usize = 0;
        if (experiment.simulation != null) stage_count += 1;
        if (experiment.retrieval != null) stage_count += 1;

        const stages = try allocator.alloc(StageExecution, stage_count);
        errdefer allocator.free(stages);

        var product_count: usize = 0;
        if (experiment.simulation) |stage| product_count += stage.products.len;
        if (experiment.retrieval) |stage| product_count += stage.products.len;
        const products = try allocator.alloc(ProductRef, product_count);
        errdefer allocator.free(products);

        const outputs = try allocator.alloc(ExportJob, experiment.outputs.len);
        errdefer allocator.free(outputs);

        // DECISION:
        //   Reject unsupported vendor controls before stage compilation so the
        //   runtime never sees a partially accepted experiment.
        try validateVendorControls(experiment);

        var stage_index: usize = 0;
        var initialized_stage_count: usize = 0;
        var product_index: usize = 0;
        errdefer {
            for (stages[0..initialized_stage_count]) |stage_execution| {
                if (stage_execution.product_requests.len != 0) allocator.free(stage_execution.product_requests);
            }
        }

        if (experiment.simulation) |stage| {
            try validateStageProducts(stage.products);
            const product_requests = try collectRequestedProducts(allocator, stage.products);
            stages[stage_index] = .{
                .kind = .simulation,
                .stage = stage.*,
                .product_requests = product_requests,
                .diagnostics = stage.diagnostics,
            };
            initialized_stage_count += 1;
            for (stage.products) |product| {
                try ensureUniqueProduct(products[0..product_index], product.name);
                products[product_index] = .{
                    .name = product.name,
                    .kind = product.kind,
                    .stage_index = stage_index,
                    .observable = product.observable,
                    .apply_noise = product.apply_noise,
                };
                product_index += 1;
            }
            stage_index += 1;
        }

        if (experiment.retrieval) |stage| {
            try validateStageProducts(stage.products);
            var diagnostics = stage.diagnostics;
            if (hasJacobianProduct(stage.products)) diagnostics.jacobians = true;
            const product_requests = try collectRequestedProducts(allocator, stage.products);
            stages[stage_index] = .{
                .kind = .retrieval,
                .stage = stage.*,
                .product_requests = product_requests,
                .diagnostics = diagnostics,
            };
            initialized_stage_count += 1;
            for (stage.products) |product| {
                try ensureUniqueProduct(products[0..product_index], product.name);
                products[product_index] = .{
                    .name = product.name,
                    .kind = product.kind,
                    .stage_index = stage_index,
                    .observable = product.observable,
                    .apply_noise = product.apply_noise,
                };
                product_index += 1;
            }
            stage_index += 1;
        }

        for (experiment.outputs, 0..) |output, output_index| {
            const target = findProduct(products, output.from) orelse return error.MissingOutputProduct;
            if (target.kind == .diagnostics) return error.UnsupportedOutputTarget;
            outputs[output_index] = .{
                .output = output,
                .target = target,
            };
        }

        return .{
            .allocator = allocator,
            .experiment = experiment,
            .stages = stages,
            .products = products,
            .outputs = outputs,
        };
    }

    /// Purpose:
    ///   Release the compiled stage plan and experiment ownership.
    pub fn deinit(self: *ExecutionProgram) void {
        for (self.stages) |stage| {
            if (stage.product_requests.len != 0) self.allocator.free(stage.product_requests);
        }
        if (self.stages.len != 0) self.allocator.free(self.stages);
        if (self.products.len != 0) self.allocator.free(self.products);
        if (self.outputs.len != 0) self.allocator.free(self.outputs);
        self.experiment.deinit();
        self.* = undefined;
    }

    /// Purpose:
    ///   Execute the compiled program against the engine and return stage and
    ///   export outcomes.
    pub fn execute(self: *const ExecutionProgram, allocator: Allocator, engine: *Engine) !ExecutionOutcome {
        const workspace_label = if (self.experiment.metadata.workspace.len != 0)
            self.experiment.metadata.workspace
        else if (self.experiment.metadata.id.len != 0)
            self.experiment.metadata.id
        else
            "canonical-config";

        var workspace = engine.createWorkspace(workspace_label);
        const stage_outcomes = try allocator.alloc(StageOutcome, self.stages.len);
        errdefer allocator.free(stage_outcomes);

        var executed_stage_count: usize = 0;
        errdefer {
            for (stage_outcomes[0..executed_stage_count]) |*stage_outcome| {
                stage_outcome.result.deinit(allocator);
            }
        }

        for (self.stages, 0..) |stage_execution, index| {
            var plan = try engine.preparePlan(stage_execution.stage.plan);
            defer plan.deinit();

            var request = Request.init(stage_execution.stage.scene);
            var owned_ingest_product: ?*MeasurementSpaceProduct = null;
            defer if (owned_ingest_product) |product| {
                product.deinit(allocator);
                allocator.destroy(product);
            };
            request.inverse_problem = stage_execution.stage.inverse;
            request.requested_products = stage_execution.product_requests;
            request.expected_derivative_mode = stage_execution.stage.plan.scene_blueprint.derivative_mode;
            request.diagnostics = stage_execution.diagnostics;

            if (stage_execution.kind == .retrieval and stage_execution.stage.inverse != null) {
                const source = stage_execution.stage.inverse.?.measurements.source;
                switch (source.kind()) {
                    .none => {},
                    .external_observation => return error.MissingMeasurementBinding,
                    .stage_product => {
                        const source_name = source.name();
                        const source_ref = findProduct(self.products, source_name) orelse return error.MissingMeasurementBinding;
                        if (source_ref.kind != .measurement_space) return error.UnsupportedMeasurementBinding;
                        if (source_ref.stage_index >= executed_stage_count) return error.MissingMeasurementBinding;
                        const source_result = &stage_outcomes[source_ref.stage_index].result;
                        if (source_result.measurement_space_product) |*source_product| {
                            request.measurement_binding = .{
                                .source = .{ .stage_product = .{ .name = source_ref.name } },
                                .borrowed_product = .init(source_product),
                            };
                        } else {
                            return error.MissingMeasurementBinding;
                        }
                    },
                    .ingest => {
                        const source_name = source.name();
                        const product = try buildIngestMeasurementProduct(
                            allocator,
                            self.experiment,
                            &request,
                            source_name,
                        );
                        owned_ingest_product = product;
                        request.measurement_binding = .{
                            .source = .{ .ingest = @import("../../model/Binding.zig").IngestRef.fromFullName(source_name) },
                            .borrowed_product = .init(product),
                        };
                    },
                    .asset, .bundle_default, .atmosphere => return error.UnsupportedMeasurementBinding,
                }
            }

            if (index != 0) workspace.reset();

            stage_outcomes[index] = .{
                .kind = stage_execution.kind,
                .result = try engine.execute(&plan, &workspace, &request),
            };
            if (stageRequestsAppliedNoise(stage_execution.stage.products)) {
                try applyNoiseToStageMeasurementProduct(
                    allocator,
                    &stage_outcomes[index].result,
                    &stage_execution.stage.scene,
                    stageNoiseSeed(stage_execution),
                );
            }
            executed_stage_count += 1;
        }

        const output_reports = try allocator.alloc(ExecutedOutput, self.outputs.len);
        errdefer allocator.free(output_reports);

        for (self.outputs, 0..) |job, output_index| {
            const stage_result = &stage_outcomes[job.target.stage_index].result;
            const view = try exportViewForTarget(stage_result, job.target);
            output_reports[output_index] = .{
                .source_name = job.target.name,
                .kind = job.target.kind,
                .report = try exporters.write(
                    allocator,
                    .{
                        .plugin_id = exporterPluginId(job.output.format),
                        .format = job.output.format,
                        .destination_uri = job.output.destination_uri,
                        .dataset_name = job.target.name,
                        .include_provenance = job.output.include_provenance,
                    },
                    view,
                ),
            };
        }

        return .{
            .allocator = allocator,
            .stage_outcomes = stage_outcomes,
            .outputs = output_reports,
        };
    }
};

/// Purpose:
///   Compile a resolved experiment without executing it.
pub fn compileResolved(allocator: Allocator, experiment: *ResolvedExperiment) !ExecutionProgram {
    return ExecutionProgram.init(allocator, experiment);
}

/// Purpose:
///   Resolve a canonical document, compile it, and execute it in one step.
pub fn resolveCompileAndExecute(
    allocator: Allocator,
    engine: *Engine,
    path: []const u8,
) !struct { program: ExecutionProgram, outcome: ExecutionOutcome } {
    var experiment = try DocumentModule.resolveFile(allocator, path);
    var experiment_owned = true;
    errdefer if (experiment_owned) experiment.deinit();

    var program = try compileResolved(allocator, experiment);
    experiment_owned = false;
    errdefer program.deinit();

    const outcome = try program.execute(allocator, engine);
    return .{
        .program = program,
        .outcome = outcome,
    };
}

fn collectRequestedProducts(allocator: Allocator, products: []const Product) ![]const Request.RequestedProduct {
    if (products.len == 0) return &[_]Request.RequestedProduct{};
    const requests = try allocator.alloc(Request.RequestedProduct, products.len);
    for (products, 0..) |product, index| {
        requests[index] = .named(
            product.name,
            requestProductKind(product.kind),
            product.observable,
        );
    }
    return requests;
}

fn requestProductKind(kind: ProductKind) Request.RequestedProductKind {
    return switch (kind) {
        .measurement_space => .measurement_space,
        .state_vector => .state_vector,
        .fitted_measurement => .fitted_measurement,
        .averaging_kernel => .averaging_kernel,
        .jacobian => .jacobian,
        .posterior_covariance => .posterior_covariance,
        .result => .result,
        .diagnostics => .diagnostics,
    };
}

fn validateStageProducts(products: []const Product) !void {
    var measurement_space_count: usize = 0;
    for (products) |product| {
        if (product.apply_noise and product.kind != .measurement_space) {
            return error.UnsupportedOutputTarget;
        }
        if (product.kind == .measurement_space) {
            measurement_space_count += 1;
            if (measurement_space_count > 1) return error.MultipleMeasurementSpaceProducts;
        }
    }
}

fn hasJacobianProduct(products: []const Product) bool {
    for (products) |product| {
        if (product.kind == .jacobian) return true;
    }
    return false;
}

fn ensureUniqueProduct(products: []const ProductRef, name: []const u8) !void {
    for (products) |product| {
        if (std.mem.eql(u8, product.name, name)) return error.DuplicateProduct;
    }
}

fn findProduct(products: []const ProductRef, name: []const u8) ?ProductRef {
    for (products) |product| {
        if (std.mem.eql(u8, product.name, name)) return product;
    }
    return null;
}

fn stageRequestsAppliedNoise(products: []const Product) bool {
    for (products) |product| {
        if (product.kind == .measurement_space and product.apply_noise) {
            return true;
        }
    }
    return false;
}

fn stageNoiseSeed(stage_execution: StageExecution) u64 {
    if (stage_execution.stage.noise_seed) |seed| return seed;

    var hasher = std.hash.Wyhash.init(@intFromEnum(stage_execution.kind));
    hasher.update(stage_execution.stage.scene.id);
    return hasher.final();
}

fn applyNoiseToStageMeasurementProduct(
    allocator: Allocator,
    result: *Result,
    scene: *const SceneModel.Scene,
    seed: u64,
) !void {
    if (result.measurement_space_product) |*product| {
        if (product.irradiance.len != product.radiance.len or product.reflectance.len != product.radiance.len) {
            return error.InvalidRequest;
        }

        const sample_count = product.radiance.len;
        const radiance_controls = scene.observation_model.resolvedChannelControls(.radiance).noise;
        const irradiance_controls = scene.observation_model.resolvedChannelControls(.irradiance).noise;
        const uses_explicit_channel_pipeline =
            scene.observation_model.measurement_pipeline.radiance.explicit or
            scene.observation_model.measurement_pipeline.irradiance.explicit;

        var fallback_radiance_sigma: []f64 = &.{};
        defer if (fallback_radiance_sigma.len != 0) allocator.free(fallback_radiance_sigma);

        var radiance_sigma: []const f64 = &.{};
        if (radiance_controls.enabled or !uses_explicit_channel_pipeline) {
            radiance_sigma = product.radiance_noise_sigma;
            if (radiance_sigma.len != sample_count or !hasPositiveSigma(radiance_sigma)) {
                fallback_radiance_sigma = try allocator.alloc(f64, sample_count);
                try spectral_noise.shotNoiseStd(product.radiance, radiance_controls.electrons_per_count, fallback_radiance_sigma);
                radiance_sigma = fallback_radiance_sigma;
                try storeFallbackRadianceSigma(allocator, product, radiance_sigma);
            }
        }

        var irradiance_sigma: []const f64 = &.{};
        if (irradiance_controls.enabled) {
            irradiance_sigma = product.irradiance_noise_sigma;
            if (irradiance_sigma.len != sample_count or !hasPositiveSigma(irradiance_sigma)) {
                return error.MissingNoiseSigma;
            }
        }

        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();
        for (0..sample_count) |index| {
            if (radiance_sigma.len == sample_count) {
                const perturbed = product.radiance[index] + random.floatNorm(f64) * radiance_sigma[index];
                product.radiance[index] = @max(perturbed, 0.0);
            }
            if (irradiance_sigma.len == sample_count) {
                const perturbed = product.irradiance[index] + random.floatNorm(f64) * irradiance_sigma[index];
                product.irradiance[index] = @max(perturbed, 0.0);
            }
            product.reflectance[index] = reflectanceForSample(scene, product.radiance[index], product.irradiance[index]);
        }
        recomputeMeasurementSummary(product);
        result.measurement_space = product.summary;
        return;
    }
    return error.UnsupportedOutputTarget;
}

fn storeFallbackRadianceSigma(
    allocator: Allocator,
    product: *MeasurementSpaceProduct,
    sigma: []const f64,
) !void {
    if (sigma.len != product.radiance.len) return error.ShapeMismatch;

    const sample_count = product.radiance.len;
    const old_noise_sigma = product.noise_sigma;
    const old_radiance_noise_sigma = product.radiance_noise_sigma;
    const radiance_sigma_shared = old_radiance_noise_sigma.len != 0 and
        old_radiance_noise_sigma.ptr == old_noise_sigma.ptr;

    var replacement_noise_sigma: ?[]f64 = null;
    errdefer if (replacement_noise_sigma) |buffer| allocator.free(buffer);

    var next_noise_sigma = old_noise_sigma;
    if (old_noise_sigma.len != sample_count) {
        const buffer = try allocator.alloc(f64, sample_count);
        @memcpy(buffer, sigma);
        replacement_noise_sigma = buffer;
        next_noise_sigma = buffer;
    } else {
        @memcpy(next_noise_sigma, sigma);
    }

    const replace_radiance_sigma = old_radiance_noise_sigma.len == 0 or
        radiance_sigma_shared or
        old_radiance_noise_sigma.len != sample_count;
    if (!replace_radiance_sigma) {
        @memcpy(old_radiance_noise_sigma, sigma);
    }

    product.noise_sigma = next_noise_sigma;
    product.radiance_noise_sigma = if (replace_radiance_sigma)
        next_noise_sigma
    else
        old_radiance_noise_sigma;

    if (replacement_noise_sigma != null and old_noise_sigma.len != 0) {
        allocator.free(old_noise_sigma);
    }
    if (replace_radiance_sigma and !radiance_sigma_shared and old_radiance_noise_sigma.len != 0) {
        allocator.free(old_radiance_noise_sigma);
    }

    if (product.reflectance_noise_sigma.len == product.radiance.len) {
        for (product.reflectance, product.radiance, product.reflectance_noise_sigma, sigma) |reflectance, radiance, *reflectance_sigma, radiance_sigma| {
            const radiance_term = if (radiance > 0.0)
                reflectance * (radiance_sigma / @max(radiance, 1.0e-12))
            else
                0.0;
            reflectance_sigma.* = std.math.sqrt(reflectance_sigma.* * reflectance_sigma.* + radiance_term * radiance_term);
        }
    }
}

fn reflectanceForSample(scene: *const SceneModel.Scene, radiance: f64, irradiance: f64) f64 {
    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
    return (radiance * std.math.pi) / @max(irradiance * solar_cosine, 1.0e-9);
}

fn hasPositiveSigma(sigma: []const f64) bool {
    for (sigma) |value| {
        if (std.math.isFinite(value) and value > 0.0) return true;
    }
    return false;
}

fn recomputeMeasurementSummary(product: *MeasurementSpaceProduct) void {
    if (product.radiance.len == 0) return;

    var radiance_sum: f64 = 0.0;
    var irradiance_sum: f64 = 0.0;
    var reflectance_sum: f64 = 0.0;
    var noise_sum: f64 = 0.0;
    for (0..product.radiance.len) |index| {
        radiance_sum += product.radiance[index];
        irradiance_sum += product.irradiance[index];
        reflectance_sum += product.reflectance[index];
        if (index < product.noise_sigma.len) noise_sum += product.noise_sigma[index];
    }

    const sample_count = @as(f64, @floatFromInt(product.radiance.len));
    product.summary.sample_count = @intCast(product.radiance.len);
    product.summary.wavelength_start_nm = product.wavelengths[0];
    product.summary.wavelength_end_nm = product.wavelengths[product.wavelengths.len - 1];
    product.summary.mean_radiance = radiance_sum / sample_count;
    product.summary.mean_irradiance = irradiance_sum / sample_count;
    product.summary.mean_reflectance = reflectance_sum / sample_count;
    product.summary.mean_noise_sigma = noise_sum / sample_count;
}

const IngestReference = struct {
    ingest_name: []const u8,
    output_name: []const u8,
};

fn buildIngestMeasurementProduct(
    allocator: Allocator,
    experiment: *ResolvedExperiment,
    request: *Request,
    reference: []const u8,
) !*MeasurementSpaceProduct {
    const ingest_reference = try parseIngestReference(reference);
    const ingest = experiment.findIngest(ingest_reference.ingest_name) orelse return error.MissingMeasurementBinding;
    if (!std.mem.eql(u8, ingest_reference.output_name, "radiance")) return error.UnsupportedMeasurementBinding;

    const product = try buildRadianceObservationProduct(allocator, &request.scene, ingest);
    if (request.scene.observation_model.sampling == .measured_channels) {
        request.scene.spectral_grid.start_nm = product.wavelengths[0];
        request.scene.spectral_grid.end_nm = product.wavelengths[product.wavelengths.len - 1];
        request.scene.spectral_grid.sample_count = @intCast(product.wavelengths.len);
        request.scene.observation_model.measured_wavelengths_nm = product.wavelengths;
        request.scene.observation_model.owns_measured_wavelengths = false;
    }
    if (request.scene.observation_model.reference_radiance.len == 0 or
        request.scene.observation_model.reference_radiance.len != product.radiance.len)
    {
        request.scene.observation_model.reference_radiance = product.radiance;
        request.scene.observation_model.owns_reference_radiance = false;
    }
    switch (request.scene.observation_model.noise_model) {
        .snr_from_input, .s5p_operational => request.scene.observation_model.ingested_noise_sigma = product.noise_sigma,
        .none, .shot_noise, .lab_operational => {},
    }
    if (!request.scene.observation_model.operational_solar_spectrum.enabled() and
        ingest.loaded_spectra.channelCount(.irradiance) > 0)
    {
        request.scene.observation_model.operational_solar_spectrum = .{
            .wavelengths_nm = product.wavelengths,
            .irradiance = product.irradiance,
        };
    }
    return product;
}

fn buildRadianceObservationProduct(
    allocator: Allocator,
    scene: *const @import("../../model/Scene.zig").Scene,
    ingest: Ingest,
) !*MeasurementSpaceProduct {
    const wavelengths = try ingest.loaded_spectra.wavelengthsForKind(allocator, .radiance);
    errdefer if (wavelengths.len != 0) allocator.free(wavelengths);
    if (wavelengths.len == 0) return error.MissingMeasurementBinding;

    const radiance = try spectral_runtime.channelValuesForKind(allocator, ingest.loaded_spectra, .radiance);
    errdefer if (radiance.len != 0) allocator.free(radiance);
    const noise_sigma = try ingest.loaded_spectra.noiseSigmaForKind(allocator, .radiance);
    errdefer if (noise_sigma.len != 0) allocator.free(noise_sigma);
    const irradiance = try alignedIrradianceForObservation(allocator, scene, ingest, wavelengths);
    errdefer if (irradiance.len != 0) allocator.free(irradiance);
    const reflectance = try allocator.alloc(f64, wavelengths.len);
    errdefer if (reflectance.len != 0) allocator.free(reflectance);

    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
    var radiance_sum: f64 = 0.0;
    var irradiance_sum: f64 = 0.0;
    var reflectance_sum: f64 = 0.0;
    var sigma_sum: f64 = 0.0;
    for (0..wavelengths.len) |index| {
        reflectance[index] = if (irradiance[index] > 0.0)
            (radiance[index] * std.math.pi) / @max(irradiance[index] * solar_cosine, 1.0e-9)
        else
            0.0;
        radiance_sum += radiance[index];
        irradiance_sum += irradiance[index];
        reflectance_sum += reflectance[index];
        if (index < noise_sigma.len) sigma_sum += noise_sigma[index];
    }

    const product = try allocator.create(MeasurementSpaceProduct);
    errdefer allocator.destroy(product);
    product.* = .{
        .summary = .{
            .sample_count = @intCast(wavelengths.len),
            .wavelength_start_nm = wavelengths[0],
            .wavelength_end_nm = wavelengths[wavelengths.len - 1],
            .mean_radiance = radiance_sum / @as(f64, @floatFromInt(wavelengths.len)),
            .mean_irradiance = irradiance_sum / @as(f64, @floatFromInt(wavelengths.len)),
            .mean_reflectance = reflectance_sum / @as(f64, @floatFromInt(wavelengths.len)),
            .mean_noise_sigma = sigma_sum / @as(f64, @floatFromInt(wavelengths.len)),
            .mean_jacobian = null,
        },
        .wavelengths = @constCast(wavelengths),
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .noise_sigma = @constCast(noise_sigma),
        .jacobian = null,
        .effective_air_mass_factor = 0.0,
        .effective_single_scatter_albedo = 0.0,
        .effective_temperature_k = 0.0,
        .effective_pressure_hpa = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.0,
        .cloud_optical_depth = 0.0,
        .total_optical_depth = 0.0,
        .depolarization_factor = 0.0,
        .d_optical_depth_d_temperature = 0.0,
    };
    return product;
}

fn alignedIrradianceForObservation(
    allocator: Allocator,
    scene: *const @import("../../model/Scene.zig").Scene,
    ingest: Ingest,
    wavelengths: []const f64,
) ![]f64 {
    if (scene.observation_model.operational_solar_spectrum.enabled()) {
        return spectral_runtime.correctedIrradianceOnWavelengthGrid(
            allocator,
            ingest.loaded_spectra,
            .irradiance,
            &scene.observation_model.operational_solar_spectrum,
            wavelengths,
        ) catch |err| switch (err) {
            spectral_runtime.ParseError.InvalidLine => core_errors.Error.InvalidRequest,
            else => err,
        };
    }
    if (ingest.loaded_spectra.channelCount(.irradiance) > 0) {
        var solar = try ingest.loaded_spectra.solarSpectrumForKind(allocator, .irradiance);
        defer solar.deinitOwned(allocator);
        return spectral_runtime.correctedIrradianceOnWavelengthGrid(
            allocator,
            ingest.loaded_spectra,
            .irradiance,
            &solar,
            wavelengths,
        ) catch |err| switch (err) {
            spectral_runtime.ParseError.InvalidLine => core_errors.Error.InvalidRequest,
            else => err,
        };
    }

    const zeros = try allocator.alloc(f64, wavelengths.len);
    @memset(zeros, 0.0);
    return zeros;
}

fn parseIngestReference(reference: []const u8) !IngestReference {
    const dot_index = std.mem.indexOfScalar(u8, reference, '.') orelse return error.MissingMeasurementBinding;
    return .{
        .ingest_name = reference[0..dot_index],
        .output_name = reference[dot_index + 1 ..],
    };
}

fn exportViewForTarget(result: *const Result, target: ProductRef) !export_spec.ExportView {
    var view = export_spec.ExportView.fromResult(result);

    switch (target.kind) {
        .measurement_space => {
            if (view.measurement_space_product == null) return error.UnsupportedOutputTarget;
            view.retrieval = null;
            view.retrieval_state_vector = null;
            view.retrieval_fitted_measurement = null;
            view.retrieval_averaging_kernel = null;
            view.retrieval_jacobian = null;
            view.retrieval_posterior_covariance = null;
        },
        .state_vector => {
            if (view.retrieval_state_vector == null) return error.UnsupportedOutputTarget;
            view.measurement_space_product = null;
            view.retrieval_fitted_measurement = null;
            view.retrieval_averaging_kernel = null;
            view.retrieval_jacobian = null;
            view.retrieval_posterior_covariance = null;
        },
        .fitted_measurement => {
            if (view.retrieval_fitted_measurement == null) return error.UnsupportedOutputTarget;
            view.measurement_space_product = null;
            view.retrieval_state_vector = null;
            view.retrieval_averaging_kernel = null;
            view.retrieval_jacobian = null;
            view.retrieval_posterior_covariance = null;
        },
        .averaging_kernel => {
            if (view.retrieval_averaging_kernel == null) return error.UnsupportedOutputTarget;
            view.measurement_space_product = null;
            view.retrieval_state_vector = null;
            view.retrieval_fitted_measurement = null;
            view.retrieval_jacobian = null;
            view.retrieval_posterior_covariance = null;
        },
        .jacobian => {
            if (view.retrieval_jacobian == null) return error.UnsupportedOutputTarget;
            view.measurement_space_product = null;
            view.retrieval_state_vector = null;
            view.retrieval_fitted_measurement = null;
            view.retrieval_averaging_kernel = null;
            view.retrieval_posterior_covariance = null;
        },
        .posterior_covariance => {
            if (view.retrieval_posterior_covariance == null) return error.UnsupportedOutputTarget;
            view.measurement_space_product = null;
            view.retrieval_state_vector = null;
            view.retrieval_fitted_measurement = null;
            view.retrieval_averaging_kernel = null;
            view.retrieval_jacobian = null;
        },
        .result => {},
        .diagnostics => return error.UnsupportedOutputTarget,
    }

    return view;
}

fn exporterPluginId(format: ExportFormat) []const u8 {
    return switch (format) {
        .netcdf_cf => "builtin.netcdf_cf",
        .zarr => "builtin.zarr",
    };
}

/// Reject configs containing vendor controls that are parsed from YAML but
/// not consumed by any runtime code path. This prevents silent
/// parsed-but-ignored behavior and enforces the WP-01 parity invariant.
///
/// Current checks:
/// - vendor_compat.simulation_method: DISMAS is not supported.
/// - vendor_compat.retrieval_method: DOAS, classic_DOAS, and DOMINO_NO2
///   are not yet supported; only OE is fully implemented.
/// - Spectral response shapes must map to a known builtin line shape.
///
/// This gate is expanded as later WPs add vendor sections to the YAML schema.
fn validateVendorControls(experiment: *const ResolvedExperiment) Error!void {
    const log = std.log.scoped(.execution);
    const BuiltinLineShapeKind = @import("../../model/instrument/line_shape.zig").BuiltinLineShapeKind;
    const stages = [_]?*const Stage{ experiment.simulation, experiment.retrieval };
    for (stages) |maybe_stage| {
        const stage = maybe_stage orelse continue;

        // A spectral response shape is only honored if it maps to a known
        // builtin line shape. Arbitrary/external shapes that cannot be
        // consumed must be rejected.
        if (stage.spectral_response_shape.len > 0) {
            _ = BuiltinLineShapeKind.parse(stage.spectral_response_shape) catch {
                log.err("UnsupportedVendorControl: spectral_response_shape '{s}' does not map to a known builtin line shape", .{stage.spectral_response_shape});
                return error.UnsupportedVendorControl;
            };
        }

        // If vendor_compat is present, validate that its controls are supportable.
        if (stage.vendor_compat) |compat| {
            // DISMAS simulation method is not supported.
            if (compat.simulation_method) |method| {
                if (method == .dismas) {
                    log.err("UnsupportedVendorControl: vendor_compat.simulation_method = dismas is not supported", .{});
                    return error.UnsupportedVendorControl;
                }
            }
            if (compat.simulation_only) {
                log.err("UnsupportedVendorControl: vendor_compat.simulation_only is parsed but not yet honored", .{});
                return error.UnsupportedVendorControl;
            }

            // DOAS-family and DOMINO retrieval methods are not yet supported;
            // only OE is fully implemented. The vendor verifier
            // (verifyConfigFileModule.f90) validates method legality
            // per-section; this gate rejects methods the Zig runtime cannot
            // honor to prevent silent parsed-but-ignored behavior.
            if (compat.retrieval_method) |method| {
                switch (method) {
                    .doas, .classic_doas, .domino_no2 => {
                        log.err("UnsupportedVendorControl: vendor_compat.retrieval_method = {s} is not yet supported", .{@tagName(method)});
                        return error.UnsupportedVendorControl;
                    },
                    .oe, .dismas => {},
                }
            }
        }
        if (stage.general) |general| {
            if (general.simulation_only) {
                log.err("UnsupportedVendorControl: general.simulation_only is parsed but not yet honored", .{});
                return error.UnsupportedVendorControl;
            }
        }
    }
}

test "storeFallbackRadianceSigma preserves buffers when replacement allocation fails" {
    const allocator = std.testing.allocator;

    var product = MeasurementSpaceProduct{
        .summary = .{
            .sample_count = 2,
            .wavelength_start_nm = 760.0,
            .wavelength_end_nm = 760.1,
            .mean_radiance = 1.5,
            .mean_irradiance = 3.5,
            .mean_reflectance = 5.5,
            .mean_noise_sigma = 0.1,
        },
        .wavelengths = try allocator.dupe(f64, &[_]f64{ 760.0, 760.1 }),
        .radiance = try allocator.dupe(f64, &[_]f64{ 1.0, 2.0 }),
        .irradiance = try allocator.dupe(f64, &[_]f64{ 3.0, 4.0 }),
        .reflectance = try allocator.dupe(f64, &[_]f64{ 5.0, 6.0 }),
        .noise_sigma = try allocator.dupe(f64, &[_]f64{0.1}),
        .radiance_noise_sigma = &.{},
        .effective_air_mass_factor = 0.0,
        .effective_single_scatter_albedo = 0.0,
        .effective_temperature_k = 0.0,
        .effective_pressure_hpa = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.0,
        .cloud_optical_depth = 0.0,
        .total_optical_depth = 0.0,
        .depolarization_factor = 0.0,
        .d_optical_depth_d_temperature = 0.0,
    };
    product.radiance_noise_sigma = product.noise_sigma;
    defer product.deinit(allocator);

    const original_noise_ptr = product.noise_sigma.ptr;

    var failing = std.testing.FailingAllocator.init(allocator, .{
        .fail_index = 0,
    });
    try std.testing.expectError(
        error.OutOfMemory,
        storeFallbackRadianceSigma(failing.allocator(), &product, &[_]f64{ 0.2, 0.3 }),
    );

    try std.testing.expectEqual(@as(usize, 1), product.noise_sigma.len);
    try std.testing.expectEqual(original_noise_ptr, product.noise_sigma.ptr);
    try std.testing.expectEqual(@as(usize, 1), product.radiance_noise_sigma.len);
    try std.testing.expectEqual(original_noise_ptr, product.radiance_noise_sigma.ptr);
    try std.testing.expectEqual(@as(f64, 0.1), product.noise_sigma[0]);
}

test "applyNoiseToStageMeasurementProduct perturbs only enabled channels" {
    const allocator = std.testing.allocator;
    const wavelengths = [_]f64{ 760.0, 760.1 };
    const radiance = [_]f64{ 10.0, 12.0 };
    const irradiance = [_]f64{ 20.0, 24.0 };
    const reflectance = [_]f64{ 1.0, 1.0 };
    const zero_sigma = [_]f64{ 0.0, 0.0 };
    const irradiance_sigma = [_]f64{ 0.25, 0.5 };

    var result = try Result.init(allocator, 1, "unit", "noise-channel-split", .{});
    defer result.deinit(allocator);
    result.attachMeasurementSpaceProduct(.{
        .summary = .{
            .sample_count = wavelengths.len,
            .wavelength_start_nm = wavelengths[0],
            .wavelength_end_nm = wavelengths[wavelengths.len - 1],
            .mean_radiance = 11.0,
            .mean_irradiance = 22.0,
            .mean_reflectance = 1.0,
            .mean_noise_sigma = 0.0,
        },
        .wavelengths = try allocator.dupe(f64, &wavelengths),
        .radiance = try allocator.dupe(f64, &radiance),
        .irradiance = try allocator.dupe(f64, &irradiance),
        .reflectance = try allocator.dupe(f64, &reflectance),
        .noise_sigma = try allocator.dupe(f64, &zero_sigma),
        .radiance_noise_sigma = &.{},
        .irradiance_noise_sigma = try allocator.dupe(f64, &irradiance_sigma),
        .effective_air_mass_factor = 0.0,
        .effective_single_scatter_albedo = 0.0,
        .effective_temperature_k = 0.0,
        .effective_pressure_hpa = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.0,
        .cloud_optical_depth = 0.0,
        .total_optical_depth = 0.0,
        .depolarization_factor = 0.0,
        .d_optical_depth_d_temperature = 0.0,
    });
    result.measurement_space_product.?.radiance_noise_sigma = result.measurement_space_product.?.noise_sigma;

    const scene: SceneModel.Scene = .{
        .observation_model = .{
            .noise_model = .none,
            .measurement_pipeline = .{
                .radiance = .{
                    .explicit = true,
                    .noise = .{
                        .explicit = true,
                        .enabled = false,
                    },
                },
                .irradiance = .{
                    .explicit = true,
                    .noise = .{
                        .explicit = true,
                        .enabled = true,
                        .model = .shot_noise,
                    },
                },
            },
        },
    };

    var expected_prng = std.Random.DefaultPrng.init(1234);
    const expected_random = expected_prng.random();
    var expected_irradiance = irradiance;
    var expected_reflectance = reflectance;
    for (0..expected_irradiance.len) |index| {
        const perturbed = expected_irradiance[index] + expected_random.floatNorm(f64) * irradiance_sigma[index];
        expected_irradiance[index] = @max(perturbed, 0.0);
        expected_reflectance[index] = reflectanceForSample(&scene, radiance[index], expected_irradiance[index]);
    }

    try applyNoiseToStageMeasurementProduct(allocator, &result, &scene, 1234);

    const product = result.measurement_space_product.?;
    try std.testing.expectEqualSlices(f64, &radiance, product.radiance);
    for (expected_irradiance, product.irradiance) |expected, actual| {
        try std.testing.expectApproxEqRel(expected, actual, 1.0e-12);
    }
    for (expected_reflectance, product.reflectance) |expected, actual| {
        try std.testing.expectApproxEqRel(expected, actual, 1.0e-12);
    }
}
