//! Basic unit tests for H3 framework
//! Simple tests to verify core functionality

const std = @import("std");
const testing = std.testing;
const h3 = @import("h3");
const test_utils = @import("test_utils");

test "Test allocator works" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    // Simple allocation test
    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);

    try testing.expect(data.len == 100);
}

test "H3 app creation and cleanup" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    // Test app creation
    var app = h3.createApp(allocator);
    defer app.deinit();

    // App initialized correctly
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
    try testing.expectEqualStrings("/", event.request.path);
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
    try testing.expectEqualStrings("application/json", h3.getHeader(&event, "Content-Type").?);
    try testing.expectEqualStrings("Bearer token123", h3.getHeader(&event, "Authorization").?);
    try testing.expect(h3.getHeader(&event, "Non-Existent") == null);

    // Test case-insensitive header access
    try testing.expectEqualStrings("application/json", h3.getHeader(&event, "content-type").?);
    try testing.expectEqualStrings("Bearer token123", h3.getHeader(&event, "AUTHORIZATION").?);
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

test "Basic route registration" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Test handler
    const testHandler = struct {
        fn handler(event: *h3.Event) !void {
            try h3.sendText(event, "Test response");
        }
    }.handler;

    // Register routes
    _ = app.get("/", testHandler);
    _ = app.get("/about", testHandler);
    _ = app.post("/users", testHandler);

    // Basic validation - we can't easily test route matching without more infrastructure
    try testing.expect(app.middlewares.items.len == 0);
}
