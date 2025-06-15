//! Integration tests for H3 middleware functionality
//! Tests middleware execution order, context passing, and error handling

const std = @import("std");
const testing = std.testing;
const h3 = @import("h3");
const test_utils = @import("test_utils");

// Test middleware functions
const LoggingMiddleware = struct {
    fn middleware(event: *h3.Event, next: h3.NextFunction) !void {
        // Add logging header to track middleware execution
        try event.response.setHeader("X-Middleware-Logging", "executed");
        try next(event);
    }
};

const AuthMiddleware = struct {
    fn middleware(event: *h3.Event, next: h3.NextFunction) !void {
        const auth_header = event.getHeader("Authorization");
        if (auth_header == null) {
            try h3.sendError(event, .unauthorized, "Authorization header required");
            return;
        }

        if (!std.mem.startsWith(u8, auth_header.?, "Bearer ")) {
            try h3.sendError(event, .unauthorized, "Invalid authorization format");
            return;
        }

        // Add user info to context (simulated)
        try event.response.setHeader("X-User-Id", "123");
        try next(event);
    }
};

const CorsMiddleware = struct {
    fn middleware(event: *h3.Event, next: h3.NextFunction) !void {
        // Add CORS headers
        try event.response.setHeader("Access-Control-Allow-Origin", "*");
        try event.response.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        try event.response.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

        // Handle preflight requests
        if (event.request.method == .OPTIONS) {
            event.response.status = .no_content;
            return;
        }

        try next(event);
    }
};

const TimingMiddleware = struct {
    fn middleware(event: *h3.Event, next: h3.NextFunction) !void {
        const start_time = std.time.milliTimestamp();
        try next(event);
        const end_time = std.time.milliTimestamp();

        const duration = end_time - start_time;
        const duration_str = try std.fmt.allocPrint(event.allocator, "{}", .{duration});
        defer event.allocator.free(duration_str);

        try event.response.setHeader("X-Response-Time", duration_str);
    }
};

const ErrorHandlingMiddleware = struct {
    fn middleware(event: *h3.Event, next: h3.NextFunction) !void {
        next(event) catch |err| {
            switch (err) {
                error.NotFound => try h3.sendError(event, .not_found, "Resource not found"),
                error.Unauthorized => try h3.sendError(event, .unauthorized, "Access denied"),
                else => try h3.sendError(event, .internal_server_error, "Internal server error"),
            }
        };
    }
};

// Test handlers
fn protectedHandler(event: *h3.Event) !void {
    const user_id = event.response.getHeader("X-User-Id") orelse "unknown";
    const response = .{
        .message = "Protected resource accessed",
        .user_id = user_id,
    };
    try h3.sendJson(event, response);
}

fn publicHandler(event: *h3.Event) !void {
    try h3.sendJson(event, .{ .message = "Public resource" });
}

fn errorHandler(event: *h3.Event) !void {
    _ = event;
    return error.NotFound;
}

test "Basic middleware execution" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Add global middleware
    app.use(LoggingMiddleware.middleware);
    app.use(CorsMiddleware.middleware);

    // Register route
    _ = app.get("/public", publicHandler);

    // Test request
    var request = test_utils.MockRequest.init(allocator);
    defer request.deinit();

    _ = request.setMethod(.GET).setPath("/public");
    var event = try request.toEvent();
    defer event.deinit();

    // Simulate middleware execution
    const route = app.findRoute(.GET, "/public");
    try testing.expect(route != null);

    // Execute middleware chain
    try app.executeMiddleware(&event, route.?);

    // Check that middleware was executed
    try testing.expectEqualStrings("executed", event.response.getHeader("X-Middleware-Logging").?);
    try testing.expectEqualStrings("*", event.response.getHeader("Access-Control-Allow-Origin").?);
    try testing.expectEqual(h3.HttpStatus.ok, event.response.status);
}

