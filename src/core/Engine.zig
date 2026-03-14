const std = @import("std");

const Catalog = @import("Catalog.zig").Catalog;
const PlanModule = @import("Plan.zig");
const Plan = PlanModule.Plan;
const Request = @import("Request.zig").Request;
const Result = @import("Result.zig").Result;
const Workspace = @import("Workspace.zig").Workspace;
const errors = @import("errors.zig");
const CapabilityRegistry = @import("../plugins/registry/CapabilityRegistry.zig").CapabilityRegistry;

pub const EngineOptions = struct {
    abi_version: u32 = 1,
    allow_native_plugins: bool = false,
    max_prepared_plans: usize = 64,
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    options: EngineOptions,
    catalog: Catalog = .{},
    registry: CapabilityRegistry = .{},
    next_plan_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator, options: EngineOptions) Engine {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn deinit(self: *Engine) void {
        self.registry.deinit(self.allocator);
        self.catalog.deinit(self.allocator);
    }

    pub fn bootstrapBuiltinCatalog(self: *Engine) !void {
        try self.catalog.bootstrapBuiltin(self.allocator);
        try self.registry.bootstrapBuiltin(self.allocator);
    }

    pub fn preparePlan(self: *Engine, template: PlanModule.Template) !Plan {
        if (!self.catalog.bootstrapped) {
            return errors.Error.CatalogNotBootstrapped;
        }

        const plan = Plan.init(self.next_plan_id, template);
        self.next_plan_id += 1;
        return plan;
    }

    pub fn createWorkspace(self: *Engine, label: []const u8) Workspace {
        _ = self;
        return Workspace.init(label);
    }

    pub fn execute(self: *Engine, plan: *const Plan, workspace: *Workspace, request: Request) !Result {
        _ = self;

        if (request.scene.id.len == 0) {
            return errors.Error.MissingScene;
        }

        return Result.init(
            plan.id,
            workspace.label,
            request.scene.id,
            plan.template.model_family,
            @tagName(plan.template.solver_mode),
        );
    }
};
