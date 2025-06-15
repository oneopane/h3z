//! Unit tests for H3 router functionality
//! Tests route registration, matching, and parameter extraction

const std = @import("std");
const testing = std.testing;
const h3 = @import("h3");
const test_utils = @import("test_utils");

// Test handler functions
fn testHandler(event: *h3.Event) !void {
    try h3.sendText(event, "Test response");
}

fn userHandler(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse "unknown";
    try h3.sendText(event, id);
}

fn userPostHandler(event: *h3.Event) !void {
    const user_id = h3.getParam(event, "user_id") orelse "unknown";
    const post_id = h3.getParam(event, "post_id") orelse "unknown";
    const response = try std.fmt.allocPrint(event.allocator, "User: {s}, Post: {s}", .{ user_id, post_id });
    defer event.allocator.free(response);
    try h3.sendText(event, response);
}

test "Basic route registration and matching" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Register routes
    _ = app.get("/", testHandler);
    _ = app.get("/about", testHandler);
    _ = app.post("/users", testHandler);
    _ = app.put("/users/:id", userHandler);
    _ = app.delete("/users/:id", userHandler);

    // Test route count
    try testing.expect(app.routes.count() == 5);

    // Test exact path matching
    const route1 = app.findRoute(.GET, "/");
    try testing.expect(route1 != null);

    const route2 = app.findRoute(.GET, "/about");
    try testing.expect(route2 != null);

    const route3 = app.findRoute(.POST, "/users");
    try testing.expect(route3 != null);

    // Test non-existent routes
    const route4 = app.findRoute(.GET, "/nonexistent");
    try testing.expect(route4 == null);

    const route5 = app.findRoute(.POST, "/about"); // Wrong method
    try testing.expect(route5 == null);
}

test "Route parameter extraction" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Register parameterized routes
    _ = app.get("/users/:id", userHandler);
    _ = app.get("/users/:user_id/posts/:post_id", userPostHandler);
    _ = app.get("/files/*path", testHandler);

    // Test single parameter
    var event1 = h3.Event.init(allocator);
    defer event1.deinit();

    const route1 = app.findRoute(.GET, "/users/123");
    try testing.expect(route1 != null);

    // Extract parameters
    try app.extractParams(&event1, route1.?, "/users/123");
    try testing.expectEqualStrings("123", h3.getParam(&event1, "id").?);

    // Test multiple parameters
    var event2 = h3.Event.init(allocator);
    defer event2.deinit();

    const route2 = app.findRoute(.GET, "/users/456/posts/789");
    try testing.expect(route2 != null);

    try app.extractParams(&event2, route2.?, "/users/456/posts/789");
    try testing.expectEqualStrings("456", h3.getParam(&event2, "user_id").?);
    try testing.expectEqualStrings("789", h3.getParam(&event2, "post_id").?);

    // Test wildcard parameter
    var event3 = h3.Event.init(allocator);
    defer event3.deinit();

    const route3 = app.findRoute(.GET, "/files/documents/report.pdf");
    try testing.expect(route3 != null);

    try app.extractParams(&event3, route3.?, "/files/documents/report.pdf");
    try testing.expectEqualStrings("documents/report.pdf", h3.getParam(&event3, "path").?);
}

test "Route pattern matching edge cases" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Register various route patterns
    _ = app.get("/", testHandler);
    _ = app.get("/users", testHandler);
    _ = app.get("/users/:id", userHandler);
    _ = app.get("/users/:id/edit", testHandler);
    _ = app.get("/admin/users/:id", userHandler);

    // Test exact matches take precedence
    const route1 = app.findRoute(.GET, "/users");
    try testing.expect(route1 != null);
    // Matches "/users" exactly

    // Test parameter routes
    const route2 = app.findRoute(.GET, "/users/123");
    try testing.expect(route2 != null);

    const route3 = app.findRoute(.GET, "/users/123/edit");
    try testing.expect(route3 != null);

    // Test nested parameters
    const route4 = app.findRoute(.GET, "/admin/users/456");
    try testing.expect(route4 != null);

    // Test non-matching routes
    const route5 = app.findRoute(.GET, "/users/123/delete"); // Not registered
    try testing.expect(route5 == null);
}

