//! Unit tests for H3 HTTP module
//! Tests HTTP methods, status codes, headers, and request/response handling

const std = @import("std");
const testing = std.testing;
const h3 = @import("h3");
const test_utils = @import("test_utils");

test "HTTP method enum and string conversion" {
    // Test all HTTP methods
    try testing.expectEqualStrings("GET", @tagName(h3.HttpMethod.GET));
    try testing.expectEqualStrings("POST", @tagName(h3.HttpMethod.POST));
    try testing.expectEqualStrings("PUT", @tagName(h3.HttpMethod.PUT));
    try testing.expectEqualStrings("DELETE", @tagName(h3.HttpMethod.DELETE));
    try testing.expectEqualStrings("PATCH", @tagName(h3.HttpMethod.PATCH));
    try testing.expectEqualStrings("HEAD", @tagName(h3.HttpMethod.HEAD));
    try testing.expectEqualStrings("OPTIONS", @tagName(h3.HttpMethod.OPTIONS));
}

test "HTTP status code values" {
    // Test common status codes
    try testing.expectEqual(@as(u16, 200), @intFromEnum(h3.HttpStatus.ok));
    try testing.expectEqual(@as(u16, 201), @intFromEnum(h3.HttpStatus.created));
    try testing.expectEqual(@as(u16, 204), @intFromEnum(h3.HttpStatus.no_content));
    try testing.expectEqual(@as(u16, 301), @intFromEnum(h3.HttpStatus.moved_permanently));
    try testing.expectEqual(@as(u16, 302), @intFromEnum(h3.HttpStatus.found));
    try testing.expectEqual(@as(u16, 400), @intFromEnum(h3.HttpStatus.bad_request));
    try testing.expectEqual(@as(u16, 401), @intFromEnum(h3.HttpStatus.unauthorized));
    try testing.expectEqual(@as(u16, 403), @intFromEnum(h3.HttpStatus.forbidden));
    try testing.expectEqual(@as(u16, 404), @intFromEnum(h3.HttpStatus.not_found));
    try testing.expectEqual(@as(u16, 500), @intFromEnum(h3.HttpStatus.internal_server_error));
}

test "HTTP request parsing - simple GET" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    const request_data = "GET /api/users HTTP/1.1\r\nHost: localhost:3000\r\nUser-Agent: test-client\r\n\r\n";

    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Parse the request (this would normally be done by the server adapter)
    try parseHttpRequest(&event, request_data);

    try testing.expectEqual(h3.HttpMethod.GET, event.request.method);
    try testing.expectEqualStrings("/api/users", event.request.path);
    try testing.expectEqualStrings("localhost:3000", event.getHeader("Host").?);
    try testing.expectEqualStrings("test-client", event.getHeader("User-Agent").?);
}

test "HTTP request parsing - POST with body" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    const request_data =
        \\POST /api/users HTTP/1.1
        \\Host: localhost:3000
        \\Content-Type: application/json
        \\Content-Length: 35
        \\
        \\{"name":"John","email":"john@test.com"}
    ;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    try parseHttpRequest(&event, request_data);

    try testing.expectEqual(h3.HttpMethod.POST, event.request.method);
    try testing.expectEqualStrings("/api/users", event.request.path);
    try testing.expectEqualStrings("application/json", event.getHeader("Content-Type").?);
    try testing.expectEqualStrings("35", event.getHeader("Content-Length").?);
    try testing.expectEqualStrings("{\"name\":\"John\",\"email\":\"john@test.com\"}", event.request.body.?);
}

test "HTTP request parsing - with query parameters" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    const request_data = "GET /api/users?page=1&limit=10&sort=name HTTP/1.1\r\nHost: localhost:3000\r\n\r\n";

    var event = h3.Event.init(allocator);
    defer event.deinit();

    try parseHttpRequest(&event, request_data);

    try testing.expectEqual(h3.HttpMethod.GET, event.request.method);
    try testing.expectEqualStrings("/api/users", event.request.path);
    try testing.expectEqualStrings("page=1&limit=10&sort=name", event.request.query.?);

    // Parse query parameters
    try event.parseQuery();
    try testing.expectEqualStrings("1", event.getQuery("page").?);
    try testing.expectEqualStrings("10", event.getQuery("limit").?);
    try testing.expectEqualStrings("name", event.getQuery("sort").?);
}

test "HTTP response formatting" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Set up response
    event.response.status = .created;
    try event.response.setHeader("Content-Type", "application/json");
    try event.response.setHeader("X-Custom-Header", "test-value");
    event.response.body = "{\"id\":123,\"name\":\"John\"}";

    // Format response
    const response_str = try formatHttpResponse(allocator, &event);
    defer allocator.free(response_str);

    // Check response format
    try test_utils.assert.expectBodyContains(response_str, "HTTP/1.1 201 Created");
    try test_utils.assert.expectBodyContains(response_str, "Content-Type: application/json");
    try test_utils.assert.expectBodyContains(response_str, "X-Custom-Header: test-value");
    try test_utils.assert.expectBodyContains(response_str, "{\"id\":123,\"name\":\"John\"}");
}

test "HTTP header case-insensitive operations" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Set headers with different cases
    try event.request.setHeader("Content-Type", "application/json");
    try event.request.setHeader("AUTHORIZATION", "Bearer token123");
    try event.request.setHeader("x-custom-header", "custom-value");

    // Test case-insensitive retrieval
    try testing.expectEqualStrings("application/json", event.getHeader("content-type").?);
    try testing.expectEqualStrings("application/json", event.getHeader("Content-Type").?);
    try testing.expectEqualStrings("application/json", event.getHeader("CONTENT-TYPE").?);

    try testing.expectEqualStrings("Bearer token123", event.getHeader("authorization").?);
    try testing.expectEqualStrings("Bearer token123", event.getHeader("Authorization").?);

    try testing.expectEqualStrings("custom-value", event.getHeader("X-Custom-Header").?);
    try testing.expectEqualStrings("custom-value", event.getHeader("x-custom-header").?);
}

