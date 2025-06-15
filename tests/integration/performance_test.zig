//! Performance tests for H3 framework
//! Tests basic performance characteristics and memory usage

const std = @import("std");
const testing = std.testing;
const h3 = @import("h3");
const test_utils = @import("test_utils");

fn simpleHandler(event: *h3.Event) !void {
    try h3.sendText(event, "OK");
}

fn jsonHandler(event: *h3.Event) !void {
    const data = .{
        .message = "Hello",
        .status = "success",
        .code = 200,
    };
    try h3.sendJson(event, data);
}

test "App creation performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = h3.createApp(allocator);
    defer app.deinit();

    try testing.expect(app.getRouteCount() == 0);
}

test "Route registration performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.get("/", simpleHandler);
    _ = app.get("/api/users", jsonHandler);
    _ = app.post("/api/users", jsonHandler);
    _ = app.get("/users/:id", simpleHandler);

    try testing.expect(app.getRouteCount() == 4);
}

test "Route lookup performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.get("/test", simpleHandler);

    const route = app.findRoute(.GET, "/test");
    try testing.expect(route != null);
}

test "Event creation performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event = h3.Event.init(allocator);
    defer event.deinit();

    try testing.expectEqual(h3.HttpMethod.GET, event.request.method);
}

test "Mock request performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var request = test_utils.MockRequest.init(allocator);
    defer request.deinit();

    _ = request.method(.GET).path("/test");
    const event = request.build();

    try testing.expectEqual(h3.HttpMethod.GET, event.request.method);
    try testing.expectEqualStrings("/test", event.request.path);
}

test "Handler execution performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.get("/test", simpleHandler);

    var request = test_utils.MockRequest.init(allocator);
    defer request.deinit();

    _ = request.method(.GET).path("/test");
    const event = request.build();

    const route = app.findRoute(.GET, "/test");
    if (route) |r| {
        try r.handler(event);
    }

    try testing.expectEqualStrings("OK", event.response.body.?);
}

test "JSON response performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.get("/json", jsonHandler);

    var request = test_utils.MockRequest.init(allocator);
    defer request.deinit();

    _ = request.method(.GET).path("/json");
    const event = request.build();

    const route = app.findRoute(.GET, "/json");
    if (route) |r| {
        try r.handler(event);
    }

    try testing.expect(event.response.body != null);
    try testing.expect(event.response.body.?.len > 0);
    try testing.expectEqualStrings("application/json", event.response.getHeader("Content-Type").?);
}

test "Memory allocation patterns" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = h3.createApp(allocator);
    defer app.deinit();

    _ = app.get("/memory", simpleHandler);

    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        var request = test_utils.MockRequest.init(allocator);
        defer request.deinit();

        _ = request.method(.GET).path("/memory");
        const event = request.build();

        const route = app.findRoute(.GET, "/memory");
        if (route) |r| {
            try r.handler(event);
        }
    }
}
