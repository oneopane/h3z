//! Server adapter interface for H3 framework
//! Provides a unified interface for different I/O implementations

const std = @import("std");
const H3App = @import("../core/app.zig").H3;
const ServeOptions = @import("config.zig").ServeOptions;

/// Server adapter interface
pub fn ServerAdapter(comptime Implementation: type) type {
    return struct {
        const Self = @This();

        impl: Implementation,

        /// Initialize the adapter
        pub fn init(allocator: std.mem.Allocator, app: *H3App) Self {
            return Self{
                .impl = Implementation.init(allocator, app),
            };
        }

        /// Start listening for connections
        pub fn listen(self: *Self, options: ServeOptions) !void {
            return self.impl.listen(options);
        }

        /// Stop the server gracefully
        pub fn stop(self: *Self) void {
            return self.impl.stop();
        }

        /// Cleanup resources
        pub fn deinit(self: *Self) void {
            return self.impl.deinit();
        }

        /// Get adapter information
        pub fn info(self: *Self) AdapterInfo {
            return self.impl.info();
        }
    };
}

/// Adapter information
pub const AdapterInfo = struct {
    name: []const u8,
    version: []const u8,
    features: AdapterFeatures,
    io_model: IOModel,
};

/// Adapter features
pub const AdapterFeatures = struct {
    ssl: bool = false,
    http2: bool = false,
    websocket: bool = false,
    keep_alive: bool = true,
    compression: bool = false,
    streaming: bool = true,
};

/// I/O model types
pub const IOModel = enum {
    sync, // Synchronous blocking I/O
    async_single, // Asynchronous single-threaded
    async_multi, // Asynchronous multi-threaded
    thread_pool, // Thread pool with blocking I/O
};

/// Adapter types
pub const AdapterType = enum {
    std,
    libxev,
    auto,

    /// Get the best adapter for the current platform
    pub fn getBest() AdapterType {
        // libxev is now always available as a dependency
        return .libxev;
    }
};

/// Connection context for adapters
pub const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    remote_address: std.net.Address,
    local_address: std.net.Address,
    start_time: i64,
    request_count: u32 = 0,
    keep_alive: bool = true,
};

/// Request processing result
pub const ProcessResult = enum {
    ok,
    close_connection,
    keep_alive,
    error_occurred,
};

/// Adapter requirements interface
/// All adapter implementations must provide these functions
pub fn AdapterInterface(comptime T: type) void {
    // Compile-time interface checking
    _ = T.init; // fn init(allocator: std.mem.Allocator, app: *H3App) T
    _ = T.listen; // fn listen(self: *T, options: ServeOptions) !void
    _ = T.stop; // fn stop(self: *T) void
    _ = T.deinit; // fn deinit(self: *T) void
    _ = T.info; // fn info(self: *T) AdapterInfo
}

/// Create a server with the specified adapter
pub fn createServer(comptime AdapterImpl: type, allocator: std.mem.Allocator, app: *H3App) ServerAdapter(AdapterImpl) {
    // Compile-time interface validation
    AdapterInterface(AdapterImpl);

    return ServerAdapter(AdapterImpl).init(allocator, app);
}

/// Server factory for creating servers with different adapters
pub const ServerFactory = struct {
    /// Create a server with automatic adapter selection
    pub fn createAuto(allocator: std.mem.Allocator, app: *H3App) AnyServer {
        const adapter_type = AdapterType.getBest();
        return createWithType(adapter_type, allocator, app);
    }

    /// Create a server with specific adapter type
    pub fn createWithType(adapter_type: AdapterType, allocator: std.mem.Allocator, app: *H3App) AnyServer {
        return switch (adapter_type) {
            .std => AnyServer{ .std = createServer(@import("adapters/std.zig").StdAdapter, allocator, app) },
            .libxev => AnyServer{ .libxev = createServer(@import("adapters/libxev.zig").LibxevAdapter, allocator, app) },
            .auto => createAuto(allocator, app),
        };
    }
};

/// Type-erased server for runtime adapter selection
pub const AnyServer = union(AdapterType) {
    std: ServerAdapter(@import("adapters/std.zig").StdAdapter),
    libxev: ServerAdapter(@import("adapters/libxev.zig").LibxevAdapter),
    auto: void, // Placeholder

    pub fn listen(self: *AnyServer, options: ServeOptions) !void {
        return switch (self.*) {
            .std => |*adapter| adapter.listen(options),
            .libxev => |*adapter| adapter.listen(options),
            .auto => unreachable,
        };
    }

    pub fn stop(self: *AnyServer) void {
        return switch (self.*) {
            .std => |*adapter| adapter.stop(),
            .libxev => |*adapter| adapter.stop(),
            .auto => unreachable,
        };
    }

    pub fn deinit(self: *AnyServer) void {
        return switch (self.*) {
            .std => |*adapter| adapter.deinit(),
            .libxev => |*adapter| adapter.deinit(),
            .auto => unreachable,
        };
    }

    pub fn info(self: *AnyServer) AdapterInfo {
        return switch (self.*) {
            .std => |*adapter| adapter.info(),
            .libxev => |*adapter| adapter.info(),
            .auto => unreachable,
        };
    }
};

/// Utility functions for adapter management
pub const AdapterUtils = struct {
    /// Check if an adapter is available at compile time
    pub fn isAvailable(comptime adapter_type: AdapterType) bool {
        return switch (adapter_type) {
            .std => true, // Always available
            .libxev => true, // Always available as dependency
            .auto => true,
        };
    }

    /// Get adapter name as string
    pub fn getName(adapter_type: AdapterType) []const u8 {
        return switch (adapter_type) {
            .std => "std",
            .libxev => "libxev",
            .auto => "auto",
        };
    }

    /// Compare adapter performance characteristics
    pub fn comparePerformance(a: AdapterType, b: AdapterType) std.math.Order {
        const scores = std.EnumMap(AdapterType, u8).init(.{
            .std = 1,
            .libxev = 3,
            .auto = 0,
        });

        const score_a = scores.get(a) orelse 0;
        const score_b = scores.get(b) orelse 0;

        return std.math.order(score_a, score_b);
    }
};

// Tests
test "AdapterType.getBest" {
    const best = AdapterType.getBest();
    try std.testing.expect(best == .libxev or best == .std);
}

test "AdapterUtils.isAvailable" {
    try std.testing.expect(AdapterUtils.isAvailable(.std));
    // libxev availability depends on build configuration
}

test "AdapterUtils.getName" {
    try std.testing.expectEqualStrings("std", AdapterUtils.getName(.std));
    try std.testing.expectEqualStrings("libxev", AdapterUtils.getName(.libxev));
    try std.testing.expectEqualStrings("auto", AdapterUtils.getName(.auto));
}

test "AdapterUtils.comparePerformance" {
    try std.testing.expect(AdapterUtils.comparePerformance(.libxev, .std) == .gt);
    try std.testing.expect(AdapterUtils.comparePerformance(.std, .std) == .eq);
}
