//! Request utility functions
//! Provides helper functions for working with HTTP requests

const std = @import("std");
const H3Event = @import("../core/event.zig").H3Event;
const body_utils = @import("../utils/body.zig");
const cookie_utils = @import("../utils/cookie.zig");

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
    errdefer {
        var iter = form_data.iterator();
        while (iter.next()) |entry| {
            event.allocator.free(entry.key_ptr.*);
            event.allocator.free(entry.value_ptr.*);
        }
        form_data.deinit();
    }

    var pairs = std.mem.splitScalar(u8, body, '&');
    while (pairs.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
            const encoded_key = pair[0..eq_pos];
            const encoded_value = pair[eq_pos + 1 ..];

            const key = try @import("../internal/url.zig").urlDecode(event.allocator, encoded_key);
            defer event.allocator.free(key);

            const value = try @import("../internal/url.zig").urlDecode(event.allocator, encoded_value);
            defer event.allocator.free(value);

            // Store the decoded key and value in the form_data map
            const key_dup = try event.allocator.dupe(u8, key);
            errdefer event.allocator.free(key_dup);

            const value_dup = try event.allocator.dupe(u8, value);
            errdefer event.allocator.free(value_dup);

            // If the key already exists, free the old value to avoid memory leaks
            if (form_data.getEntry(key_dup)) |entry| {
                event.allocator.free(entry.key_ptr.*);
                event.allocator.free(entry.value_ptr.*);
            }

            try form_data.put(key_dup, value_dup);
        } else {
            // Handle key without value
            const encoded_key = pair;

            const key = try @import("../internal/url.zig").urlDecode(event.allocator, encoded_key);
            defer event.allocator.free(key);

            const key_dup = try event.allocator.dupe(u8, key);
            errdefer event.allocator.free(key_dup);

            const empty_value = try event.allocator.dupe(u8, "");
            errdefer event.allocator.free(empty_value);

            // If the key already exists, free the old value to avoid memory leaks
            if (form_data.getEntry(key_dup)) |entry| {
                event.allocator.free(entry.key_ptr.*);
                event.allocator.free(entry.value_ptr.*);
            }

            try form_data.put(key_dup, empty_value);
        }
    }

    return form_data;
}

/// Parse multipart form data
pub fn parseMultipartFormData(event: *H3Event) !body_utils.MultipartData {
    return body_utils.BodyParser.parseMultipart(event);
}

/// Get a cookie value by name
pub fn getCookie(event: *H3Event, name: []const u8) ?[]const u8 {
    return cookie_utils.CookieUtils.getCookie(event, name);
}

/// Get all cookies as a map
pub fn getAllCookies(event: *H3Event) !cookie_utils.CookieJar {
    return cookie_utils.CookieUtils.getAllCookies(event);
}

/// Check if the request is an AJAX request
pub fn isAjaxRequest(event: *H3Event) bool {
    const x_requested_with = getHeader(event, "x-requested-with") orelse return false;
    return std.mem.eql(u8, x_requested_with, "XMLHttpRequest");
}

/// Get the client IP address
pub fn getClientIp(event: *H3Event) ?[]const u8 {
    // Try common headers for client IP in order of reliability
    if (getHeader(event, "cf-connecting-ip")) |ip| return ip; // Cloudflare
    if (getHeader(event, "x-real-ip")) |ip| return ip; // Nginx
    if (getHeader(event, "x-forwarded-for")) |forwarded| {
        // X-Forwarded-For can contain multiple IPs, get the first one
        var ips = std.mem.splitScalar(u8, forwarded, ',');
        if (ips.next()) |ip| {
            return std.mem.trim(u8, ip, " ");
        }
    }
    return getHeader(event, "remote-addr"); // Direct connection
}

/// Check if the request content type matches a specific type
pub fn hasContentType(event: *H3Event, content_type: []const u8) bool {
    const ct = getHeader(event, "content-type") orelse return false;
    return std.mem.indexOf(u8, ct, content_type) != null;
}

/// Check if the request is a multipart form data request
pub fn isMultipartFormData(event: *H3Event) bool {
    return hasContentType(event, "multipart/form-data");
}

/// Check if the request is a form urlencoded request
pub fn isFormUrlencoded(event: *H3Event) bool {
    return hasContentType(event, "application/x-www-form-urlencoded");
}

/// Check if the request is a text request
pub fn isTextRequest(event: *H3Event) bool {
    return hasContentType(event, "text/");
}