test "URL encoding and decoding" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    // Test URL encoding
    const original = "Hello World! @#$%";
    const encoded = try h3.urlEncode(allocator, original);
    defer allocator.free(encoded);

    try testing.expectEqualStrings("Hello%20World%21%20%40%23%24%25", encoded);

    // Test URL decoding
    const decoded = try h3.urlDecode(allocator, encoded);
    defer allocator.free(decoded);

    try testing.expectEqualStrings(original, decoded);
}

test "Query parameter parsing edge cases" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var event = h3.Event.init(allocator);
    defer event.deinit();

    // Test empty query
    event.request.query = "";
    try event.parseQuery();
    try testing.expect(event.getQuery("anything") == null);

    // Test single parameter
    event.request.query = "name=John";
    try event.parseQuery();
    try testing.expectEqualStrings("John", event.getQuery("name").?);

    // Test parameter without value
    event.request.query = "flag&name=John&empty=";
    try event.parseQuery();
    try testing.expectEqualStrings("", event.getQuery("flag").?);
    try testing.expectEqualStrings("John", event.getQuery("name").?);
    try testing.expectEqualStrings("", event.getQuery("empty").?);

    // Test URL encoded values
    event.request.query = "message=Hello%20World&email=test%40example.com";
    try event.parseQuery();
    try testing.expectEqualStrings("Hello World", event.getQuery("message").?);
    try testing.expectEqualStrings("test@example.com", event.getQuery("email").?);
}

test "Content-Type parsing" {
    // Test MIME type detection
    try testing.expectEqualStrings("text/html", h3.getMimeType(".html"));
    try testing.expectEqualStrings("application/json", h3.getMimeType(".json"));
    try testing.expectEqualStrings("text/css", h3.getMimeType(".css"));
    try testing.expectEqualStrings("application/javascript", h3.getMimeType(".js"));
    try testing.expectEqualStrings("image/png", h3.getMimeType(".png"));
    try testing.expectEqualStrings("image/jpeg", h3.getMimeType(".jpg"));
    try testing.expectEqualStrings("application/octet-stream", h3.getMimeType(".unknown"));
}

test "HTTP method validation" {
    // Test method parsing from string
    try testing.expectEqual(h3.HttpMethod.GET, h3.parseHttpMethod("GET"));
    try testing.expectEqual(h3.HttpMethod.POST, h3.parseHttpMethod("POST"));
    try testing.expectEqual(h3.HttpMethod.PUT, h3.parseHttpMethod("PUT"));
    try testing.expectEqual(h3.HttpMethod.DELETE, h3.parseHttpMethod("DELETE"));
    try testing.expectEqual(h3.HttpMethod.PATCH, h3.parseHttpMethod("PATCH"));
    try testing.expectEqual(h3.HttpMethod.HEAD, h3.parseHttpMethod("HEAD"));
    try testing.expectEqual(h3.HttpMethod.OPTIONS, h3.parseHttpMethod("OPTIONS"));

    // Test invalid method
    try testing.expectError(error.InvalidMethod, h3.parseHttpMethod("INVALID"));
}

// Helper functions for testing (these would normally be in the HTTP module)
fn parseHttpRequest(event: *h3.Event, request_data: []const u8) !void {
    // Simple HTTP request parser for testing
    var lines = std.mem.split(u8, request_data, "\r\n");

    // Parse request line
    if (lines.next()) |request_line| {
        var parts = std.mem.split(u8, request_line, " ");

        // Method
        if (parts.next()) |method_str| {
            event.request.method = h3.parseHttpMethod(method_str) catch .GET;
        }

        // Path and query
        if (parts.next()) |url| {
            if (std.mem.indexOf(u8, url, "?")) |query_start| {
                event.request.path = url[0..query_start];
                event.request.query = url[query_start + 1 ..];
            } else {
                event.request.path = url;
            }
        }
    }

    // Parse headers
    while (lines.next()) |line| {
        if (line.len == 0) break; // Empty line indicates end of headers

        if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
            const name = line[0..colon_pos];
            const value = line[colon_pos + 2 ..];
            try event.request.setHeader(name, value);
        }
    }

    // Parse body (everything after empty line)
    if (lines.rest.len > 0) {
        event.request.body = lines.rest;
    }
}

fn formatHttpResponse(allocator: std.mem.Allocator, event: *h3.Event) ![]u8 {
    var response = std.ArrayList(u8).init(allocator);
    defer response.deinit();

    // Status line
    try response.writer().print("HTTP/1.1 {} {s}\r\n", .{ @intFromEnum(event.response.status), getStatusText(event.response.status) });

    // Headers
    var header_iter = event.response.headers.iterator();
    while (header_iter.next()) |entry| {
        try response.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    // Empty line
    try response.appendSlice("\r\n");

    // Body
    if (event.response.body) |body| {
        try response.appendSlice(body);
    }

    return response.toOwnedSlice();
}

fn getStatusText(status: h3.HttpStatus) []const u8 {
    return switch (status) {
        .ok => "OK",
        .created => "Created",
        .no_content => "No Content",
        .moved_permanently => "Moved Permanently",
        .found => "Found",
        .bad_request => "Bad Request",
        .unauthorized => "Unauthorized",
        .forbidden => "Forbidden",
        .not_found => "Not Found",
        .internal_server_error => "Internal Server Error",
        else => "Unknown",
    };
}