test "Authentication middleware" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Add auth middleware to protected route
    _ = app.get("/protected", protectedHandler).use(AuthMiddleware.middleware);
    _ = app.get("/public", publicHandler);

    // Test protected route without auth header
    var unauth_request = test_utils.MockRequest.init(allocator);
    defer unauth_request.deinit();

    _ = unauth_request.setMethod(.GET).setPath("/protected");
    var unauth_event = try unauth_request.toEvent();
    defer unauth_event.deinit();

    const protected_route = app.findRoute(.GET, "/protected");
    try testing.expect(protected_route != null);
    try app.executeMiddleware(&unauth_event, protected_route.?);

    try testing.expectEqual(h3.HttpStatus.unauthorized, unauth_event.response.status);

    // Test protected route with valid auth header
    var auth_request = test_utils.MockRequest.init(allocator);
    defer auth_request.deinit();

    _ = try auth_request
        .setMethod(.GET)
        .setPath("/protected")
        .setHeader("Authorization", "Bearer valid-token");

    var auth_event = try auth_request.toEvent();
    defer auth_event.deinit();

    try app.executeMiddleware(&auth_event, protected_route.?);

    try testing.expectEqual(h3.HttpStatus.ok, auth_event.response.status);
    try testing.expectEqualStrings("123", auth_event.response.getHeader("X-User-Id").?);

    // Test public route (no auth required)
    var public_request = test_utils.MockRequest.init(allocator);
    defer public_request.deinit();

    _ = public_request.setMethod(.GET).setPath("/public");
    var public_event = try public_request.toEvent();
    defer public_event.deinit();

    const public_route = app.findRoute(.GET, "/public");
    try testing.expect(public_route != null);
    try app.executeMiddleware(&public_event, public_route.?);

    try testing.expectEqual(h3.HttpStatus.ok, public_event.response.status);
}

test "CORS middleware with preflight" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Add CORS middleware globally
    app.use(CorsMiddleware.middleware);
    _ = app.post("/api/data", publicHandler);

    // Test preflight OPTIONS request
    var preflight_request = test_utils.MockRequest.init(allocator);
    defer preflight_request.deinit();

    _ = try preflight_request
        .setMethod(.OPTIONS)
        .setPath("/api/data")
        .setHeader("Origin", "https://example.com")
        .setHeader("Access-Control-Request-Method", "POST")
        .setHeader("Access-Control-Request-Headers", "Content-Type");

    var preflight_event = try preflight_request.toEvent();
    defer preflight_event.deinit();

    // Execute CORS middleware
    try CorsMiddleware.middleware(&preflight_event, struct {
        fn next(event: *h3.Event) !void {
            // Not called for OPTIONS requests
            try h3.sendText(event, "Not reached");
        }
    }.next);

    try testing.expectEqual(h3.HttpStatus.no_content, preflight_event.response.status);
    try testing.expectEqualStrings("*", preflight_event.response.getHeader("Access-Control-Allow-Origin").?);
    try testing.expectEqualStrings("GET, POST, PUT, DELETE, OPTIONS", preflight_event.response.getHeader("Access-Control-Allow-Methods").?);

    // Test actual POST request
    var post_request = test_utils.MockRequest.init(allocator);
    defer post_request.deinit();

    _ = try post_request
        .setMethod(.POST)
        .setPath("/api/data")
        .setHeader("Origin", "https://example.com")
        .setJson("{\"data\":\"test\"}");

    var post_event = try post_request.toEvent();
    defer post_event.deinit();

    const post_route = app.findRoute(.POST, "/api/data");
    try testing.expect(post_route != null);
    try app.executeMiddleware(&post_event, post_route.?);

    try testing.expectEqual(h3.HttpStatus.ok, post_event.response.status);
    try testing.expectEqualStrings("*", post_event.response.getHeader("Access-Control-Allow-Origin").?);
}

