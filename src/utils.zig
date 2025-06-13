//! Utility functions for H3 applications

const std = @import("std");
const H3Event = @import("core/event.zig").H3Event;
const HttpStatus = @import("http/status.zig").HttpStatus;
const MimeTypes = @import("http/headers.zig").MimeTypes;

/// Send a plain text response
pub fn send(event: *H3Event, text: []const u8) !void {
    try event.sendText(text);
}

/// Send an HTML response
pub fn sendHtml(event: *H3Event, html: []const u8) !void {
    try event.sendHtml(html);
}

/// Send a JSON response from a string
pub fn sendJson(event: *H3Event, json: []const u8) !void {
    try event.sendJson(json);
}

/// Send a JSON response from a value
pub fn sendJsonValue(event: *H3Event, value: anytype) !void {
    try event.sendJsonValue(value);
}

/// Send a redirect response
pub fn redirect(event: *H3Event, location: []const u8, status: ?HttpStatus) !void {
    try event.redirect(location, status);
}

/// Send a 404 Not Found response
pub fn notFound(event: *H3Event, message: ?[]const u8) !void {
    event.setStatus(.not_found);
    try event.sendText(message orelse "Not Found");
}

/// Send a 400 Bad Request response
pub fn badRequest(event: *H3Event, message: ?[]const u8) !void {
    event.setStatus(.bad_request);
    try event.sendText(message orelse "Bad Request");
}

/// Send a 401 Unauthorized response
pub fn unauthorized(event: *H3Event, message: ?[]const u8) !void {
    event.setStatus(.unauthorized);
    try event.sendText(message orelse "Unauthorized");
}

/// Send a 403 Forbidden response
pub fn forbidden(event: *H3Event, message: ?[]const u8) !void {
    event.setStatus(.forbidden);
    try event.sendText(message orelse "Forbidden");
}

/// Send a 500 Internal Server Error response
pub fn internalServerError(event: *H3Event, message: ?[]const u8) !void {
    event.setStatus(.internal_server_error);
    try event.sendText(message orelse "Internal Server Error");
}

/// Get a request header value
pub fn getHeader(event: *const H3Event, name: []const u8) ?[]const u8 {
    return event.getHeader(name);
}

/// Set a response header
pub fn setHeader(event: *H3Event, name: []const u8, value: []const u8) !void {
    try event.setHeader(name, value);
}

/// Get a query parameter
pub fn getQuery(event: *const H3Event, key: []const u8) ?[]const u8 {
    return event.getQuery(key);
}

/// Get a route parameter
pub fn getParam(event: *const H3Event, key: []const u8) ?[]const u8 {
    return event.getParam(key);
}

/// Read the request body
pub fn readBody(event: *const H3Event) ?[]const u8 {
    return event.readBody();
}

/// Parse JSON from request body
pub fn readJson(event: *const H3Event, comptime T: type) !T {
    return event.readJson(T);
}

/// Set CORS headers with default values
pub fn setCors(event: *H3Event, origin: ?[]const u8) !void {
    try event.setCors(.{
        .origin = origin orelse "*",
        .methods = "GET, POST, PUT, DELETE, PATCH, OPTIONS",
        .headers = "Content-Type, Authorization",
        .credentials = false,
    });
}

/// Set security headers with default values
pub fn setSecurity(event: *H3Event) !void {
    try event.setSecurity(.{
        .hsts = true,
        .nosniff = true,
        .frame_options = "DENY",
        .xss_protection = true,
    });
}

/// Set no-cache headers
pub fn setNoCache(event: *H3Event) !void {
    try event.setNoCache();
}

/// Create a simple logger middleware
pub fn logger(event: *H3Event, app: *@import("core/app.zig").H3, index: usize, final_handler: @import("core/app.zig").Handler) !void {
    const start_time = std.time.milliTimestamp();

    std.log.info("{s} {s}", .{ event.getMethod().toString(), event.getPath() });

    // Call next middleware
    try app.next(event, index, final_handler);

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    std.log.info("{s} {s} {} {}ms", .{ event.getMethod().toString(), event.getPath(), event.response.status.code(), duration });
}

/// Create a CORS middleware
pub fn cors(origin: ?[]const u8) @import("core/app.zig").Middleware {
    return struct {
        fn middleware(event: *H3Event, app: *@import("core/app.zig").H3, index: usize, final_handler: @import("core/app.zig").Handler) !void {
            try setCors(event, origin);

            // Handle preflight requests
            if (event.getMethod() == .OPTIONS) {
                event.setStatus(.no_content);
                return;
            }

            // Call next middleware
            try app.next(event, index, final_handler);
        }
    }.middleware;
}

/// Create a security headers middleware
pub fn security() @import("core/app.zig").Middleware {
    return struct {
        fn middleware(event: *H3Event, app: *@import("core/app.zig").H3, index: usize, final_handler: @import("core/app.zig").Handler) !void {
            try setSecurity(event);
            // Call next middleware
            try app.next(event, index, final_handler);
        }
    }.middleware;
}

/// Create a JSON body parser middleware
pub fn jsonParser() @import("core/app.zig").Middleware {
    return struct {
        fn middleware(event: *H3Event, app: *@import("core/app.zig").H3, index: usize, final_handler: @import("core/app.zig").Handler) !void {
            // Only parse JSON for requests with JSON content type
            if (event.isJson()) {
                // In a real implementation, we'd parse the JSON here
                // and store it in the event context
            }
            // Call next middleware
            try app.next(event, index, final_handler);
        }
    }.middleware;
}

/// URL decode a string (simplified implementation)
pub fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            // Parse hex digits
            const hex_str = encoded[i + 1 .. i + 3];
            if (std.fmt.parseInt(u8, hex_str, 16)) |byte| {
                try result.append(byte);
                i += 3;
            } else |_| {
                try result.append(encoded[i]);
                i += 1;
            }
        } else if (encoded[i] == '+') {
            try result.append(' ');
            i += 1;
        } else {
            try result.append(encoded[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

/// URL encode a string (simplified implementation)
pub fn urlEncode(allocator: std.mem.Allocator, decoded: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (decoded) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~') {
            try result.append(byte);
        } else {
            try result.writer().print("%{X:0>2}", .{byte});
        }
    }

    return result.toOwnedSlice();
}

/// Parse form data from request body
pub fn parseFormData(allocator: std.mem.Allocator, body: []const u8) !std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) {
    var result = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);

    var iter = std.mem.splitSequence(u8, body, "&");
    while (iter.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
            const key = try urlDecode(allocator, pair[0..eq_pos]);
            const value = try urlDecode(allocator, pair[eq_pos + 1 ..]);
            try result.put(key, value);
        }
    }

    return result;
}

test "utils.send" {
    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    try send(&event, "Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", event.response.body.?);
}

test "utils.notFound" {
    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    try notFound(&event, null);
    try std.testing.expectEqual(HttpStatus.not_found, event.response.status);
    try std.testing.expectEqualStrings("Not Found", event.response.body.?);
}

test "utils.urlDecode" {
    const allocator = std.testing.allocator;

    const decoded = try urlDecode(allocator, "Hello%20World%21");
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings("Hello World!", decoded);
}

test "utils.urlEncode" {
    const allocator = std.testing.allocator;

    const encoded = try urlEncode(allocator, "Hello World!");
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings("Hello%20World%21", encoded);
}
