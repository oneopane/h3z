//! HTTP request representation

const std = @import("std");
const HttpMethod = @import("method.zig").HttpMethod;
const Headers = @import("headers.zig").Headers;

/// HTTP request structure
pub const Request = struct {
    /// HTTP method
    method: HttpMethod,

    /// Full URL including query string
    url: []const u8,

    /// Path component of the URL
    path: []const u8,

    /// Query string (without the '?')
    query: ?[]const u8,

    /// HTTP headers
    headers: Headers,

    /// Request body - owned by the Request object if set via setBody
    body: ?[]u8,

    /// HTTP version (e.g., "1.1", "2.0")
    version: []const u8,

    /// Allocator used for dynamic allocations
    allocator: std.mem.Allocator,

    /// Initialize a new request
    pub fn init(allocator: std.mem.Allocator) Request {
        return Request{
            .method = .GET,
            .url = "",
            .path = "",
            .query = null,
            .headers = Headers.init(allocator),
            .body = null,
            .version = "1.1",
            .allocator = allocator,
        };
    }

    /// Deinitialize the request and free resources
    /// This function ensures that any owned memory, like the request body, is freed.
    pub fn deinit(self: *Request) void {
        if (self.body) |b| {
            // Only free if the body was allocated by this request's allocator
            // This assumes setBody was used, which duplicates the input slice.
            // If body is set externally as a const slice, it should not be freed here.
            // To make this safer, we could add a flag indicating if body is owned.
            // For now, we assume if self.body is not null, it was allocated by self.allocator.dupe
            self.allocator.free(b);
            self.body = null; // Avoid double free on subsequent deinit calls
        }
        self.headers.deinit();
    }

    /// Reset the request for reuse in object pool
    /// This function resets the request state and frees the body if it's owned.
    pub fn reset(self: *Request) void {
        self.method = .GET;
        self.url = "";
        self.path = "";
        self.query = null;
        if (self.body) |b| {
            self.allocator.free(b);
            self.body = null;
        }
        self.headers.clearRetainingCapacity();
    }

    /// Set the request body, taking ownership of the data by copying it.
    /// If a body already exists, it will be freed before setting the new one.
    pub fn setBody(self: *Request, body_data: []const u8) !void {
        // Free existing body if any
        if (self.body) |old_b| {
            self.allocator.free(old_b);
            self.body = null;
        }
        // Duplicate the incoming body data
        self.body = try self.allocator.dupe(u8, body_data);
    }

    /// Parse URL into path and query components
    pub fn parseUrl(self: *Request, url: []const u8) !void {
        self.url = url;

        if (std.mem.indexOf(u8, url, "?")) |query_start| {
            self.path = url[0..query_start];
            self.query = url[query_start + 1 ..];
        } else {
            self.path = url;
            self.query = null;
        }
    }

    /// Get a header value by name (case-insensitive)
    pub fn getHeader(self: *const Request, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// Set a header value
    pub fn setHeader(self: *Request, name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }

    /// Check if request has a specific header
    pub fn hasHeader(self: *const Request, name: []const u8) bool {
        return self.headers.contains(name);
    }

    /// Get Content-Type header
    pub fn getContentType(self: *const Request) ?[]const u8 {
        return self.getHeader("content-type");
    }

    /// Get Content-Length header as integer
    pub fn getContentLength(self: *const Request) ?usize {
        if (self.getHeader("content-length")) |length_str| {
            return std.fmt.parseInt(usize, length_str, 10) catch null;
        }
        return null;
    }

    /// Check if request expects JSON response
    pub fn acceptsJson(self: *const Request) bool {
        if (self.getHeader("accept")) |accept| {
            return std.mem.indexOf(u8, accept, "application/json") != null;
        }
        return false;
    }

    /// Check if request has JSON content type
    pub fn isJson(self: *const Request) bool {
        if (self.getContentType()) |content_type| {
            return std.mem.startsWith(u8, content_type, "application/json");
        }
        return false;
    }

    /// Check if request has form data content type
    pub fn isForm(self: *const Request) bool {
        if (self.getContentType()) |content_type| {
            return std.mem.startsWith(u8, content_type, "application/x-www-form-urlencoded") or
                std.mem.startsWith(u8, content_type, "multipart/form-data");
        }
        return false;
    }

    /// Get User-Agent header
    pub fn getUserAgent(self: *const Request) ?[]const u8 {
        return self.getHeader("user-agent");
    }

    /// Get Authorization header
    pub fn getAuthorization(self: *const Request) ?[]const u8 {
        return self.getHeader("authorization");
    }

    /// Check if request is from a secure connection
    pub fn isSecure(self: *const Request) bool {
        // Check for common headers that indicate HTTPS
        if (self.getHeader("x-forwarded-proto")) |proto| {
            return std.mem.eql(u8, proto, "https");
        }
        if (self.getHeader("x-forwarded-ssl")) |ssl| {
            return std.mem.eql(u8, ssl, "on");
        }
        return false;
    }
};

test "Request.init and deinit" {
    var request = Request.init(std.testing.allocator);
    defer request.deinit();

    try std.testing.expectEqual(HttpMethod.GET, request.method);
    try std.testing.expectEqualStrings("", request.path);
    try std.testing.expectEqual(@as(?[]const u8, null), request.query);
}

test "Request.parseUrl" {
    var request = Request.init(std.testing.allocator);
    defer request.deinit();

    try request.parseUrl("/api/users?page=1&limit=10");
    try std.testing.expectEqualStrings("/api/users", request.path);
    try std.testing.expectEqualStrings("page=1&limit=10", request.query.?);

    try request.parseUrl("/api/users");
    try std.testing.expectEqualStrings("/api/users", request.path);
    try std.testing.expectEqual(@as(?[]const u8, null), request.query);
}

test "Request.headers" {
    var request = Request.init(std.testing.allocator);
    defer request.deinit();

    try request.setHeader("content-type", "application/json");
    try std.testing.expectEqualStrings("application/json", request.getHeader("content-type").?);
    try std.testing.expect(request.hasHeader("content-type"));
    try std.testing.expect(!request.hasHeader("authorization"));
}

test "Request.content type checks" {
    var request = Request.init(std.testing.allocator);
    defer request.deinit();

    try request.setHeader("content-type", "application/json");
    try std.testing.expect(request.isJson());
    try std.testing.expect(!request.isForm());

    try request.setHeader("content-type", "application/x-www-form-urlencoded");
    try std.testing.expect(!request.isJson());
    try std.testing.expect(request.isForm());
}
