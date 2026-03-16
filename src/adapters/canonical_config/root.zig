pub const yaml = @import("yaml.zig");
pub const Error = @import("Document.zig").Error;
pub const Document = @import("Document.zig").Document;
pub const ResolvedExperiment = @import("Document.zig").ResolvedExperiment;
pub const resolveFile = @import("Document.zig").resolveFile;
pub const execution = @import("execution.zig");
pub const ExecutionProgram = execution.ExecutionProgram;
pub const ExecutionOutcome = execution.ExecutionOutcome;
pub const compileResolved = execution.compileResolved;
pub const resolveCompileAndExecute = execution.resolveCompileAndExecute;

test "canonical config package exposes parser and resolver" {
    _ = @import("yaml.zig");
    _ = @import("Document.zig");
    _ = @import("execution.zig");
}
