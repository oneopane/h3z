//! Unified HTTP server interface for H3 framework
//! Provides a simple API that automatically selects the best adapter

const std = @import("std");
const H3App = @import("../core/app.zig").H3App;
pub const ServeOptions = @import("config.zig").ServeOptions;
const ConfigBuilder = @import("config.zig").ConfigBuilder;
const ServerFactory = @import("adapter.zig").ServerFactory;
const AnyServer = @import("adapter.zig").AnyServer;
const AdapterType = @import("adapter.zig").AdapterType;
const AdapterUtils = @import("adapter.zig").AdapterUtils;

// Re-export for convenience
pub const Config = @import("config.zig");
pub const Adapter = @import("adapter.zig");

/// Main server interface using adapter pattern
pub const Server = struct {
    server: AnyServer,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Create a server with automatic adapter selection
    pub fn init(allocator: std.mem.Allocator, app: *H3App) Self {
        const server = ServerFactory.createAuto(allocator, app);
        return Self{
            .server = server,
            .allocator = allocator,
        };
    }

    /// Create a server with specific adapter
    pub fn initWithAdapter(allocator: std.mem.Allocator, app: *H3App, adapter_type: AdapterType) Self {
        const server = ServerFactory.createWithType(adapter_type, allocator, app);
        return Self{
            .server = server,
            .allocator = allocator,
        };
    }

    /// Start the server with given options
    pub fn listen(self: *Self, options: ServeOptions) !void {
        return self.server.listen(options);
    }

    /// Stop the server gracefully
    pub fn stop(self: *Self) void {
        self.server.stop();
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        self.server.deinit();
    }

    /// Get adapter information
    pub fn getAdapterInfo(self: *Self) @import("adapter.zig").AdapterInfo {
        return self.server.info();
    }
};

/// Start a server with the given H3App using automatic adapter selection
pub fn serve(app: *H3App, options: ServeOptions) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = Server.init(allocator, app);
    defer server.deinit();

    try server.listen(options);
}

/// Start a server with specific adapter
pub fn serveWithAdapter(app: *H3App, options: ServeOptions, adapter_type: AdapterType) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = Server.initWithAdapter(allocator, app, adapter_type);
    defer server.deinit();

    try server.listen(options);
}

/// Start a server with default options
pub fn serveDefault(app: *H3App) !void {
    const options = ServeOptions{};
    try serve(app, options);
}

/// Create a configuration builder for fluent API
pub fn config() ConfigBuilder {
    return ConfigBuilder.init();
}

// Tests
test "ServeOptions default values" {
    const options = ServeOptions{};
    try std.testing.expectEqual(@as(u16, 3000), options.port);
    try std.testing.expectEqualStrings("127.0.0.1", options.host);
    try std.testing.expectEqual(@as(u32, 128), options.backlog);
}

test "Server.init" {
    var app = try H3App.init(std.testing.allocator);
    defer app.deinit();

    var server = Server.init(std.testing.allocator, &app);
    defer server.deinit();

    const adapter_info = server.getAdapterInfo();
    try std.testing.expect(adapter_info.name.len > 0);
}

test "AdapterType selection" {
    const best = AdapterType.getBest();
    try std.testing.expect(best == .libxev or best == .std);

    try std.testing.expectEqualStrings("std", AdapterUtils.getName(.std));
    try std.testing.expectEqualStrings("libxev", AdapterUtils.getName(.libxev));
}

test "ConfigBuilder fluent API" {
    var builder = config();
    const options = try builder
        .host("0.0.0.0")
        .port(8080)
        .workers(4)
        .maxConnections(2000)
        .build();

    try std.testing.expectEqualStrings("0.0.0.0", options.host);
    try std.testing.expectEqual(@as(u16, 8080), options.port);
    try std.testing.expectEqual(@as(u32, 4), options.thread_pool.workers);
    try std.testing.expectEqual(@as(u32, 2000), options.limits.max_connections);
}
