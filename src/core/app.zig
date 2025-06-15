//! H3 application class - the main entry point for the framework

const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;
const HttpStatus = @import("../http/status.zig").HttpStatus;
const H3Event = @import("event.zig").H3Event;
const Router = @import("router.zig").Router;
const Route = @import("router.zig").Route;
const RouteMatch = @import("router.zig").RouteMatch;
pub const Handler = @import("router.zig").Handler;
const interfaces = @import("interfaces.zig");
pub const Middleware = interfaces.Middleware;
pub const MiddlewareContext = interfaces.MiddlewareContext;
const EventPool = @import("event_pool.zig").EventPool;
const FastMiddlewareChain = @import("fast_middleware.zig").FastMiddlewareChain;
const FastMiddleware = @import("fast_middleware.zig").FastMiddleware;

/// Global hook function types
pub const OnRequestHook = *const fn (*H3Event) anyerror!void;
pub const OnResponseHook = *const fn (*H3Event) anyerror!void;
pub const OnErrorHook = *const fn (*H3Event, anyerror) anyerror!void;

/// H3 application configuration with performance options
pub const H3Config = struct {
    debug: bool = false,
    on_request: ?OnRequestHook = null,
    on_response: ?OnResponseHook = null,
    on_error: ?OnErrorHook = null,

    // Performance configuration
    use_event_pool: bool = true,
    event_pool_size: usize = 100,
    use_fast_middleware: bool = true,
    enable_route_compilation: bool = true,
};

/// Execute middleware at a specific index in the chain
fn executeMiddlewareAtIndex(app: *H3, event: *H3Event, index: usize, final_handler: Handler) !void {
    if (index >= app.middlewares.items.len) {
        // All middlewares executed, call the final handler
        try final_handler(event);
        return;
    }

    // Get current middleware
    const middleware = app.middlewares.items[index];

    // Create middleware context with type safety
    const context = interfaces.createMiddlewareContext(app);

    // Call the middleware with clean interface
    try middleware(event, context, index + 1, final_handler);
}

