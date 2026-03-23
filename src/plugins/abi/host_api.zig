//! Purpose:
//!   Adapt typed host logging into the ABI-facing callback table.
//!
//! Physics:
//!   No physics is introduced here; the file moves log messages across the
//!   plugin ABI boundary.
//!
//! Vendor:
//!   `host_api`
//!
//! Design:
//!   Keep a typed logger context in front of the ABI struct so the host can
//!   supply closures without exposing them to the plugin side.
//!
//! Invariants:
//!   The ABI struct must always advertise the current host API version and
//!   valid user-data pointer when logging is enabled.
//!
//! Validation:
//!   Covered by the host API tests in this file.
const std = @import("std");
const Abi = @import("abi_types.zig");

/// Log levels visible to native plugins.
pub const LogLevel = enum(i32) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};

/// Function signature used by typed host log sinks.
pub const LoggerFn = *const fn (user_data: ?*anyopaque, level: LogLevel, message: []const u8) void;

const HostLogContext = struct {
    logger: LoggerFn,
    logger_user_data: ?*anyopaque,
};

/// Host-side wrapper around the ABI callback table.
pub const HostApiRef = struct {
    context: HostLogContext = .{
        .logger = noopLogger,
        .logger_user_data = null,
    },
    api: Abi.HostApi = .{
        .struct_size = @sizeOf(Abi.HostApi),
        .host_api_version = Abi.host_api_version,
    },

    pub fn init(self: *HostApiRef, logger: LoggerFn, logger_user_data: ?*anyopaque) void {
        self.context = .{
            .logger = logger,
            .logger_user_data = logger_user_data,
        };
        self.api = .{
            .struct_size = @sizeOf(Abi.HostApi),
            .host_api_version = Abi.host_api_version,
            .log_message = cLogMessage,
            .user_data = &self.context,
        };
    }

    pub fn initNoop(self: *HostApiRef) void {
        self.context = .{
            .logger = noopLogger,
            .logger_user_data = null,
        };
        self.api = noop_host_api;
    }

    pub fn asAbi(self: *const HostApiRef) *const Abi.HostApi {
        return &self.api;
    }
};

/// No-op ABI host API used when logging is disabled.
pub const noop_host_api: Abi.HostApi = .{
    .struct_size = @sizeOf(Abi.HostApi),
    .host_api_version = Abi.host_api_version,
    .log_message = null,
    .user_data = null,
};

fn noopLogger(_: ?*anyopaque, _: LogLevel, _: []const u8) void {}

fn cLogMessage(level: i32, message: ?[*:0]const u8, user_data: ?*anyopaque) callconv(.c) void {
    const context_ptr = user_data orelse return;
    const context: *HostLogContext = @ptrCast(@alignCast(context_ptr));
    const text = if (message) |value| std.mem.span(value) else "";
    // DECISION:
    //   Map unexpected integers to `.err` so the host log sink still receives a
    //   typed severity even when a plugin misbehaves.
    const mapped_level = std.meta.intToEnum(LogLevel, level) catch .err;
    context.logger(context.logger_user_data, mapped_level, text);
}

test "host api routes C callback logging through typed host logger" {
    const Sink = struct {
        call_count: usize = 0,
        last_level: LogLevel = .debug,
        last_message: [64]u8 = [_]u8{0} ** 64,
        last_message_len: usize = 0,
    };

    const Callbacks = struct {
        fn logger(user_data: ?*anyopaque, level: LogLevel, message: []const u8) void {
            const sink_ptr = user_data orelse return;
            const sink: *Sink = @ptrCast(@alignCast(sink_ptr));
            sink.call_count += 1;
            sink.last_level = level;
            const length = @min(message.len, sink.last_message.len);
            @memcpy(sink.last_message[0..length], message[0..length]);
            sink.last_message_len = length;
        }
    };

    var sink = Sink{};
    var host_api_ref: HostApiRef = .{};
    host_api_ref.init(Callbacks.logger, &sink);
    try Abi.validateHostApi(host_api_ref.asAbi());

    const log_fn = host_api_ref.api.log_message orelse return error.TestUnexpectedResult;
    log_fn(@intFromEnum(LogLevel.warn), "native plugin loaded", host_api_ref.api.user_data);

    try std.testing.expectEqual(@as(usize, 1), sink.call_count);
    try std.testing.expectEqual(LogLevel.warn, sink.last_level);
    try std.testing.expectEqualStrings("native plugin loaded", sink.last_message[0..sink.last_message_len]);
}
