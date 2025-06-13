//! H3 application class - the main entry point for the framework

const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;
const HttpStatus = @import("../http/status.zig").HttpStatus;
const H3Event = @import("event.zig").H3Event;
const Router = @import("router.zig").Router;
pub const Handler = @import("router.zig").Handler;

/// Middleware function type
pub const Middleware = *const fn (*H3Event, Handler) anyerror!void;

/// Global hook function types
pub const OnRequestHook = *const fn (*H3Event) anyerror!void;
pub const OnResponseHook = *const fn (*H3Event) anyerror!void;
pub const OnErrorHook = *const fn (*H3Event, anyerror) anyerror!void;

/// H3 application configuration
pub const H3Config = struct {
    debug: bool = false,
    on_request: ?OnRequestHook = null,
    on_response: ?OnResponseHook = null,
    on_error: ?OnErrorHook = null,
};

/// H3 application class
pub const H3 = struct {
    router: Router,
    middlewares: std.ArrayList(Middleware),
    config: H3Config,
    allocator: std.mem.Allocator,

    /// Initialize a new H3 application
    pub fn init(allocator: std.mem.Allocator) H3 {
        return H3{
            .router = Router.init(allocator),
            .middlewares = std.ArrayList(Middleware).init(allocator),
            .config = H3Config{},
            .allocator = allocator,
        };
    }

    /// Initialize with configuration
    pub fn initWithConfig(allocator: std.mem.Allocator, config: H3Config) H3 {
        return H3{
            .router = Router.init(allocator),
            .middlewares = std.ArrayList(Middleware).init(allocator),
            .config = config,
            .allocator = allocator,
        };
    }

    /// Deinitialize the application
    pub fn deinit(self: *H3) void {
        self.router.deinit();
        self.middlewares.deinit();
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

    /// Register a global middleware
    pub fn use(self: *H3, middleware: Middleware) *H3 {
        self.middlewares.append(middleware) catch |err| {
            std.log.err("Failed to add middleware: {}", .{err});
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

        // Find matching route
        if (self.router.findRoute(event.getMethod(), event.getPath())) |match| {
            var params = match.params;
            defer params.deinit();

            // Set route parameters in event
            var param_iter = params.iterator();
            while (param_iter.next()) |entry| {
                try event.setParam(entry.key_ptr.*, entry.value_ptr.*);
            }

            // Execute middleware chain
            try self.executeMiddlewareChain(event, match.route.handler);
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
        if (self.middlewares.items.len == 0) {
            try final_handler(event);
            return;
        }

        // Create a context for the middleware chain
        const MiddlewareContext = struct {
            app: *H3,
            event: *H3Event,
            index: usize,
            final_handler: Handler,

            fn next(ctx: *@This()) !void {
                if (ctx.index >= ctx.app.middlewares.items.len) {
                    try ctx.final_handler(ctx.event);
                    return;
                }

                const middleware = ctx.app.middlewares.items[ctx.index];
                ctx.index += 1;

                const next_handler = struct {
                    fn handler(e: *H3Event) !void {
                        _ = e;
                        // This is a simplified implementation
                        // In a real implementation, we'd need proper closure handling
                    }
                }.handler;

                try middleware(ctx.event, next_handler);
            }
        };

        var ctx = MiddlewareContext{
            .app = self,
            .event = event,
            .index = 0,
            .final_handler = final_handler,
        };

        try ctx.next();
    }

    /// Get the number of registered routes
    pub fn getRouteCount(self: *const H3) usize {
        return self.router.getRoutes().len;
    }

    /// Get the number of registered middlewares
    pub fn getMiddlewareCount(self: *const H3) usize {
        return self.middlewares.items.len;
    }

    /// Clear all routes and middlewares
    pub fn clear(self: *H3) void {
        self.router.clear();
        self.middlewares.clearRetainingCapacity();
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
        fn middleware(event: *H3Event, next: Handler) !void {
            _ = event;
            _ = next;
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
