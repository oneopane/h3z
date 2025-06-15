//! Integration tests for H3 routing functionality
//! Tests end-to-end routing behavior with real HTTP requests

const std = @import("std");
const testing = std.testing;
const h3 = @import("h3");
const test_utils = @import("test_utils");

// Test handlers
fn homeHandler(event: *h3.Event) !void {
    try h3.sendHtml(event, "<h1>Welcome Home</h1>");
}

fn apiStatusHandler(event: *h3.Event) !void {
    const status = .{
        .status = "ok",
        .version = "1.0.0",
        .timestamp = std.time.timestamp(),
    };
    try h3.sendJson(event, status);
}

fn userHandler(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse "unknown";
    const user = .{
        .id = id,
        .name = "Test User",
        .email = "test@example.com",
    };
    try h3.sendJson(event, user);
}

fn createUserHandler(event: *h3.Event) !void {
    // Simulate user creation
    const body = event.request.body orelse "";
    if (body.len == 0) {
        try h3.sendError(event, .bad_request, "Request body is required");
        return;
    }

    const response = .{
        .id = "123",
        .message = "User created successfully",
        .data = body,
    };
    event.response.status = .created;
    try h3.sendJson(event, response);
}

fn updateUserHandler(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse "unknown";
    const body = event.request.body orelse "";

    const response = .{
        .id = id,
        .message = "User updated successfully",
        .data = body,
    };
    try h3.sendJson(event, response);
}

fn deleteUserHandler(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse "unknown";
    const response = .{
        .id = id,
        .message = "User deleted successfully",
    };
    try h3.sendJson(event, response);
}

fn queryParamsHandler(event: *h3.Event) !void {
    const page = h3.getQuery(event, "page") orelse "1";
    const limit = h3.getQuery(event, "limit") orelse "10";
    const sort = h3.getQuery(event, "sort") orelse "id";

    const response = .{
        .page = page,
        .limit = limit,
        .sort = sort,
        .total = 100,
    };
    try h3.sendJson(event, response);
}

fn wildcardHandler(event: *h3.Event) !void {
    const path = h3.getParam(event, "path") orelse "";
    const response = .{
        .message = "Wildcard route matched",
        .path = path,
    };
    try h3.sendJson(event, response);
}

test "Basic routing integration" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Register routes
    _ = app.get("/", homeHandler);
    _ = app.get("/api/status", apiStatusHandler);
    _ = app.get("/users/:id", userHandler);
    _ = app.post("/users", createUserHandler);
    _ = app.put("/users/:id", updateUserHandler);
    _ = app.delete("/users/:id", deleteUserHandler);

    // Test GET /
    var home_request = test_utils.MockRequest.init(allocator);
    defer home_request.deinit();

    _ = home_request.method(.GET).path("/");
    const home_event = home_request.build();
    // Note: event is owned by home_request, no separate deinit needed

    // Simulate route handling
    const home_route = app.findRoute(.GET, "/");
    try testing.expect(home_route != null);
    try home_route.?.handler(home_event);

    try testing.expectEqual(h3.HttpStatus.ok, home_event.response.status);
    try testing.expectEqualStrings("text/html", home_event.response.getHeader("Content-Type").?);
    try test_utils.assert.expectBodyContains(home_event.response.body, "<h1>Welcome Home</h1>");

    // Test GET /api/status
    var status_request = test_utils.MockRequest.init(allocator);
    defer status_request.deinit();

    _ = status_request.method(.GET).path("/api/status");
    const status_event = status_request.build();

    const status_route = app.findRoute(.GET, "/api/status");
    try testing.expect(status_route != null);
    try status_route.?.handler(status_event);

    try testing.expectEqual(h3.HttpStatus.ok, status_event.response.status);
    try testing.expectEqualStrings("application/json", status_event.response.getHeader("Content-Type").?);
    try test_utils.assert.expectJsonField(status_event.response.body.?, "status", "ok");
}

test "Parameterized routing integration" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.get("/users/:id", userHandler);
    _ = app.put("/users/:id", updateUserHandler);
    _ = app.delete("/users/:id", deleteUserHandler);

    // Test GET /users/123
    var get_request = test_utils.MockRequest.init(allocator);
    defer get_request.deinit();

    _ = get_request.method(.GET).path("/users/123");
    const get_event = get_request.build();

    const get_route = app.findRoute(.GET, "/users/123");
    try testing.expect(get_route != null);
    try app.extractParams(get_event, get_route.?, "/users/123");
    try get_route.?.handler(get_event);

    try testing.expectEqual(h3.HttpStatus.ok, get_event.response.status);
    try test_utils.assert.expectJsonField(get_event.response.body.?, "id", "123");

    // Test PUT /users/456
    var put_request = test_utils.MockRequest.init(allocator);
    defer put_request.deinit();

    _ = put_request.method(.PUT).path("/users/456").body("{\"name\":\"Updated User\"}").header("Content-Type", "application/json");
    const put_event = put_request.build();

    const put_route = app.findRoute(.PUT, "/users/456");
    try testing.expect(put_route != null);
    try app.extractParams(put_event, put_route.?, "/users/456");
    try put_route.?.handler(put_event);

    try testing.expectEqual(h3.HttpStatus.ok, put_event.response.status);
    try test_utils.assert.expectJsonField(put_event.response.body.?, "id", "456");
    try test_utils.assert.expectJsonField(put_event.response.body.?, "message", "User updated successfully");
}

