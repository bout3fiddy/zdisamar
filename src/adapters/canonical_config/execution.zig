const std = @import("std");
const core_errors = @import("../../core/errors.zig");
const Engine = @import("../../core/Engine.zig").Engine;
const Request = @import("../../core/Request.zig").Request;
const Result = @import("../../core/Result.zig").Result;
const export_spec = @import("../exporters/spec.zig");
const exporters = @import("../exporters/writer.zig");
const DocumentModule = @import("Document.zig");
const ResolvedExperiment = DocumentModule.ResolvedExperiment;
const Stage = DocumentModule.Stage;
const StageKind = DocumentModule.StageKind;
const Product = DocumentModule.Product;
const ProductKind = DocumentModule.ProductKind;
const OutputSpec = DocumentModule.OutputSpec;
const ExportFormat = @import("../exporters/format.zig").ExportFormat;
const Allocator = std.mem.Allocator;

pub const Error =
    core_errors.Error ||
    exporters.Error ||
    DocumentModule.Error ||
    error{
        DuplicateProduct,
        MissingOutputProduct,
        MissingMeasurementBinding,
        UnsupportedMeasurementBinding,
        UnsupportedOutputTarget,
    };

pub const StageExecution = struct {
    kind: StageKind,
    stage: Stage,
    product_names: []const []const u8,
    diagnostics: @import("../../core/diagnostics.zig").DiagnosticsSpec,
};

pub const ProductRef = struct {
    name: []const u8,
    kind: ProductKind,
    stage_index: usize,
    observable: []const u8 = "",
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

    pub fn deinit(self: *ExecutionOutcome) void {
        for (self.stage_outcomes) |*stage_outcome| {
            stage_outcome.result.deinit(self.allocator);
        }
        if (self.stage_outcomes.len != 0) self.allocator.free(self.stage_outcomes);
        if (self.outputs.len != 0) self.allocator.free(self.outputs);
        self.* = undefined;
    }

    pub fn stageResult(self: *const ExecutionOutcome, kind: StageKind) ?*const Result {
        for (self.stage_outcomes) |*stage_outcome| {
            if (stage_outcome.kind == kind) return &stage_outcome.result;
        }
        return null;
    }
};

pub const ExecutionProgram = struct {
    allocator: Allocator,
    experiment: ResolvedExperiment,
    stages: []StageExecution,
    products: []ProductRef,
    outputs: []ExportJob,

    pub fn init(allocator: Allocator, experiment: ResolvedExperiment) !ExecutionProgram {
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

        var stage_index: usize = 0;
        var initialized_stage_count: usize = 0;
        var product_index: usize = 0;
        errdefer {
            for (stages[0..initialized_stage_count]) |stage_execution| {
                if (stage_execution.product_names.len != 0) allocator.free(stage_execution.product_names);
            }
        }

        if (experiment.simulation) |stage| {
            const product_names = try collectProductNames(allocator, stage.products);
            stages[stage_index] = .{
                .kind = .simulation,
                .stage = stage,
                .product_names = product_names,
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
            var diagnostics = stage.diagnostics;
            if (hasJacobianProduct(stage.products)) diagnostics.jacobians = true;
            const product_names = try collectProductNames(allocator, stage.products);
            stages[stage_index] = .{
                .kind = .retrieval,
                .stage = stage,
                .product_names = product_names,
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

    pub fn deinit(self: *ExecutionProgram) void {
        for (self.stages) |stage| {
            if (stage.product_names.len != 0) self.allocator.free(stage.product_names);
        }
        if (self.stages.len != 0) self.allocator.free(self.stages);
        if (self.products.len != 0) self.allocator.free(self.products);
        if (self.outputs.len != 0) self.allocator.free(self.outputs);
        self.experiment.deinit();
        self.* = undefined;
    }

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
            request.inverse_problem = stage_execution.stage.inverse;
            request.requested_products = stage_execution.product_names;
            request.expected_derivative_mode = stage_execution.stage.plan.scene_blueprint.derivative_mode;
            request.diagnostics = stage_execution.diagnostics;

            if (stage_execution.kind == .retrieval and stage_execution.stage.inverse != null) {
                const source = stage_execution.stage.inverse.?.measurements.source;
                switch (source.kind) {
                    .none, .external_observation => {},
                    .stage_product => {
                        const source_ref = findProduct(self.products, source.name) orelse return error.MissingMeasurementBinding;
                        if (source_ref.kind != .measurement_space) return error.UnsupportedMeasurementBinding;
                        if (source_ref.stage_index >= executed_stage_count) return error.MissingMeasurementBinding;
                        const source_result = &stage_outcomes[source_ref.stage_index].result;
                        if (source_result.measurement_space_product) |*source_product| {
                            request.measurement_binding = .{
                                .source_name = source_ref.name,
                                .observable = if (source_ref.observable.len != 0) source_ref.observable else stage_execution.stage.inverse.?.measurements.observable,
                                .product = source_product,
                            };
                        } else {
                            return error.MissingMeasurementBinding;
                        }
                    },
                    .asset, .ingest, .bundle_default, .atmosphere => return error.UnsupportedMeasurementBinding,
                }
            }

            if (index != 0) workspace.reset();

            stage_outcomes[index] = .{
                .kind = stage_execution.kind,
                .result = try engine.execute(&plan, &workspace, request),
            };
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

pub fn compileResolved(allocator: Allocator, experiment: ResolvedExperiment) !ExecutionProgram {
    return ExecutionProgram.init(allocator, experiment);
}

pub fn resolveCompileAndExecute(
    allocator: Allocator,
    engine: *Engine,
    path: []const u8,
) !struct { program: ExecutionProgram, outcome: ExecutionOutcome } {
    var experiment = try DocumentModule.resolveFile(allocator, path);
    errdefer experiment.deinit();

    var program = try compileResolved(allocator, experiment);
    experiment = undefined;
    errdefer program.deinit();

    const outcome = try program.execute(allocator, engine);
    return .{
        .program = program,
        .outcome = outcome,
    };
}

fn collectProductNames(allocator: Allocator, products: []const Product) ![]const []const u8 {
    if (products.len == 0) return &[_][]const u8{};
    const names = try allocator.alloc([]const u8, products.len);
    for (products, 0..) |product, index| names[index] = product.name;
    return names;
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
        },
        .state_vector => {
            if (view.retrieval_state_vector == null) return error.UnsupportedOutputTarget;
            view.measurement_space_product = null;
            view.retrieval_fitted_measurement = null;
            view.retrieval_averaging_kernel = null;
            view.retrieval_jacobian = null;
        },
        .fitted_measurement => {
            if (view.retrieval_fitted_measurement == null) return error.UnsupportedOutputTarget;
            view.measurement_space_product = null;
            view.retrieval_state_vector = null;
            view.retrieval_averaging_kernel = null;
            view.retrieval_jacobian = null;
        },
        .averaging_kernel => {
            if (view.retrieval_averaging_kernel == null) return error.UnsupportedOutputTarget;
            view.measurement_space_product = null;
            view.retrieval_state_vector = null;
            view.retrieval_fitted_measurement = null;
            view.retrieval_jacobian = null;
        },
        .jacobian => {
            if (view.retrieval_jacobian == null) return error.UnsupportedOutputTarget;
            view.measurement_space_product = null;
            view.retrieval_state_vector = null;
            view.retrieval_fitted_measurement = null;
            view.retrieval_averaging_kernel = null;
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
