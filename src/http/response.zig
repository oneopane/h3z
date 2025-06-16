//! HTTP response representation

const std = @import("std");
const HttpStatus = @import("status.zig").HttpStatus;
const Headers = @import("headers.zig").Headers;
const HeaderNames = @import("headers.zig").HeaderNames;
const MimeTypes = @import("headers.zig").MimeTypes;

/// HTTP response structure
pub const Response = struct {
    /// HTTP status code
    status: HttpStatus,

    /// HTTP headers
    headers: Headers,

    /// Response body
    body: ?[]const u8,

    /// Whether the body was allocated and needs to be freed
    body_owned: bool,

    /// HTTP version (e.g., "1.1", "2.0")
    version: []const u8,

    /// Whether the response has been sent
    sent: bool,

    /// Whether the response processing is finished
    finished: bool,

    /// Allocator used for dynamic allocations
    allocator: std.mem.Allocator,

    /// Initialize a new response
    pub fn init(allocator: std.mem.Allocator) Response {
        return Response{
            .status = .ok,
            .headers = Headers.init(allocator),
            .body = null,
            .body_owned = false,
            .version = "1.1",
            .sent = false,
            .finished = false,
            .allocator = allocator,
        };
    }

    /// Deinitialize the response and free resources
    pub fn deinit(self: *Response) void {
        // Free all header keys and values
        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();

        // Free body if it was allocated by us
        if (self.body_owned and self.body != null) {
            self.allocator.free(self.body.?);
        }
    }

    /// Reset the response for reuse in object pool
    pub fn reset(self: *Response) void {
        // Free all header keys and values before clearing
        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.clearRetainingCapacity();

        // Free body if it was allocated by us
        if (self.body_owned and self.body != null) {
            self.allocator.free(self.body.?);
        }

        self.status = .ok;
        self.body = null;
        self.body_owned = false;
        self.sent = false;
        self.finished = false;
    }

    /// Set the status code
    pub fn setStatus(self: *Response, status: HttpStatus) void {
        self.status = status;
    }

    /// Set a header value
    pub fn setHeader(self: *Response, name: []const u8, value: []const u8) !void {
        // Check if header already exists and free old memory
        if (self.headers.getEntry(name)) |existing| {
            self.allocator.free(existing.key_ptr.*);
            self.allocator.free(existing.value_ptr.*);
            _ = self.headers.remove(name);
        }

        // Create copies of name and value to ensure they persist
        const name_copy = try self.allocator.dupe(u8, name);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.headers.put(name_copy, value_copy);
    }

    /// Get a header value by name
    pub fn getHeader(self: *const Response, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// Remove a header
    pub fn removeHeader(self: *Response, name: []const u8) bool {
        return self.headers.remove(name);
    }

    /// Check if response has a specific header
    pub fn hasHeader(self: *const Response, name: []const u8) bool {
        return self.headers.contains(name);
    }

    /// Set the Content-Type header
    pub fn setContentType(self: *Response, content_type: []const u8) !void {
        try self.setHeader(HeaderNames.CONTENT_TYPE, content_type);
    }

    /// Set the Content-Length header
    pub fn setContentLength(self: *Response, length: usize) !void {
        // Allocate memory for the content-length string to ensure it persists
        const length_str = try std.fmt.allocPrint(self.allocator, "{d}", .{length});
        defer self.allocator.free(length_str); // Free the temporary string after use
        try self.setHeader(HeaderNames.CONTENT_LENGTH, length_str);
    }

    /// Set response body as text
    pub fn setText(self: *Response, text: []const u8) !void {
        // Free old body if it was owned
        if (self.body_owned and self.body != null) {
            self.allocator.free(self.body.?);
        }

        // Copy the text to ensure we own the memory
        const body_copy = try self.allocator.dupe(u8, text);
        self.body = body_copy;
        self.body_owned = true;

        try self.setHeader(HeaderNames.CONTENT_TYPE, "text/plain; charset=utf-8");
        try self.setContentLength(text.len);
    }

    /// Set response body as HTML
    pub fn setHtml(self: *Response, html: []const u8) !void {
        // Free old body if it was owned
        if (self.body_owned and self.body != null) {
            self.allocator.free(self.body.?);
        }

        // Copy the HTML to ensure we own the memory
        const body_copy = try self.allocator.dupe(u8, html);
        self.body = body_copy;
        self.body_owned = true;

        try self.setHeader(HeaderNames.CONTENT_TYPE, "text/html; charset=utf-8");
        try self.setContentLength(html.len);
    }

    /// Set response body as JSON
    pub fn setJson(self: *Response, json: []const u8) !void {
        // Free old body if it was owned
        if (self.body_owned and self.body != null) {
            self.allocator.free(self.body.?);
        }

        // Copy the JSON to ensure we own the memory
        const body_copy = try self.allocator.dupe(u8, json);
        self.body = body_copy;
        self.body_owned = true;
        try self.setHeader(HeaderNames.CONTENT_TYPE, "application/json; charset=utf-8");
        try self.setContentLength(json.len);
    }

    /// Set response body as JSON from a struct
    /// This function safely handles memory allocation and deallocation to prevent double-free issues
    pub fn setJsonValue(self: *Response, value: anytype) !void {
        // Use allocator for dynamic JSON serialization to avoid buffer size limits
        const json_str = try std.json.stringifyAlloc(self.allocator, value, .{});
        defer self.allocator.free(json_str);

        // Set proper JSON content type with UTF-8 charset
        try self.setHeader(HeaderNames.CONTENT_TYPE, "application/json; charset=utf-8");

        // Copy JSON string to response body
        const body_copy = try self.allocator.dupe(u8, json_str);
        errdefer self.allocator.free(body_copy); // Free new allocation if subsequent operations fail

        // Free old body if it was owned
        if (self.body_owned and self.body != null) {
            self.allocator.free(self.body.?);
        }

        // Update body pointer and content length
        self.body = body_copy;
        self.body_owned = true;
        try self.setContentLength(body_copy.len);
    }

    /// Set a redirect response
    pub fn redirect(self: *Response, location: []const u8, status: HttpStatus) !void {
        // Free old body if it was owned
        if (self.body_owned and self.body != null) {
            self.allocator.free(self.body.?);
        }

        self.status = status;
        try self.setHeader(HeaderNames.LOCATION, location);
        self.body = null;
        self.body_owned = false;
    }

    /// Set an error response
    pub fn setError(self: *Response, status: HttpStatus, message: []const u8) !void {
        self.status = status;
        // Use a larger stack buffer for error response JSON
        var buf: [512]u8 = undefined;
        const error_response = try std.fmt.bufPrint(buf[0..], "{{\"error\":true,\"message\":\"{s}\",\"status\":{}}}", .{ message, @intFromEnum(status) });
        try self.setJson(error_response);
    }

    /// Set CORS headers
    pub fn setCors(self: *Response, options: struct {
        origin: ?[]const u8 = null,
        methods: ?[]const u8 = null,
        headers: ?[]const u8 = null,
        credentials: bool = false,
        max_age: ?u32 = null,
    }) !void {
        if (options.origin) |origin| {
            try self.setHeader(HeaderNames.ACCESS_CONTROL_ALLOW_ORIGIN, origin);
        }

        if (options.methods) |methods| {
            try self.setHeader(HeaderNames.ACCESS_CONTROL_ALLOW_METHODS, methods);
        }

        if (options.headers) |headers| {
            try self.setHeader(HeaderNames.ACCESS_CONTROL_ALLOW_HEADERS, headers);
        }

        if (options.credentials) {
            try self.setHeader(HeaderNames.ACCESS_CONTROL_ALLOW_CREDENTIALS, "true");
        }

        if (options.max_age) |max_age| {
            var buf: [32]u8 = undefined;
            const max_age_str = try std.fmt.bufPrint(buf[0..], "{d}", .{max_age});
            try self.setHeader(HeaderNames.ACCESS_CONTROL_MAX_AGE, max_age_str);
        }
    }

    /// Set security headers
    pub fn setSecurity(self: *Response, options: struct {
        hsts: bool = true,
        nosniff: bool = true,
        frame_options: ?[]const u8 = "DENY",
        xss_protection: bool = true,
        csp: ?[]const u8 = null,
    }) !void {
        if (options.hsts) {
            try self.setHeader(HeaderNames.STRICT_TRANSPORT_SECURITY, "max-age=31536000; includeSubDomains");
        }

        if (options.nosniff) {
            try self.setHeader(HeaderNames.X_CONTENT_TYPE_OPTIONS, "nosniff");
        }

        if (options.frame_options) |frame_options| {
            try self.setHeader(HeaderNames.X_FRAME_OPTIONS, frame_options);
        }

        if (options.xss_protection) {
            try self.setHeader(HeaderNames.X_XSS_PROTECTION, "1; mode=block");
        }

        if (options.csp) |csp| {
            try self.setHeader(HeaderNames.CONTENT_SECURITY_POLICY, csp);
        }
    }

    /// Set cache control headers
    pub fn setCacheControl(self: *Response, directive: []const u8) !void {
        try self.setHeader(HeaderNames.CACHE_CONTROL, directive);
    }

    /// Set no-cache headers
    pub fn setNoCache(self: *Response) !void {
        try self.setCacheControl("no-cache, no-store, must-revalidate");
        try self.setHeader(HeaderNames.EXPIRES, "0");
    }

    /// Mark response as sent
    pub fn markSent(self: *Response) void {
        self.sent = true;
    }

    /// Check if response has been sent
    pub fn isSent(self: *const Response) bool {
        return self.sent;
    }

    /// Get the status line for HTTP response
    pub fn getStatusLine(self: *const Response) []const u8 {
        // This would need proper memory management in a real implementation
        return switch (self.status) {
            .ok => "HTTP/1.1 200 OK",
            .not_found => "HTTP/1.1 404 Not Found",
            .internal_server_error => "HTTP/1.1 500 Internal Server Error",
            else => "HTTP/1.1 200 OK", // Simplified for now
        };
    }
};

test "Response.init and deinit" {
    var response = Response.init(std.testing.allocator);
    defer response.deinit();

    try std.testing.expectEqual(HttpStatus.ok, response.status);
    try std.testing.expectEqual(@as(?[]const u8, null), response.body);
    try std.testing.expect(!response.sent);
}

test "Response.setStatus" {
    var response = Response.init(std.testing.allocator);
    defer response.deinit();

    response.setStatus(.not_found);
    try std.testing.expectEqual(HttpStatus.not_found, response.status);
}

test "Response.headers" {
    var response = Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setHeader("content-type", "application/json");
    try std.testing.expectEqualStrings("application/json", response.getHeader("content-type").?);
    try std.testing.expect(response.hasHeader("content-type"));
}

test "Response.setText" {
    var response = Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setText("Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", response.body.?);
    try std.testing.expectEqualStrings("text/plain; charset=utf-8", response.getHeader("content-type").?);
}

test "Response.redirect" {
    var response = Response.init(std.testing.allocator);
    defer response.deinit();

    try response.redirect("/new-location", .moved_permanently);
    try std.testing.expectEqual(HttpStatus.moved_permanently, response.status);
    try std.testing.expectEqualStrings("/new-location", response.getHeader("location").?);
}
