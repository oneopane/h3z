//! Simple router for matching HTTP routes

const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;
const H3Event = @import("event.zig").H3Event;

/// Handler function type
pub const Handler = *const fn (*H3Event) anyerror!void;

/// Route entry
pub const Route = struct {
    method: HttpMethod,
    pattern: []const u8,
    handler: Handler,
};

/// Simple router implementation
pub const Router = struct {
    routes: std.ArrayList(Route),
    allocator: std.mem.Allocator,

    /// Initialize a new router
    pub fn init(allocator: std.mem.Allocator) Router {
        return Router{
            .routes = std.ArrayList(Route).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize the router
    pub fn deinit(self: *Router) void {
        self.routes.deinit();
    }

    /// Add a route
    pub fn addRoute(self: *Router, method: HttpMethod, pattern: []const u8, handler: Handler) !void {
        try self.routes.append(Route{
            .method = method,
            .pattern = pattern,
            .handler = handler,
        });
    }

    /// Find a matching route
    pub fn findRoute(self: *const Router, method: HttpMethod, path: []const u8) ?struct { route: Route, params: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) } {
        for (self.routes.items) |route| {
            if (route.method == method) {
                var params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
                if (self.matchPattern(route.pattern, path, &params)) {
                    return .{ .route = route, .params = params };
                } else {
                    params.deinit();
                }
            }
        }
        return null;
    }

    /// Match a route pattern against a path
    /// Supports simple parameter matching like /users/:id
    fn matchPattern(self: *const Router, pattern: []const u8, path: []const u8, params: *std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage)) bool {
        _ = self;

        // Simple exact match for now
        if (std.mem.eql(u8, pattern, path)) {
            return true;
        }

        // Handle parameter patterns like /users/:id
        var pattern_parts = std.mem.splitSequence(u8, pattern, "/");
        var path_parts = std.mem.splitSequence(u8, path, "/");

        while (true) {
            const pattern_part = pattern_parts.next();
            const path_part = path_parts.next();

            // Both exhausted - match
            if (pattern_part == null and path_part == null) {
                return true;
            }

            // One exhausted but not the other - no match
            if (pattern_part == null or path_part == null) {
                return false;
            }

            const pp = pattern_part.?;
            const path_p = path_part.?;

            // Parameter pattern (starts with :)
            if (pp.len > 0 and pp[0] == ':') {
                const param_name = pp[1..];
                params.put(param_name, path_p) catch return false;
                continue;
            }

            // Wildcard pattern (*)
            if (std.mem.eql(u8, pp, "*")) {
                // Consume remaining path parts
                while (path_parts.next() != null) {}
                return true;
            }

            // Exact match required
            if (!std.mem.eql(u8, pp, path_p)) {
                return false;
            }
        }
    }

    /// Get all routes for debugging
    pub fn getRoutes(self: *const Router) []const Route {
        return self.routes.items;
    }

    /// Clear all routes
    pub fn clear(self: *Router) void {
        self.routes.clearRetainingCapacity();
    }
};

test "Router.addRoute and findRoute" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    const testHandler = struct {
        fn handler(event: *H3Event) !void {
            _ = event;
        }
    }.handler;

    try router.addRoute(.GET, "/", testHandler);
    try router.addRoute(.POST, "/users", testHandler);
    try router.addRoute(.GET, "/users/:id", testHandler);

    // Test exact match
    const result1 = router.findRoute(.GET, "/");
    try std.testing.expect(result1 != null);
    try std.testing.expectEqualStrings("/", result1.?.route.pattern);
    var params1 = result1.?.params;
    params1.deinit();

    // Test no match
    const result2 = router.findRoute(.GET, "/nonexistent");
    try std.testing.expect(result2 == null);

    // Test parameter match
    const result3 = router.findRoute(.GET, "/users/123");
    try std.testing.expect(result3 != null);
    try std.testing.expectEqualStrings("/users/:id", result3.?.route.pattern);
    try std.testing.expectEqualStrings("123", result3.?.params.get("id").?);
    var params3 = result3.?.params;
    params3.deinit();
}

test "Router.matchPattern exact" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    var params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(std.testing.allocator);
    defer params.deinit();

    try std.testing.expect(router.matchPattern("/api/users", "/api/users", &params));
    try std.testing.expect(!router.matchPattern("/api/users", "/api/posts", &params));
}

test "Router.matchPattern parameters" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    var params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(std.testing.allocator);
    defer params.deinit();

    try std.testing.expect(router.matchPattern("/users/:id", "/users/123", &params));
    try std.testing.expectEqualStrings("123", params.get("id").?);

    params.clearRetainingCapacity();
    try std.testing.expect(router.matchPattern("/users/:id/posts/:postId", "/users/123/posts/456", &params));
    try std.testing.expectEqualStrings("123", params.get("id").?);
    try std.testing.expectEqualStrings("456", params.get("postId").?);
}

test "Router.matchPattern wildcard" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    var params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(std.testing.allocator);
    defer params.deinit();

    try std.testing.expect(router.matchPattern("/static/*", "/static/css/style.css", &params));
    try std.testing.expect(router.matchPattern("/api/*", "/api/v1/users/123", &params));
    try std.testing.expect(!router.matchPattern("/static/*", "/api/users", &params));
}
