//! Purpose:
//!   Open native plugin libraries or provide an in-memory symbol table for
//!   tests and builtin fallbacks.
//!
//! Physics:
//!   No physics is introduced here; this is pure loading and symbol lookup
//!   infrastructure for the plugin runtime.
//!
//! Vendor:
//!   `dynlib`
//!
//! Design:
//!   Wrap `std.DynLib` behind a small union so the runtime can swap between
//!   process-local symbol fixtures and real dynamic loading.
//!
//! Invariants:
//!   The backend must be closed exactly once, and static symbol lookup must
//!   only return pointer-typed entries.
//!
//! Validation:
//!   Covered by the static symbol backend test in this file.
const std = @import("std");

/// Name/address pair for a static symbol backend.
pub const SymbolEntry = struct {
    name: [:0]const u8,
    address: *const anyopaque,
};

/// Library handle that may be backed by a dynamic library or static symbols.
pub const Library = struct {
    backend: Backend,

    const Backend = union(enum) {
        dynamic: std.DynLib,
        static_symbols: []const SymbolEntry,
    };

    /// Purpose:
    ///   Open a dynamic library from a filesystem path.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `dynlib::open`
    ///
    /// Inputs:
    ///   `path` identifies the library to load.
    ///
    /// Outputs:
    ///   Returns a library wrapper around the opened dynamic library.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The path exists and the loader can open it.
    ///
    /// Decisions:
    ///   Expose the dynamic loader directly so runtime policy can decide whether
    ///   the path is permitted.
    ///
    /// Validation:
    ///   Covered indirectly by resolver tests.
    pub fn open(path: []const u8) std.DynLib.Error!Library {
        return .{
            .backend = .{
                .dynamic = try std.DynLib.open(path),
            },
        };
    }

    /// Purpose:
    ///   Create a library view backed by an in-memory symbol table.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `dynlib::fromStaticSymbols`
    ///
    /// Inputs:
    ///   `entries` contains the mock or builtin symbol table.
    ///
    /// Outputs:
    ///   Returns a library wrapper that resolves symbols from `entries`.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The caller keeps the symbol table alive for the library lifetime.
    ///
    /// Decisions:
    ///   Use the same lookup surface for dynamic and static loading.
    ///
    /// Validation:
    ///   Covered by the static symbol backend test in this file.
    pub fn fromStaticSymbols(entries: []const SymbolEntry) Library {
        return .{
            .backend = .{
                .static_symbols = entries,
            },
        };
    }

    /// Purpose:
    ///   Release the active backend and poison the wrapper.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `dynlib::close`
    ///
    /// Inputs:
    ///   The current library backend stored on `self`.
    ///
    /// Outputs:
    ///   Destroys the active backend, if any.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   `close` is called at most once for a live wrapper.
    ///
    /// Decisions:
    ///   Clear the wrapper after closing so accidental reuse fails fast.
    ///
    /// Validation:
    ///   Covered indirectly by the backend tests.
    pub fn close(self: *Library) void {
        switch (self.backend) {
            .dynamic => |*dynamic| dynamic.close(),
            .static_symbols => {},
        }
        self.* = undefined;
    }

    /// Purpose:
    ///   Resolve a typed symbol from the active backend.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `dynlib::lookup`
    ///
    /// Inputs:
    ///   `symbol` names the function or object to resolve.
    ///
    /// Outputs:
    ///   Returns a typed pointer or null when the symbol is missing.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   `T` is a pointer type when used with the static backend.
    ///
    /// Decisions:
    ///   Preserve the lookup shape across backends so tests and runtime code
    ///   share one resolver.
    ///
    /// Validation:
    ///   Covered by the static symbol backend test in this file.
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