test "POST request with body integration" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.post("/users", createUserHandler);

    // Test POST /users with JSON body
    var post_request = test_utils.MockRequest.init(allocator);
    defer post_request.deinit();

    _ = post_request
        .method(.POST)
        .path("/users")
        .body("{\"name\":\"John Doe\",\"email\":\"john@example.com\"}")
        .header("Content-Type", "application/json");

    const post_event = post_request.build();

    const post_route = app.findRoute(.POST, "/users");
    try testing.expect(post_route != null);
    try post_route.?.handler(post_event);

    try testing.expectEqual(h3.HttpStatus.created, post_event.response.status);
    try test_utils.assert.expectJsonField(post_event.response.body.?, "message", "User created successfully");

    // Test POST /users without body
    var empty_request = test_utils.MockRequest.init(allocator);
    defer empty_request.deinit();

    _ = empty_request.method(.POST).path("/users");
    const empty_event = empty_request.build();

    try post_route.?.handler(empty_event);
    try testing.expectEqual(h3.HttpStatus.bad_request, empty_event.response.status);
}

test "Query parameter handling integration" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.get("/search", queryParamsHandler);

    // Test GET /search with query parameters
    var search_request = test_utils.MockRequest.init(allocator);
    defer search_request.deinit();

    _ = search_request
        .method(.GET)
        .path("/search")
        .query("page", "2")
        .query("limit", "20")
        .query("sort", "name");

    const search_event = search_request.build();

    const search_route = app.findRoute(.GET, "/search");
    try testing.expect(search_route != null);
    try search_route.?.handler(search_event);

    try testing.expectEqual(h3.HttpStatus.ok, search_event.response.status);
    try test_utils.assert.expectJsonField(search_event.response.body.?, "page", "2");
    try test_utils.assert.expectJsonField(search_event.response.body.?, "limit", "20");
    try test_utils.assert.expectJsonField(search_event.response.body.?, "sort", "name");
}

test "Wildcard routing integration" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.get("/files/*path", wildcardHandler);

    // Test wildcard route with nested path
    var wildcard_request = test_utils.MockRequest.init(allocator);
    defer wildcard_request.deinit();

    _ = wildcard_request.method(.GET).path("/files/documents/reports/2023/annual.pdf");
    const wildcard_event = wildcard_request.build();

    const wildcard_route = app.findRoute(.GET, "/files/documents/reports/2023/annual.pdf");
    try testing.expect(wildcard_route != null);
    try app.extractParams(wildcard_event, wildcard_route.?, "/files/documents/reports/2023/annual.pdf");
    try wildcard_route.?.handler(wildcard_event);

    try testing.expectEqual(h3.HttpStatus.ok, wildcard_event.response.status);
    try test_utils.assert.expectJsonField(wildcard_event.response.body.?, "path", "documents/reports/2023/annual.pdf");
}

test "Route not found handling" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.get("/", homeHandler);

    // Test non-existent route
    const missing_route = app.findRoute(.GET, "/nonexistent");
    try testing.expect(missing_route == null);

    // Test wrong method
    const wrong_method = app.findRoute(.POST, "/");
    try testing.expect(wrong_method == null);
}

test "Multiple HTTP methods on same path" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Register multiple methods for same path
    _ = app.get("/api/users", queryParamsHandler);
    _ = app.post("/api/users", createUserHandler);
    _ = app.put("/api/users", updateUserHandler);
    _ = app.delete("/api/users", deleteUserHandler);

    // Test each method
    try testing.expect(app.findRoute(.GET, "/api/users") != null);
    try testing.expect(app.findRoute(.POST, "/api/users") != null);
    try testing.expect(app.findRoute(.PUT, "/api/users") != null);
    try testing.expect(app.findRoute(.DELETE, "/api/users") != null);

    // Test unregistered methods
    try testing.expect(app.findRoute(.PATCH, "/api/users") == null);
    try testing.expect(app.findRoute(.HEAD, "/api/users") == null);
    try testing.expect(app.findRoute(.OPTIONS, "/api/users") == null);
}

test "Complex routing scenarios" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Register complex route patterns
    _ = app.get("/api/v1/users", queryParamsHandler);
    _ = app.get("/api/v1/users/:id", userHandler);
    _ = app.get("/api/v1/users/:user_id/posts/:post_id", wildcardHandler);
    _ = app.get("/static/*path", wildcardHandler);
    _ = app.get("/admin/users/new", homeHandler); // Specific route before parameter route
    _ = app.get("/admin/users/:id", userHandler);

    // Test specific route takes precedence
    const specific_route = app.findRoute(.GET, "/admin/users/new");
    try testing.expect(specific_route != null);

    // Test parameter route
    const param_route = app.findRoute(.GET, "/admin/users/123");
    try testing.expect(param_route != null);

    // Test nested parameters
    var nested_request = test_utils.MockRequest.init(allocator);
    defer nested_request.deinit();

    _ = nested_request.method(.GET).path("/api/v1/users/456/posts/789");
    const nested_event = nested_request.build();

    const nested_route = app.findRoute(.GET, "/api/v1/users/456/posts/789");
    try testing.expect(nested_route != null);
    try app.extractParams(nested_event, nested_route.?, "/api/v1/users/456/posts/789");

    try testing.expectEqualStrings("456", h3.getParam(nested_event, "user_id").?);
    try testing.expectEqualStrings("789", h3.getParam(nested_event, "post_id").?);
}
