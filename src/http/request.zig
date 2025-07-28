//! HTTP request representation

const std = @import("std");
const HttpMethod = @import("method.zig").HttpMethod;
const Headers = @import("headers.zig").Headers;
const url_utils = @import("../internal/url.zig");
const body_utils = @import("../utils/body.zig");

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
        // Free body memory
        if (self.body) |b| {
            self.allocator.free(b);
            self.body = null; // Avoid double free in subsequent deinit calls
        }

        // Free path memory (if not a static string)
        if (self.path.len > 0 and !std.mem.eql(u8, self.path, "/") and !std.mem.eql(u8, self.path, "")) {
            self.allocator.free(self.path);
        }

        // Free query memory
        if (self.query) |q| {
            self.allocator.free(q);
            self.query = null;
        }

        // Free headers
        self.headers.deinit();
    }

    /// Reset the request for reuse in object pool
    /// This function resets the request state and frees all allocated memory.
    pub fn reset(self: *Request) void {
        self.method = .GET;
        self.url = "";

        // Free body memory
        if (self.body) |b| {
            self.allocator.free(b);
            self.body = null;
        }

        // Free path memory (if not a static string)
        if (self.path.len > 0 and !std.mem.eql(u8, self.path, "/") and !std.mem.eql(u8, self.path, "")) {
            self.allocator.free(self.path);
            // Set to empty string immediately after freeing
        }
        self.path = "";

        // Free query memory
        if (self.query) |q| {
            self.allocator.free(q);
            self.query = null;
        }

        // Safely free all header key-value pairs
        var keys = std.ArrayList([]const u8).init(self.allocator);
        var values = std.ArrayList([]const u8).init(self.allocator);
        defer keys.deinit();
        defer values.deinit();

        // Collect all key-value pairs
        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            keys.append(entry.key_ptr.*) catch continue;
            values.append(entry.value_ptr.*) catch continue;
        }

        // Clear the hash map
        self.headers.clearRetainingCapacity();

        // Free all collected key-value pairs
        for (keys.items) |key| {
            self.allocator.free(key);
        }
        for (values.items) |value| {
            self.allocator.free(value);
        }
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
    /// This function properly handles URL-encoded characters
    pub fn parseUrl(self: *Request, url: []const u8) !void {
        // Free previous path if it exists and is not a static string
        if (self.path.len > 0 and !std.mem.eql(u8, self.path, "/")) {
            self.allocator.free(self.path);
        }

        // Free previous query if it exists
        if (self.query) |q| {
            self.allocator.free(q);
            self.query = null;
        }

        // Store the original URL
        self.url = url;

        // Try to use std.Uri.parse for robust URL parsing
        if (std.Uri.parse(url)) |parsed_uri| {
            // Handle path component based on its type
            if (parsed_uri.path == .percent_encoded) {
                const path_encoded = parsed_uri.path.percent_encoded;
                // Decode the path to handle URL-encoded characters
                const decoded_path = try url_utils.urlDecode(self.allocator, path_encoded);
                self.path = decoded_path;
            } else if (parsed_uri.path == .raw) {
                const raw_path = parsed_uri.path.raw;
                // For root path, use static string directly
                if (std.mem.eql(u8, raw_path, "/")) {
                    self.path = "/";
                } else {
                    // Check if the path contains URL encoded characters
                    if (std.mem.indexOf(u8, raw_path, "%")) |_| {
                        // If it contains percent signs, it might be URL encoded, decode it
                        const decoded_path = try url_utils.urlDecode(self.allocator, raw_path);
                        self.path = decoded_path;
                    } else {
                        self.path = try self.allocator.dupe(u8, raw_path);
                    }
                }
            } else {
                // For root path, use static string
                self.path = "/";
            }

            // Handle query component based on its type
            if (parsed_uri.query != null) {
                const query = switch (parsed_uri.query.?) {
                    .percent_encoded => |q| q,
                    .raw => |q| q,
                };
                // Store the raw query string (still encoded)
                self.query = try self.allocator.dupe(u8, query);
            } else {
                self.query = null;
            }
        } else |_| {
            // Fallback to simple parsing if std.Uri.parse fails
            if (std.mem.indexOf(u8, url, "?")) |query_start| {
                // For root path, use static string directly
                if (query_start == 1 and url[0] == '/') {
                    self.path = "/";
                } else {
                    const path_part = url[0..query_start];
                    // Check if the path contains URL encoded characters
                    if (std.mem.indexOf(u8, path_part, "%")) |_| {
                        // If it contains percent signs, it might be URL encoded, decode it
                        const decoded_path = try url_utils.urlDecode(self.allocator, path_part);
                        self.path = decoded_path;
                    } else {
                        self.path = try self.allocator.dupe(u8, path_part);
                    }
                }
                self.query = try self.allocator.dupe(u8, url[query_start + 1 ..]);
            } else {
                // For root path, use static string directly
                if (std.mem.eql(u8, url, "/")) {
                    self.path = "/";
                } else {
                    // Check if the path contains URL encoded characters
                    if (std.mem.indexOf(u8, url, "%")) |_| {
                        // If it contains percent signs, it might be URL encoded, decode it
                        const decoded_path = try url_utils.urlDecode(self.allocator, url);
                        self.path = decoded_path;
                    } else {
                        self.path = try self.allocator.dupe(u8, url);
                    }
                }
                self.query = null;
            }
        }
    }

    /// Get a header value by name (case-insensitive)
    pub fn getHeader(self: *const Request, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// Set a header value
    pub fn setHeader(self: *Request, name: []const u8, value: []const u8) !void {
        // Check if header already exists and free old memory
        if (self.headers.getEntry(name)) |existing| {
            self.allocator.free(existing.key_ptr.*);
            self.allocator.free(existing.value_ptr.*);
            _ = self.headers.remove(name);
        }
        
        // Create copies of name and value to ensure they persist
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        
        try self.headers.put(name_copy, value_copy);
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

    // Test with URL-encoded characters
    try request.parseUrl("/api/users/John%20Doe?query=Hello%20World");
    try std.testing.expectEqualStrings("/api/users/John Doe", request.path);
    try std.testing.expectEqualStrings("query=Hello%20World", request.query.?);
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