test "Timing middleware" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Add timing middleware
    app.use(TimingMiddleware.middleware);
    _ = app.get("/timed", publicHandler);

    var request = test_utils.MockRequest.init(allocator);
    defer request.deinit();

    _ = request.setMethod(.GET).setPath("/timed");
    var event = try request.toEvent();
    defer event.deinit();

    const route = app.findRoute(.GET, "/timed");
    try testing.expect(route != null);
    try app.executeMiddleware(&event, route.?);

    try testing.expectEqual(h3.HttpStatus.ok, event.response.status);

    const response_time = event.response.getHeader("X-Response-Time");
    try testing.expect(response_time != null);
    try testing.expect(response_time.?.len > 0);
}

test "Error handling middleware" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Add error handling middleware
    app.use(ErrorHandlingMiddleware.middleware);
    _ = app.get("/error", errorHandler);

    var request = test_utils.MockRequest.init(allocator);
    defer request.deinit();

    _ = request.setMethod(.GET).setPath("/error");
    var event = try request.toEvent();
    defer event.deinit();

    const route = app.findRoute(.GET, "/error");
    try testing.expect(route != null);
    try app.executeMiddleware(&event, route.?);

    try testing.expectEqual(h3.HttpStatus.not_found, event.response.status);
    try test_utils.assert.expectJsonField(event.response.body.?, "message", "Resource not found");
}

test "Middleware execution order" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Add middleware in specific order
    app.use(struct {
        fn middleware(event: *h3.Event, next: h3.NextFunction) !void {
            try event.response.setHeader("X-Order-1", "first");
            try next(event);
            try event.response.setHeader("X-Order-1-After", "first-after");
        }
    }.middleware);

    app.use(struct {
        fn middleware(event: *h3.Event, next: h3.NextFunction) !void {
            try event.response.setHeader("X-Order-2", "second");
            try next(event);
            try event.response.setHeader("X-Order-2-After", "second-after");
        }
    }.middleware);

    _ = app.get("/order", publicHandler);

    var request = test_utils.MockRequest.init(allocator);
    defer request.deinit();

    _ = request.setMethod(.GET).setPath("/order");
    var event = try request.toEvent();
    defer event.deinit();

    const route = app.findRoute(.GET, "/order");
    try testing.expect(route != null);
    try app.executeMiddleware(&event, route.?);

    // Check that middleware executed in correct order
    try testing.expectEqualStrings("first", event.response.getHeader("X-Order-1").?);
    try testing.expectEqualStrings("second", event.response.getHeader("X-Order-2").?);
    try testing.expectEqualStrings("first-after", event.response.getHeader("X-Order-1-After").?);
    try testing.expectEqualStrings("second-after", event.response.getHeader("X-Order-2-After").?);
}

test "Route-specific middleware" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Add global middleware
    app.use(LoggingMiddleware.middleware);

    // Add route-specific middleware
    _ = app.get("/protected", protectedHandler).use(AuthMiddleware.middleware);
    _ = app.get("/public", publicHandler);

    // Test protected route with middleware
    var protected_request = test_utils.MockRequest.init(allocator);
    defer protected_request.deinit();

    _ = try protected_request
        .setMethod(.GET)
        .setPath("/protected")
        .setHeader("Authorization", "Bearer token");

    var protected_event = try protected_request.toEvent();
    defer protected_event.deinit();

    const protected_route = app.findRoute(.GET, "/protected");
    try testing.expect(protected_route != null);
    try app.executeMiddleware(&protected_event, protected_route.?);

    try testing.expectEqualStrings("executed", protected_event.response.getHeader("X-Middleware-Logging").?);
    try testing.expectEqualStrings("123", protected_event.response.getHeader("X-User-Id").?);

    // Test public route with global middleware
    var public_request = test_utils.MockRequest.init(allocator);
    defer public_request.deinit();

    _ = public_request.setMethod(.GET).setPath("/public");
    var public_event = try public_request.toEvent();
    defer public_event.deinit();

    const public_route = app.findRoute(.GET, "/public");
    try testing.expect(public_route != null);
    try app.executeMiddleware(&public_event, public_route.?);

    try testing.expectEqualStrings("executed", public_event.response.getHeader("X-Middleware-Logging").?);
    try testing.expect(public_event.response.getHeader("X-User-Id") == null);
}
