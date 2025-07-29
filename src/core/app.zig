//! H3 application class - the main entry point for the framework
//! Now using component-based architecture with unified configuration

const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;
const HttpStatus = @import("../http/status.zig").HttpStatus;
const H3Event = @import("event.zig").H3Event;
const Router = @import("router.zig").Router;
const RouterComponent = @import("router.zig").RouterComponent;
const Route = @import("router.zig").Route;
const RouteMatch = @import("router.zig").RouteMatch;
pub const Handler = @import("router.zig").Handler;
const interfaces = @import("interfaces.zig");
pub const Middleware = interfaces.Middleware;
pub const MiddlewareContext = interfaces.MiddlewareContext;
const EventPool = @import("event_pool.zig").EventPool;
const FastMiddlewareChain = @import("fast_middleware.zig").FastMiddlewareChain;
const config = @import("config.zig");
const MemoryManager = @import("memory_manager.zig").MemoryManager;
const MemoryStats = @import("memory_manager.zig").MemoryStats;
const component = @import("component.zig");
const ComponentRegistry = component.ComponentRegistry;
const FastMiddleware = @import("fast_middleware.zig").FastMiddleware;

pub const H3App = struct {
    // Core components
    memory_manager: MemoryManager,
    component_registry: ComponentRegistry,
    router_component: RouterComponent,

    // Configuration and allocator
    config: config.H3Config,
    allocator: std.mem.Allocator,

    const Self = @This();

    // TODO: Change initialization so that we do something using comptime (init and initWithConfig)
    /// Initialize a new H3 application with component architecture
    pub fn init(allocator: std.mem.Allocator) !Self {
        const h3_config = config.H3Config.development();
        return Self.initWithConfig(allocator, h3_config);
    }

    /// Initialize with configuration
    pub fn initWithConfig(allocator: std.mem.Allocator, h3_config: config.H3Config) !Self {
        try h3_config.validate();

        var memory_manager = try MemoryManager.init(allocator, h3_config.memory);
        var component_registry = ComponentRegistry.init(allocator, &memory_manager, &h3_config);
        var router_component = try RouterComponent.init(allocator, h3_config.router);

        try component_registry.register(router_component.component());

        var app = Self{
            .memory_manager = memory_manager,
            .component_registry = component_registry,
            .router_component = router_component,
            .config = h3_config,
            .allocator = allocator,
        };

        try app.component_registry.startAll();

        return app;
    }

    /// Deinitialize the application
    pub fn deinit(self: *Self) void {
        self.component_registry.deinit();
        self.memory_manager.deinit();
    }

    /// Register a route handler with automatic type detection
    pub fn on(self: *Self, method: HttpMethod, pattern: []const u8, comptime handler: anytype) !*Self {
        try self.router_component.addRoute(method, pattern, handler);
        return self;
    }

    /// Register a GET route handler with automatic type detection
    pub fn get(self: *Self, pattern: []const u8, comptime handler: anytype) !*Self {
        return self.on(.GET, pattern, handler);
    }

    /// Register a POST route handler with automatic type detection
    pub fn post(self: *Self, pattern: []const u8, comptime handler: anytype) !*Self {
        return self.on(.POST, pattern, handler);
    }

    /// Register a PUT route handler with automatic type detection
    pub fn put(self: *Self, pattern: []const u8, comptime handler: anytype) !*Self {
        return self.on(.PUT, pattern, handler);
    }

    /// Register a DELETE route handler with automatic type detection
    pub fn delete(self: *Self, pattern: []const u8, comptime handler: anytype) !*Self {
        return self.on(.DELETE, pattern, handler);
    }

    /// Handle an HTTP request
    pub fn handle(self: *Self, event: *H3Event) !void {
        if (self.config.on_request) |hook| {
            hook(event) catch |err| {
                if (self.config.on_error) |error_hook| {
                    try error_hook(event, err);
                    return;
                }
                return err;
            };
        }

        event.parseQuery() catch |err| {
            std.log.warn("Failed to parse query parameters: {}", .{err});
        };

        if (self.router_component.findRoute(event.getMethod(), event.getPath())) |match| {
            defer self.router_component.releaseMatch(match);

            var param_iter = match.params.params.iterator();
            while (param_iter.next()) |entry| {
                try event.setParam(entry.key_ptr.*, entry.value_ptr.*);
            }

            // Handle different handler types
            switch (match.handler_type) {
                .regular => {
                    try match.handler(event);
                },
                .stream, .stream_with_loop => {
                    // For streaming handlers, set up SSE mode and store handler info
                    try event.startSSE();
                    event.sse_typed_handler = match.typed_handler;
                    event.sse_handler_type = match.handler_type;
                    // Don't call the handler directly - the adapter will handle it
                },
            }
        } else {
            event.setStatus(.not_found);
            try event.sendText("Not Found");
        }

        if (self.config.on_response) |hook| {
            hook(event) catch |err| {
                if (self.config.on_error) |error_hook| {
                    try error_hook(event, err);
                    return;
                }
                return err;
            };
        }
    }

    /// Get the number of registered routes
    pub fn getRouteCount(self: *const Self) usize {
        return self.router_component.getRouteCount();
    }

    /// Get memory statistics
    pub fn getMemoryStats(self: *const Self) MemoryStats {
        return self.memory_manager.getStats();
    }

    /// Get component health status
    pub fn getHealthStatus(self: *Self) struct { healthy: usize, total: usize } {
        const health = self.component_registry.getHealthStatus();
        return .{ .healthy = health.healthy, .total = health.total };
    }

    /// Get memory usage report
    pub fn getMemoryReport(self: *const Self) ![]u8 {
        return self.memory_manager.getReport(self.allocator);
    }

    /// Optimize memory usage
    pub fn optimizeMemory(self: *Self) void {
        self.memory_manager.optimize();
    }
};

// /// Create a fast H3 application with performance optimizations
// pub fn createFastApp(allocator: std.mem.Allocator) !H3App {
//     const fast_config = config.H3Config.production();
//     return H3App.initWithConfig(allocator, fast_config);
// }
//
// /// Create a development H3 application
// pub fn createDevApp(allocator: std.mem.Allocator) !H3App {
//     const dev_config = config.H3Config.development();
//     return H3App.initWithConfig(allocator, dev_config);
// }
//
test "H3App component architecture" {
    // Use testing config to avoid memory leaks
    const test_config = config.H3Config.testing();
    var app = try H3App.initWithConfig(std.testing.allocator, test_config);
    defer {
        // Clear routes before deinit to prevent memory leaks
        app.router_component.clear();
        app.deinit();
    }

    const testHandler = struct {
        fn handler(event: *H3Event) !void {
            try event.sendText("Component test!");
        }
    }.handler;

    _ = try app.get("/component", testHandler);

    try std.testing.expectEqual(@as(usize, 1), app.getRouteCount());

    const health = app.getHealthStatus();
    try std.testing.expect(health.healthy > 0);
    try std.testing.expect(health.total > 0);
}

test "H3App memory management" {
    var app = try H3App.init(std.testing.allocator);
    defer app.deinit();

    const stats = app.getMemoryStats();
    try std.testing.expect(stats.total_allocated >= 0);

    app.optimizeMemory();

    const report = try app.getMemoryReport();
    defer std.testing.allocator.free(report);
    try std.testing.expect(report.len > 0);
}
