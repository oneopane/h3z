//! H3Event - The central context object for HTTP requests

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const HttpMethod = @import("../http/method.zig").HttpMethod;
const HttpStatus = @import("../http/status.zig").HttpStatus;
const url_utils = @import("../internal/url.zig");
const body_utils = @import("../utils/body.zig");

/// Context map for storing arbitrary data
const Context = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage);

/// H3Event represents the context for a single HTTP request/response cycle
pub const H3Event = struct {
    /// HTTP request
    request: Request,

    /// HTTP response
    response: Response,

    /// Context map for storing arbitrary data
    context: Context,

    /// Route parameters (e.g., from /users/:id)
    params: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    /// Parsed query parameters
    query: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    /// Initialize a new H3Event
    pub fn init(allocator: std.mem.Allocator) H3Event {
        return H3Event{
            .request = Request.init(allocator),
            .response = Response.init(allocator),
            .context = Context.init(allocator),
            .params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .query = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize the event and free resources
    pub fn deinit(self: *H3Event) void {
        // Free key-value pairs in the context hash map
        var context_iter = self.context.iterator();
        while (context_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.context.deinit();

        // Free key-value pairs in the params hash map
        var params_iter = self.params.iterator();
        while (params_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.params.deinit();

        // Free key-value pairs in the query hash map
        var query_iter = self.query.iterator();
        while (query_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.query.deinit();

        // Free request and response
        self.request.deinit();
        self.response.deinit();
    }

    /// Reset the event for reuse in object pool
    pub fn reset(self: *H3Event) void {
        self.request.reset();
        self.response.reset();

        // Free key-value pairs in the context hash map
        var context_iter = self.context.iterator();
        while (context_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.context.clearRetainingCapacity();

        // Free key-value pairs in the params hash map
        var params_iter = self.params.iterator();
        while (params_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.params.clearRetainingCapacity();

        // Free key-value pairs in the query hash map
        var query_iter = self.query.iterator();
        while (query_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.query.clearRetainingCapacity();
    }

    /// Get a context value
    pub fn getContext(self: *const H3Event, key: []const u8) ?[]const u8 {
        return self.context.get(key);
    }

    /// Set a context value
    pub fn setContext(self: *H3Event, key: []const u8, value: []const u8) !void {
        // Duplicate the key
        const key_dup = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_dup);

        // Duplicate the value
        const value_dup = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_dup);

        // Check if the key already exists, if so, free the old key-value pair
        if (self.context.getEntry(key)) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        // Add the new key-value pair
        try self.context.put(key_dup, value_dup);
    }

    /// Get a route parameter
    pub fn getParam(self: *const H3Event, key: []const u8) ?[]const u8 {
        return self.params.get(key);
    }

    /// Set a route parameter
    pub fn setParam(self: *H3Event, key: []const u8, value: []const u8) !void {
        // Duplicate the key
        const key_dup = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_dup);

        // Duplicate the value
        const value_dup = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_dup);

        // Check if the key already exists, if so, free the old key-value pair
        if (self.params.getEntry(key)) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        // Add the new key-value pair
        try self.params.put(key_dup, value_dup);
    }

    /// Get a query parameter
    pub fn getQuery(self: *const H3Event, key: []const u8) ?[]const u8 {
        return self.query.get(key);
    }

    /// Parse query string into query parameters
    /// This function properly handles URL-encoded characters in query parameters
    pub fn parseQuery(self: *H3Event) !void {
        // If there is no query string, return directly
        const query_string = self.request.query orelse return;

        // First clean up existing query parameters to avoid memory leaks
        var old_iter = self.query.iterator();
        while (old_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.query.clearRetainingCapacity();

        // Use url_utils.QueryParser to parse the query string
        // It automatically handles URL-encoded special characters
        var parsed_params = try url_utils.QueryParser.parse(self.allocator, query_string);
        // Ensure temporary parsing results are cleaned up when the function ends
        defer url_utils.QueryParser.deinit(&parsed_params, self.allocator);

        // Transfer parsed parameters to self.query, need to copy strings
        var iter = parsed_params.iterator();
        while (iter.next()) |entry| {
            // Copy key
            const key = entry.key_ptr.*;
            const key_dup = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(key_dup);

            // Copy value
            const value = entry.value_ptr.*;
            const value_dup = try self.allocator.dupe(u8, value);
            errdefer self.allocator.free(value_dup);

            // Add the copied key-value pair to the query parameter map
            try self.query.put(key_dup, value_dup);
        }
    }

    /// Get the HTTP method
    pub fn getMethod(self: *const H3Event) HttpMethod {
        return self.request.method;
    }

    /// Get the request path
    pub fn getPath(self: *const H3Event) []const u8 {
        return self.request.path;
    }

    /// Get the full URL
    pub fn getUrl(self: *const H3Event) []const u8 {
        return self.request.url;
    }

    /// Get a request header
    pub fn getHeader(self: *const H3Event, name: []const u8) ?[]const u8 {
        return self.request.getHeader(name);
    }

    /// Set a response header
    pub fn setHeader(self: *H3Event, name: []const u8, value: []const u8) !void {
        try self.response.setHeader(name, value);
    }

    /// Set the response status
    pub fn setStatus(self: *H3Event, status: HttpStatus) void {
        self.response.setStatus(status);
    }

    /// Send a text response
    pub fn sendText(self: *H3Event, text: []const u8) !void {
        try self.response.setText(text);
    }

    /// Send an HTML response
    pub fn sendHtml(self: *H3Event, html: []const u8) !void {
        try self.response.setHtml(html);
    }

    /// Send a JSON response
    pub fn sendJson(self: *H3Event, json: []const u8) !void {
        try self.response.setJson(json);
    }

    /// Send a JSON response from a value
    pub fn sendJsonValue(self: *H3Event, value: anytype) !void {
        try self.response.setJsonValue(value);
    }

    /// Send a redirect response
    pub fn redirect(self: *H3Event, location: []const u8, status: HttpStatus) !void {
        try self.response.redirect(location, status);
    }

    /// Send an error response
    pub fn sendError(self: *H3Event, status: HttpStatus, message: []const u8) !void {
        try self.response.setError(status, message);
    }

    /// Read the request body
    pub fn readBody(self: *const H3Event) ?[]const u8 {
        return self.request.body;
    }

    /// Parse JSON from request body
    /// This function parses the JSON request body into the specified type T.
    /// It handles potential memory allocations and ensures they are properly deinitialized.
    pub fn readJson(self: *const H3Event, comptime T: type) !T {
        const body = self.readBody() orelse return error.NoBody;
        var parsed = try std.json.parseFromSlice(T, self.allocator, body, .{
            .allocator = self.allocator, // Pass allocator for parsing
        });
        defer parsed.deinit(); // Ensure deinit is called to free parsed resources

        // For types that might own memory (like slices or strings not part of the original body),
        // a deep copy might be necessary if the lifetime of `parsed.value` is tied to `parsed`.
        // However, for simple value types or types that copy data during parsing, this is sufficient.
        // If T is a complex type that holds references to memory managed by `parsed`,
        // you would need to deep copy `parsed.value` here before `parsed.deinit()` is called.
        // For now, we assume T is a type that can be directly returned or is copied by value.
        // A more robust solution might involve a trait or compile-time check for deep-copyable types.
        return parsed.value;
    }

    /// Check if request accepts JSON
    pub fn acceptsJson(self: *const H3Event) bool {
        return self.request.acceptsJson();
    }

    /// Check if request has JSON content type
    pub fn isJson(self: *const H3Event) bool {
        return self.request.isJson();
    }

    /// Check if request is secure (HTTPS)
    pub fn isSecure(self: *const H3Event) bool {
        return self.request.isSecure();
    }

    /// Get the User-Agent header
    pub fn getUserAgent(self: *const H3Event) ?[]const u8 {
        return self.request.getUserAgent();
    }

    /// Get the Authorization header
    pub fn getAuthorization(self: *const H3Event) ?[]const u8 {
        return self.request.getAuthorization();
    }

    /// Set CORS headers
    pub fn setCors(self: *H3Event, options: anytype) !void {
        try self.response.setCors(options);
    }

    /// Set security headers
    pub fn setSecurity(self: *H3Event, options: anytype) !void {
        try self.response.setSecurity(options);
    }

    /// Set cache control
    pub fn setCacheControl(self: *H3Event, directive: []const u8) !void {
        try self.response.setCacheControl(directive);
    }

    /// Set no-cache headers
    pub fn setNoCache(self: *H3Event) !void {
        try self.response.setNoCache();
    }
};

test "H3Event.init and deinit" {
    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    try std.testing.expectEqual(HttpMethod.GET, event.getMethod());
    try std.testing.expectEqualStrings("", event.getPath());
}

test "H3Event.context" {
    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    try event.setContext("user_id", "123");
    try std.testing.expectEqualStrings("123", event.getContext("user_id").?);
    try std.testing.expectEqual(@as(?[]const u8, null), event.getContext("nonexistent"));
}

test "H3Event.params" {
    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    try event.setParam("id", "42");
    try std.testing.expectEqualStrings("42", event.getParam("id").?);
}

test "H3Event.parseQuery" {
    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    try event.request.parseUrl("/api/users?page=1&limit=10&sort=name");
    try event.parseQuery();

    try std.testing.expectEqualStrings("1", event.getQuery("page").?);
    try std.testing.expectEqualStrings("10", event.getQuery("limit").?);
    try std.testing.expectEqualStrings("name", event.getQuery("sort").?);
}

test "H3Event.response methods" {
    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    event.setStatus(.created);
    try std.testing.expectEqual(HttpStatus.created, event.response.status);

    try event.sendText("Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", event.response.body.?);
}