test "Route method specificity" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Register same path with different methods
    _ = app.get("/api/users", testHandler);
    _ = app.post("/api/users", testHandler);
    _ = app.put("/api/users", testHandler);
    _ = app.delete("/api/users", testHandler);

    // Test each method matches correctly
    try testing.expect(app.findRoute(.GET, "/api/users") != null);
    try testing.expect(app.findRoute(.POST, "/api/users") != null);
    try testing.expect(app.findRoute(.PUT, "/api/users") != null);
    try testing.expect(app.findRoute(.DELETE, "/api/users") != null);

    // Test unregistered method
    try testing.expect(app.findRoute(.PATCH, "/api/users") == null);
    try testing.expect(app.findRoute(.HEAD, "/api/users") == null);
}

test "Route parameter validation" {
    // Test valid route patterns
    try testing.expect(h3.isValidRoutePattern("/users"));
    try testing.expect(h3.isValidRoutePattern("/users/:id"));
    try testing.expect(h3.isValidRoutePattern("/users/:id/posts/:post_id"));
    try testing.expect(h3.isValidRoutePattern("/files/*path"));
    try testing.expect(h3.isValidRoutePattern("/api/v1/users/:id"));

    // Test invalid route patterns
    try testing.expect(!h3.isValidRoutePattern("users")); // Missing leading slash
    try testing.expect(!h3.isValidRoutePattern("/users/")); // Trailing slash
    try testing.expect(!h3.isValidRoutePattern("/users/:id:")); // Invalid parameter syntax
    try testing.expect(!h3.isValidRoutePattern("/users/*path/more")); // Content after wildcard
    try testing.expect(!h3.isValidRoutePattern("")); // Empty pattern
}

test "Route priority and ordering" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Register routes in specific order to test priority
    _ = app.get("/users/new", testHandler); // Specific route
    _ = app.get("/users/:id", userHandler); // Parameter route
    _ = app.get("/users/*path", testHandler); // Wildcard route

    // Test that specific routes take precedence
    const route1 = app.findRoute(.GET, "/users/new");
    try testing.expect(route1 != null);
    // Matches "/users/new" specifically

    const route2 = app.findRoute(.GET, "/users/123");
    try testing.expect(route2 != null);
    // Matches "/users/:id" pattern

    const route3 = app.findRoute(.GET, "/users/some/deep/path");
    try testing.expect(route3 != null);
    // Matches "/users/*path" wildcard
}

test "Route group functionality" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Test route grouping
    var api_group = app.group("/api");
    _ = api_group.get("/users", testHandler);
    _ = api_group.post("/users", testHandler);
    _ = api_group.get("/users/:id", userHandler);

    var v1_group = api_group.group("/v1");
    _ = v1_group.get("/posts", testHandler);
    _ = v1_group.get("/posts/:id", testHandler);

    // Test that grouped routes are accessible
    try testing.expect(app.findRoute(.GET, "/api/users") != null);
    try testing.expect(app.findRoute(.POST, "/api/users") != null);
    try testing.expect(app.findRoute(.GET, "/api/users/123") != null);
    try testing.expect(app.findRoute(.GET, "/api/v1/posts") != null);
    try testing.expect(app.findRoute(.GET, "/api/v1/posts/456") != null);
}

test "Route middleware attachment" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Test middleware function
    const authMiddleware = struct {
        fn middleware(event: *h3.Event, next: h3.NextFunction) !void {
            // Add auth header for testing
            try event.response.setHeader("X-Auth", "middleware-applied");
            try next(event);
        }
    }.middleware;

    // Register route with middleware
    _ = app.get("/protected", testHandler).use(authMiddleware);
    _ = app.get("/public", testHandler);

    // Test that middleware is attached to the correct route
    const protected_route = app.findRoute(.GET, "/protected");
    try testing.expect(protected_route != null);
    try testing.expect(protected_route.?.middleware.len > 0);

    const public_route = app.findRoute(.GET, "/public");
    try testing.expect(public_route != null);
    try testing.expect(public_route.?.middleware.len == 0);
}

test "Route performance with many routes" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Register many routes
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const path = try std.fmt.allocPrint(allocator, "/route{}", .{i});
        defer allocator.free(path);
        _ = app.get(path, testHandler);
    }

    // Test route lookup performance
    const lookup_func = struct {
        fn lookup(app_ptr: *h3.H3) ?*h3.Route {
            return app_ptr.findRoute(.GET, "/route500");
        }
    }.lookup;

    const benchmark = try test_utils.perf.benchmark(lookup_func, .{&app}, 1000);

    // Route lookup performance check
    try testing.expect(benchmark.avg_duration_ns < 1_000_000); // 1ms

    std.log.info("Route lookup benchmark: avg={}ns, min={}ns, max={}ns", .{
        benchmark.avg_duration_ns,
        benchmark.min_ns,
        benchmark.max_ns,
    });
}
