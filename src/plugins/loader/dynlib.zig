const std = @import("std");

pub const SymbolEntry = struct {
    name: [:0]const u8,
    address: *const anyopaque,
};

pub const Library = struct {
    backend: Backend,

    const Backend = union(enum) {
        dynamic: std.DynLib,
        static_symbols: []const SymbolEntry,
    };

    pub fn open(path: []const u8) std.DynLib.Error!Library {
        return .{
            .backend = .{
                .dynamic = try std.DynLib.open(path),
            },
        };
    }

    pub fn fromStaticSymbols(entries: []const SymbolEntry) Library {
        return .{
            .backend = .{
                .static_symbols = entries,
            },
        };
    }

    pub fn close(self: *Library) void {
        switch (self.backend) {
            .dynamic => |*dynamic| dynamic.close(),
            .static_symbols => {},
        }
        self.* = undefined;
    }

    pub fn lookup(self: *Library, comptime T: type, symbol: [:0]const u8) ?T {
        return switch (self.backend) {
            .dynamic => |*dynamic| dynamic.lookup(T, symbol),
            .static_symbols => |entries| lookupStatic(T, entries, symbol),
        };
    }
};

fn lookupStatic(comptime T: type, entries: []const SymbolEntry, symbol: [:0]const u8) ?T {
    comptime {
        if (@typeInfo(T) != .pointer) {
            @compileError("DynLib mock lookup requires a pointer type");
        }
    }

    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, symbol)) {
            return @as(T, @ptrCast(@alignCast(entry.address)));
        }
    }
    return null;
}

test "static symbol backend resolves typed function pointers" {
    const Fixture = struct {
        fn callback() callconv(.c) i32 {
            return 42;
        }
    };

    const symbols = [_]SymbolEntry{
        .{
            .name = "fixture_callback",
            .address = @ptrCast(&Fixture.callback),
        },
    };

    var library = Library.fromStaticSymbols(&symbols);
    defer library.close();

    const callback = library.lookup(*const fn () callconv(.c) i32, "fixture_callback") orelse {
        return error.TestUnexpectedResult;
    };
    try std.testing.expectEqual(@as(i32, 42), callback());
    try std.testing.expect(library.lookup(*const fn () callconv(.c) i32, "missing_callback") == null);
}
