//! Unit tests for H3 core functionality
//! Tests app creation, event handling, and basic operations

const std = @import("std");
const testing = std.testing;
const h3 = @import("h3");
const test_utils = @import("test_utils");

test "H3 app creation and cleanup" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    // Test app creation
    var app = try h3.createApp(allocator);
    defer app.deinit();

    // App initialized correctly
    // Note: getRouteCount() method doesn't exist in current H3 implementation
    // We can check middlewares instead
    try testing.expect(app.middlewares.items.len == 0);
}

test "H3 event creation and basic operations" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    // Test event creation
    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Test basic properties
    try testing.expectEqual(h3.HttpMethod.GET, event.request.method);
    try testing.expectEqualStrings("", event.request.path); // Empty path by default
    try testing.expectEqual(@as(?[]const u8, null), event.request.query);
    try testing.expectEqual(@as(?[]const u8, null), event.request.body);
}

test "H3 event header operations" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Test setting headers
    try event.request.setHeader("Content-Type", "application/json");
    try event.request.setHeader("Authorization", "Bearer token123");

    // Test getting headers
    try testing.expectEqualStrings("application/json", event.getHeader("Content-Type").?);
    try testing.expectEqualStrings("Bearer token123", event.getHeader("Authorization").?);
    try testing.expect(event.getHeader("Non-Existent") == null);

    // Test case-insensitive header access
    try testing.expectEqualStrings("application/json", event.getHeader("content-type").?);
    try testing.expectEqualStrings("Bearer token123", event.getHeader("AUTHORIZATION").?);
}

test "H3 event query parameter parsing" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Set query string
    event.request.query = "name=John&age=30&city=New%20York";
    try event.parseQuery();

    // Test getting query parameters
    try testing.expectEqualStrings("John", event.getQuery("name").?);
    try testing.expectEqualStrings("30", event.getQuery("age").?);
    try testing.expectEqualStrings("New York", event.getQuery("city").?);
    try testing.expect(event.getQuery("non-existent") == null);
}

test "H3 event path parameter operations" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Test setting path parameters (simulating router behavior)
    try event.setParam("id", "123");
    try event.setParam("name", "john");

    // Test getting path parameters
    try testing.expectEqualStrings("123", event.getParam("id").?);
    try testing.expectEqualStrings("john", event.getParam("name").?);
    try testing.expect(event.getParam("non-existent") == null);
}

test "H3 response operations" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Test setting response status
    event.response.status = .created;
    try testing.expectEqual(h3.HttpStatus.created, event.response.status);

    // Test setting response headers
    try event.response.setHeader("Content-Type", "application/json");
    try event.response.setHeader("X-Custom-Header", "custom-value");

    // Test response body
    event.response.body = "Hello, World!";
    try testing.expectEqualStrings("Hello, World!", event.response.body.?);
}

test "H3 JSON response helper" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Test JSON response
    const data = .{
        .message = "Hello",
        .status = "success",
        .code = 200,
    };

    try h3.sendJson(&event, data);

    // Check response properties
    try testing.expectEqual(h3.HttpStatus.ok, event.response.status);
    try testing.expectEqualStrings("application/json", event.response.getHeader("Content-Type").?);

    // Check JSON content (basic validation)
    const body = event.response.body.?;
    try test_utils.assert.expectBodyContains(body, "\"message\":\"Hello\"");
    try test_utils.assert.expectBodyContains(body, "\"status\":\"success\"");
    try test_utils.assert.expectBodyContains(body, "\"code\":200");
}

test "H3 HTML response helper" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    const html = "<html><body><h1>Hello, World!</h1></body></html>";
    try h3.sendHtml(&event, html);

    // Check response properties
    try testing.expectEqual(h3.HttpStatus.ok, event.response.status);
    try testing.expectEqualStrings("text/html", event.response.getHeader("Content-Type").?);
    try testing.expectEqualStrings(html, event.response.body.?);
}

test "H3 text response helper" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    const text = "Hello, World!";
    try h3.sendText(&event, text);

    // Check response properties
    try testing.expectEqual(h3.HttpStatus.ok, event.response.status);
    try testing.expectEqualStrings("text/plain", event.response.getHeader("Content-Type").?);
    try testing.expectEqualStrings(text, event.response.body.?);
}

test "H3 error response helper" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    try h3.sendError(&event, .not_found, "Resource not found");

    // Check response properties
    try testing.expectEqual(h3.HttpStatus.not_found, event.response.status);
    try testing.expectEqualStrings("application/json", event.response.getHeader("Content-Type").?);

    const body = event.response.body.?;
    try test_utils.assert.expectBodyContains(body, "\"error\":");
    try test_utils.assert.expectBodyContains(body, "\"message\":\"Resource not found\"");
}

test "H3 redirect response helper" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    try h3.redirect(&event, "/new-location", .moved_permanently);

    // Check response properties
    try testing.expectEqual(h3.HttpStatus.moved_permanently, event.response.status);
    try testing.expectEqualStrings("/new-location", event.response.getHeader("Location").?);
}

test "Mock request builder" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var mock_req = test_utils.MockRequest.init(allocator);
    defer mock_req.deinit();

    // Build a mock request
    _ = mock_req
        .method(.POST)
        .path("/api/users")
        .query("page", "1")
        .query("limit", "10")
        .header("Content-Type", "application/json")
        .body("{\"name\":\"John\",\"email\":\"john@example.com\"}");

    // Convert to event and test
    var event = mock_req.build();
    // Note: event is owned by mock_req, so we don't deinit it separately

    try testing.expectEqual(h3.HttpMethod.POST, event.request.method);
    try testing.expectEqualStrings("/api/users", event.request.path);
    try testing.expectEqualStrings("page=1&limit=10", event.request.query.?);
    try testing.expectEqualStrings("application/json", event.getHeader("Content-Type").?);
    try testing.expectEqualStrings("{\"name\":\"John\",\"email\":\"john@example.com\"}", event.request.body.?);
}

test "Performance measurement utilities" {
    // Test a simple function
    const testFunc = struct {
        fn add(a: i32, b: i32) i32 {
            return a + b;
        }
    }.add;

    // Measure single execution
    const measurement = try test_utils.perf.measureTime(testFunc, .{ 5, 3 });
    try testing.expectEqual(@as(i32, 8), measurement.result);
    try testing.expect(measurement.duration_ns > 0);

    // Benchmark multiple executions
    const benchmark = try test_utils.perf.benchmark(testFunc, .{ 10, 20 }, 100);
    try testing.expect(benchmark.avg_duration_ns > 0);
    try testing.expect(benchmark.min_ns <= benchmark.avg_duration_ns);
    try testing.expect(benchmark.avg_duration_ns <= benchmark.max_ns);
}
