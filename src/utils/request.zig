//! Request utility functions
//! Provides helper functions for working with HTTP requests

const std = @import("std");
const H3Event = @import("../core/event.zig").H3Event;

/// Get a path parameter from the request
pub fn getParam(event: *H3Event, name: []const u8) ?[]const u8 {
    return event.getParam(name);
}

/// Get a query parameter from the request
pub fn getQuery(event: *H3Event, name: []const u8) ?[]const u8 {
    return event.getQuery(name);
}

/// Get all query parameters as a map
pub fn getAllQuery(event: *H3Event) std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) {
    return event.request.query;
}

/// Get a request header
pub fn getHeader(event: *H3Event, name: []const u8) ?[]const u8 {
    return event.getHeader(name);
}

/// Get all request headers
pub fn getAllHeaders(event: *H3Event) @import("../http/headers.zig").Headers {
    return event.request.headers;
}

/// Read the request body as text
pub fn readBody(event: *H3Event) ?[]const u8 {
    return event.request.body;
}

/// Read and parse JSON request body
pub fn readJson(event: *H3Event, comptime T: type) !T {
    const body = readBody(event) orelse return error.NoBody;

    const parsed = std.json.parseFromSlice(T, event.allocator, body, .{}) catch |err| {
        std.log.err("Failed to parse JSON: {}", .{err});
        return error.InvalidJson;
    };

    return parsed.value;
}

/// Check if the request has a JSON content type
pub fn isJson(event: *H3Event) bool {
    return event.isJson();
}

/// Get the request method
pub fn getMethod(event: *H3Event) @import("../http/method.zig").HttpMethod {
    return event.getMethod();
}

/// Get the request path
pub fn getPath(event: *H3Event) []const u8 {
    return event.getPath();
}

/// Get the request URL (path + query string)
pub fn getUrl(event: *H3Event) []const u8 {
    return event.request.url;
}

/// Get the HTTP version
pub fn getHttpVersion(event: *H3Event) []const u8 {
    return event.request.version;
}

/// Check if the request accepts a specific content type
pub fn accepts(event: *H3Event, content_type: []const u8) bool {
    const accept_header = getHeader(event, "accept") orelse return false;
    return std.mem.indexOf(u8, accept_header, content_type) != null;
}

/// Check if the request accepts JSON
pub fn acceptsJson(event: *H3Event) bool {
    return accepts(event, "application/json") or accepts(event, "*/*");
}

/// Check if the request accepts HTML
pub fn acceptsHtml(event: *H3Event) bool {
    return accepts(event, "text/html") or accepts(event, "*/*");
}

/// Get the User-Agent header
pub fn getUserAgent(event: *H3Event) ?[]const u8 {
    return getHeader(event, "user-agent");
}

/// Get the Host header
pub fn getHost(event: *H3Event) ?[]const u8 {
    return getHeader(event, "host");
}

/// Get the Referer header
pub fn getReferer(event: *H3Event) ?[]const u8 {
    return getHeader(event, "referer");
}

/// Get the Authorization header
pub fn getAuthorization(event: *H3Event) ?[]const u8 {
    return getHeader(event, "authorization");
}

/// Extract Bearer token from Authorization header
pub fn getBearerToken(event: *H3Event) ?[]const u8 {
    const auth = getAuthorization(event) orelse return null;
    if (std.mem.startsWith(u8, auth, "Bearer ")) {
        return auth[7..]; // Skip "Bearer "
    }
    return null;
}

/// Get the Content-Length header as a number
pub fn getContentLength(event: *H3Event) ?usize {
    const length_str = getHeader(event, "content-length") orelse return null;
    return std.fmt.parseInt(usize, length_str, 10) catch null;
}

/// Check if the request is a specific method
pub fn isMethod(event: *H3Event, method: @import("../http/method.zig").HttpMethod) bool {
    return getMethod(event) == method;
}

/// Check if the request is GET
pub fn isGet(event: *H3Event) bool {
    return isMethod(event, .GET);
}

/// Check if the request is POST
pub fn isPost(event: *H3Event) bool {
    return isMethod(event, .POST);
}

/// Check if the request is PUT
pub fn isPut(event: *H3Event) bool {
    return isMethod(event, .PUT);
}

/// Check if the request is DELETE
pub fn isDelete(event: *H3Event) bool {
    return isMethod(event, .DELETE);
}

/// Check if the request is PATCH
pub fn isPatch(event: *H3Event) bool {
    return isMethod(event, .PATCH);
}

/// Check if the request is OPTIONS
pub fn isOptions(event: *H3Event) bool {
    return isMethod(event, .OPTIONS);
}

/// Parse form data (application/x-www-form-urlencoded)
pub fn parseFormData(event: *H3Event) !std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) {
    const body = readBody(event) orelse return error.NoBody;

    var form_data = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(event.allocator);

    var pairs = std.mem.split(u8, body, "&");
    while (pairs.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
            const key = pair[0..eq_pos];
            const value = pair[eq_pos + 1 ..];
            try form_data.put(key, value);
        }
    }

    return form_data;
}