/// High-performance H3 application class with optimized components
pub const H3 = struct {
    router: Router,
    middlewares: std.ArrayList(Middleware),
    fast_middlewares: FastMiddlewareChain,
    event_pool: ?EventPool,
    config: H3Config,
    allocator: std.mem.Allocator,

    /// Initialize a new H3 application with performance optimizations
    pub fn init(allocator: std.mem.Allocator) H3 {
        const config = H3Config{};
        return H3.initWithConfig(allocator, config);
    }

    /// Initialize with configuration and performance optimizations
    pub fn initWithConfig(allocator: std.mem.Allocator, config: H3Config) H3 {
        var app = H3{
            .router = Router.init(allocator),
            .middlewares = std.ArrayList(Middleware).init(allocator),
            .fast_middlewares = FastMiddlewareChain.init(),
            .event_pool = null,
            .config = config,
            .allocator = allocator,
        };

        // Initialize event pool if enabled
        if (config.use_event_pool) {
            app.event_pool = EventPool.init(allocator, config.event_pool_size);

            // Warm up the pool with some events
            if (app.event_pool) |*pool| {
                pool.warmUp(config.event_pool_size / 4) catch {}; // Warm up 25% of pool
            }
        }

        return app;
    }

    /// Deinitialize the application and cleanup resources
    pub fn deinit(self: *H3) void {
        self.router.deinit();
        self.middlewares.deinit();
        self.fast_middlewares.deinit();

        if (self.event_pool) |*pool| {
            pool.deinit();
        }
    }

    /// Register a route handler for a specific HTTP method
    pub fn on(self: *H3, method: HttpMethod, pattern: []const u8, handler: Handler) *H3 {
        self.router.addRoute(method, pattern, handler) catch |err| {
            std.log.err("Failed to add route: {}", .{err});
            return self;
        };
        return self;
    }

    /// Register a GET route handler
    pub fn get(self: *H3, pattern: []const u8, handler: Handler) *H3 {
        return self.on(.GET, pattern, handler);
    }

    /// Register a POST route handler
    pub fn post(self: *H3, pattern: []const u8, handler: Handler) *H3 {
        return self.on(.POST, pattern, handler);
    }

    /// Register a PUT route handler
    pub fn put(self: *H3, pattern: []const u8, handler: Handler) *H3 {
        return self.on(.PUT, pattern, handler);
    }

    /// Register a DELETE route handler
    pub fn delete(self: *H3, pattern: []const u8, handler: Handler) *H3 {
        return self.on(.DELETE, pattern, handler);
    }

    /// Register a PATCH route handler
    pub fn patch(self: *H3, pattern: []const u8, handler: Handler) *H3 {
        return self.on(.PATCH, pattern, handler);
    }

    /// Register a HEAD route handler
    pub fn head(self: *H3, pattern: []const u8, handler: Handler) *H3 {
        return self.on(.HEAD, pattern, handler);
    }

    /// Register an OPTIONS route handler
    pub fn options(self: *H3, pattern: []const u8, handler: Handler) *H3 {
        return self.on(.OPTIONS, pattern, handler);
    }

    /// Register a route handler for all HTTP methods
    pub fn all(self: *H3, pattern: []const u8, handler: Handler) *H3 {
        inline for (std.meta.fields(HttpMethod)) |field| {
            const method = @field(HttpMethod, field.name);
            _ = self.on(method, pattern, handler);
        }
        return self;
    }

    /// Register a global middleware (legacy API)
    pub fn use(self: *H3, middleware: Middleware) *H3 {
        self.middlewares.append(middleware) catch |err| {
            std.log.err("Failed to add middleware: {}", .{err});
            return self;
        };
        return self;
    }

    /// Register a fast middleware (recommended for performance)
    pub fn useFast(self: *H3, middleware: FastMiddleware) *H3 {
        self.fast_middlewares.use(middleware) catch |err| {
            std.log.err("Failed to add fast middleware: {}", .{err});
            return self;
        };
        return self;
    }

    /// Handle an HTTP request
    pub fn handle(self: *H3, event: *H3Event) !void {
        // Call global request hook
        if (self.config.on_request) |hook| {
            hook(event) catch |err| {
                if (self.config.on_error) |error_hook| {
                    try error_hook(event, err);
                    return;
                }
                return err;
            };
        }

        // Parse query parameters
        event.parseQuery() catch |err| {
            std.log.warn("Failed to parse query parameters: {}", .{err});
        };

        // Find matching route with optimized lookup
        if (self.router.findRoute(event.getMethod(), event.getPath())) |match| {
            defer self.router.releaseMatch(match);

            // Set route parameters in event
            var param_iter = match.params.params.iterator();
            while (param_iter.next()) |entry| {
                try event.setParam(entry.key_ptr.*, entry.value_ptr.*);
            }

            // Execute optimized middleware chain
            if (self.config.use_fast_middleware and self.fast_middlewares.getCount() > 0) {
                try self.fast_middlewares.executeWithErrorHandling(event, match.handler, self.config.on_error);
            } else {
                try self.executeMiddlewareChain(event, match.handler);
            }
        } else {
            // No route found - 404
            event.setStatus(.not_found);
            try event.sendText("Not Found");
        }

        // Call global response hook
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

    /// Execute the middleware chain
    fn executeMiddlewareChain(self: *H3, event: *H3Event, final_handler: Handler) !void {
        try executeMiddlewareAtIndex(self, event, 0, final_handler);
    }

    /// Call the next middleware in the chain (used by middleware implementations)
    pub fn next(self: *H3, event: *H3Event, index: usize, final_handler: Handler) !void {
        try executeMiddlewareAtIndex(self, event, index, final_handler);
    }

    /// Get the number of registered routes
    pub fn getRouteCount(self: *const H3) usize {
        return self.router.getRouteCount();
    }

    /// Get the number of registered middlewares
    pub fn getMiddlewareCount(self: *const H3) usize {
        return self.middlewares.items.len;
    }

    /// Get the number of registered fast middlewares
    pub fn getFastMiddlewareCount(self: *const H3) u8 {
        return self.fast_middlewares.getCount();
    }

    /// Clear all routes and middlewares
    pub fn clear(self: *H3) void {
        self.router.clear();
        self.middlewares.clearRetainingCapacity();
        self.fast_middlewares.clear();
    }

    /// Find a route for the given method and path
    pub fn findRoute(self: *H3, method: HttpMethod, path: []const u8) ?Handler {
        if (self.router.findRoute(method, path)) |match| {
            defer self.router.releaseMatch(match);
            return match.handler;
        }
        return null;
    }

    /// Extract parameters from a route match
    pub fn extractParams(self: *H3, event: *H3Event, method: HttpMethod, path: []const u8) !void {
        if (self.router.findRoute(method, path)) |match| {
            defer self.router.releaseMatch(match);

            // Set route parameters in event
            var param_iter = match.params.params.iterator();
            while (param_iter.next()) |entry| {
                try event.setParam(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }

    /// Execute middleware chain for testing
    pub fn executeMiddleware(self: *H3, event: *H3Event, handler: Handler) !void {
        try self.executeMiddlewareChain(event, handler);
    }

    /// Get routes for testing
    pub fn routes(self: *const H3) std.ArrayList(Route) {
        return self.router.getRoutes();
    }
};

test "H3.init and deinit" {
    var app = H3.init(std.testing.allocator);
    defer app.deinit();

    try std.testing.expectEqual(@as(usize, 0), app.getRouteCount());
    try std.testing.expectEqual(@as(usize, 0), app.getMiddlewareCount());
}

test "H3.route registration" {
    var app = H3.init(std.testing.allocator);
    defer app.deinit();

    const testHandler = struct {
        fn handler(event: *H3Event) !void {
            try event.sendText("Hello");
        }
    }.handler;

    _ = app.get("/", testHandler);
    _ = app.post("/users", testHandler);
    _ = app.put("/users/:id", testHandler);

    try std.testing.expectEqual(@as(usize, 3), app.getRouteCount());
}

test "H3.middleware registration" {
    var app = H3.init(std.testing.allocator);
    defer app.deinit();

    const testMiddleware = struct {
        fn middleware(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
            // Call next middleware
            try context.next(event, index, final_handler);
        }
    }.middleware;

    _ = app.use(testMiddleware);
    _ = app.use(testMiddleware);

    try std.testing.expectEqual(@as(usize, 2), app.getMiddlewareCount());
}

test "H3.handle basic request" {
    var app = H3.init(std.testing.allocator);
    defer app.deinit();

    const testHandler = struct {
        fn handler(event: *H3Event) !void {
            try event.sendText("Hello, World!");
        }
    }.handler;

    _ = app.get("/", testHandler);

    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    event.request.method = .GET;
    try event.request.parseUrl("/");

    try app.handle(&event);

    try std.testing.expectEqualStrings("Hello, World!", event.response.body.?);
    try std.testing.expectEqual(HttpStatus.ok, event.response.status);
}

test "H3.middleware chain execution" {
    var app = H3.init(std.testing.allocator);
    defer app.deinit();

    // This test verifies middleware chain execution order

    // First middleware
    const middleware1 = struct {
        fn middleware(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
            // Get context from event (simplified for test)
            try event.setContext("test", "1");

            // Call next middleware
            try context.next(event, index, final_handler);

            // Post-processing
            try event.setContext("post1", "done");
        }
    }.middleware;

    // Second middleware
    const middleware2 = struct {
        fn middleware(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
            try event.setContext("test2", "2");

            // Call next middleware
            try context.next(event, index, final_handler);

            try event.setContext("post2", "done");
        }
    }.middleware;

    const testHandler = struct {
        fn handler(event: *H3Event) !void {
            // Verify middlewares ran
            try std.testing.expectEqualStrings("1", event.getContext("test").?);
            try std.testing.expectEqualStrings("2", event.getContext("test2").?);

            try event.sendText("Middleware test passed!");
        }
    }.handler;

    // Register middlewares and handler
    _ = app.use(middleware1);
    _ = app.use(middleware2);
    _ = app.get("/test", testHandler);

    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    event.request.method = .GET;
    try event.request.parseUrl("/test");

    try app.handle(&event);

    // Verify response
    try std.testing.expectEqualStrings("Middleware test passed!", event.response.body.?);

    // Verify post-processing ran
    try std.testing.expectEqualStrings("done", event.getContext("post1").?);
    try std.testing.expectEqualStrings("done", event.getContext("post2").?);
}
