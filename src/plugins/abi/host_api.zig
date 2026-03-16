const std = @import("std");
const Abi = @import("abi_types.zig");

pub const LogLevel = enum(i32) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};

pub const LoggerFn = *const fn (user_data: ?*anyopaque, level: LogLevel, message: []const u8) void;

const HostLogContext = struct {
    logger: LoggerFn,
    logger_user_data: ?*anyopaque,
};

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
