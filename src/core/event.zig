//! H3Event - The central context object for HTTP requests

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const HttpMethod = @import("../http/method.zig").HttpMethod;
const HttpStatus = @import("../http/status.zig").HttpStatus;

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
        self.request.deinit();
        self.response.deinit();
        self.context.deinit();
        self.params.deinit();
        self.query.deinit();
    }

    /// Reset the event for reuse in object pool
    pub fn reset(self: *H3Event) void {
        self.request.reset();
        self.response.reset();
        self.context.clearRetainingCapacity();
        self.params.clearRetainingCapacity();
        self.query.clearRetainingCapacity();
    }

    /// Get a context value
    pub fn getContext(self: *const H3Event, key: []const u8) ?[]const u8 {
        return self.context.get(key);
    }

    /// Set a context value
    pub fn setContext(self: *H3Event, key: []const u8, value: []const u8) !void {
        try self.context.put(key, value);
    }

    /// Get a route parameter
    pub fn getParam(self: *const H3Event, key: []const u8) ?[]const u8 {
        return self.params.get(key);
    }

    /// Set a route parameter
    pub fn setParam(self: *H3Event, key: []const u8, value: []const u8) !void {
        try self.params.put(key, value);
    }

    /// Get a query parameter
    pub fn getQuery(self: *const H3Event, key: []const u8) ?[]const u8 {
        return self.query.get(key);
    }

    /// Parse query string into query parameters
    pub fn parseQuery(self: *H3Event) !void {
        if (self.request.query) |query_string| {
            var iter = std.mem.splitSequence(u8, query_string, "&");
            while (iter.next()) |pair| {
                if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
                    const key = pair[0..eq_pos];
                    const value = pair[eq_pos + 1 ..];

                    // URL decode key and value (simplified implementation)
                    try self.query.put(key, value);
                } else {
                    // Handle key without value
                    try self.query.put(pair, "");
                }
            }
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
    pub fn readJson(self: *const H3Event, comptime T: type) !T {
        const body = self.readBody() orelse return error.NoBody;
        const parsed = try std.json.parseFromSlice(T, self.allocator, body, .{});
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
