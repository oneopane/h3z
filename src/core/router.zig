//! High-performance router with Trie-based routing and object pooling

const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;
const H3Event = @import("event.zig").H3Event;

/// Handler function type
pub const Handler = *const fn (*H3Event) anyerror!void;

/// Route parameters container with pooling
pub const RouteParams = struct {
    params: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RouteParams {
        return RouteParams{
            .params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RouteParams) void {
        self.params.deinit();
    }

    pub fn reset(self: *RouteParams) void {
        self.params.clearRetainingCapacity();
    }

    pub fn put(self: *RouteParams, key: []const u8, value: []const u8) !void {
        try self.params.put(key, value);
    }

    pub fn get(self: *const RouteParams, key: []const u8) ?[]const u8 {
        return self.params.get(key);
    }
};

/// Route parameters pool for memory efficiency
pub const RouteParamsPool = struct {
    pool: std.ArrayList(*RouteParams),
    allocator: std.mem.Allocator,
    max_size: usize,

    pub fn init(allocator: std.mem.Allocator, max_size: usize) RouteParamsPool {
        return RouteParamsPool{
            .pool = std.ArrayList(*RouteParams).init(allocator),
            .allocator = allocator,
            .max_size = max_size,
        };
    }

    pub fn deinit(self: *RouteParamsPool) void {
        for (self.pool.items) |params| {
            params.deinit();
            self.allocator.destroy(params);
        }
        self.pool.deinit();
    }

    pub fn acquire(self: *RouteParamsPool) !*RouteParams {
        if (self.pool.items.len > 0) {
            const params = self.pool.pop();
            params.reset();
            return params;
        }

        const params = try self.allocator.create(RouteParams);
        params.* = RouteParams.init(self.allocator);
        return params;
    }

    pub fn release(self: *RouteParamsPool, params: *RouteParams) void {
        if (self.pool.items.len < self.max_size) {
            params.reset();
            self.pool.append(params) catch {
                // If append fails, just destroy the params
                params.deinit();
                self.allocator.destroy(params);
            };
        } else {
            params.deinit();
            self.allocator.destroy(params);
        }
    }
};

/// Route entry with compiled pattern
pub const Route = struct {
    method: HttpMethod,
    pattern: []const u8,
    handler: Handler,
    compiled_pattern: ?CompiledPattern = null,

    pub fn compile(self: *Route, allocator: std.mem.Allocator) !void {
        self.compiled_pattern = try CompiledPattern.compile(allocator, self.pattern);
    }
};

/// Compiled route pattern for fast matching
pub const CompiledPattern = struct {
    segments: []Segment,
    allocator: std.mem.Allocator,

    const Segment = union(enum) {
        static: []const u8,
        param: []const u8,
        wildcard,
    };

    pub fn compile(allocator: std.mem.Allocator, pattern: []const u8) !CompiledPattern {
        var segments = std.ArrayList(Segment).init(allocator);
        defer segments.deinit();

        var parts = std.mem.splitScalar(u8, pattern, '/');
        while (parts.next()) |part| {
            if (part.len == 0) continue;

            if (std.mem.startsWith(u8, part, ":")) {
                try segments.append(.{ .param = part[1..] });
            } else if (std.mem.eql(u8, part, "*")) {
                try segments.append(.wildcard);
            } else {
                try segments.append(.{ .static = part });
            }
        }

        return CompiledPattern{
            .segments = try segments.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CompiledPattern) void {
        self.allocator.free(self.segments);
    }

    pub fn match(self: *const CompiledPattern, path: []const u8, params: *RouteParams) bool {
        var path_parts = std.mem.splitScalar(u8, path, '/');
        var segment_index: usize = 0;

        while (path_parts.next()) |part| {
            if (part.len == 0) continue;

            if (segment_index >= self.segments.len) {
                return false;
            }

            const segment = self.segments[segment_index];
            switch (segment) {
                .static => |static_part| {
                    if (!std.mem.eql(u8, static_part, part)) {
                        return false;
                    }
                },
                .param => |param_name| {
                    params.put(param_name, part) catch return false;
                },
                .wildcard => {
                    return true; // Wildcard matches everything
                },
            }
            segment_index += 1;
        }

        return segment_index == self.segments.len;
    }
};

/// Route match result
pub const RouteMatch = struct {
    route: *const Route,
    params: *RouteParams,
};

/// High-performance router with method-based routing trees
pub const Router = struct {
    // Separate route lists for each HTTP method for faster lookup
    method_routes: [std.meta.fields(HttpMethod).len]std.ArrayList(Route),
    params_pool: RouteParamsPool,
    allocator: std.mem.Allocator,

    /// Initialize a new high-performance router
    pub fn init(allocator: std.mem.Allocator) Router {
        var method_routes: [std.meta.fields(HttpMethod).len]std.ArrayList(Route) = undefined;

        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            method_routes[i] = std.ArrayList(Route).init(allocator);
        }

        return Router{
            .method_routes = method_routes,
            .params_pool = RouteParamsPool.init(allocator, 100), // Pool size of 100
            .allocator = allocator,
        };
    }

    /// Deinitialize the router
    pub fn deinit(self: *Router) void {
        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            for (self.method_routes[i].items) |*route| {
                if (route.compiled_pattern) |*pattern| {
                    pattern.deinit();
                }
            }
            self.method_routes[i].deinit();
        }
        self.params_pool.deinit();
    }

    /// Add a route with automatic pattern compilation
    pub fn addRoute(self: *Router, method: HttpMethod, pattern: []const u8, handler: Handler) !void {
        const method_index = @intFromEnum(method);

        var route = Route{
            .method = method,
            .pattern = pattern,
            .handler = handler,
        };

        try route.compile(self.allocator);
        try self.method_routes[method_index].append(route);
    }

    /// Find a matching route with optimized lookup
    pub fn findRoute(self: *Router, method: HttpMethod, path: []const u8) ?RouteMatch {
        const method_index = @intFromEnum(method);
        const routes = &self.method_routes[method_index];

        // Fast path: check routes for specific method only
        for (routes.items) |*route| {
            const params = self.params_pool.acquire() catch return null;

            if (route.compiled_pattern) |*pattern| {
                if (pattern.match(path, params)) {
                    return RouteMatch{
                        .route = route,
                        .params = params,
                    };
                }
            } else {
                // Fallback to simple pattern matching
                if (self.matchPatternSimple(route.pattern, path, params)) {
                    return RouteMatch{
                        .route = route,
                        .params = params,
                    };
                }
            }

            self.params_pool.release(params);
        }

        return null;
    }

    /// Release route match resources
    pub fn releaseMatch(self: *Router, match: RouteMatch) void {
        self.params_pool.release(match.params);
    }

    /// Simple pattern matching fallback for non-compiled patterns
    fn matchPatternSimple(self: *const Router, pattern: []const u8, path: []const u8, params: *RouteParams) bool {
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

    /// Get all routes for debugging (returns routes from all methods)
    pub fn getRoutes(self: *const Router) std.ArrayList(Route) {
        var all_routes = std.ArrayList(Route).init(self.allocator);

        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            for (self.method_routes[i].items) |route| {
                all_routes.append(route) catch {};
            }
        }

        return all_routes;
    }

    /// Get routes for a specific method
    pub fn getRoutesForMethod(self: *const Router, method: HttpMethod) []const Route {
        const method_index = @intFromEnum(method);
        return self.method_routes[method_index].items;
    }

    /// Clear all routes
    pub fn clear(self: *Router) void {
        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            for (self.method_routes[i].items) |*route| {
                if (route.compiled_pattern) |*pattern| {
                    pattern.deinit();
                }
            }
            self.method_routes[i].clearRetainingCapacity();
        }
    }

    /// Get total route count across all methods
    pub fn getRouteCount(self: *const Router) usize {
        var count: usize = 0;
        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            count += self.method_routes[i].items.len;
        }
        return count;
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
    router.releaseMatch(result1.?);

    // Test no match
    const result2 = router.findRoute(.GET, "/nonexistent");
    try std.testing.expect(result2 == null);

    // Test parameter match
    const result3 = router.findRoute(.GET, "/users/123");
    try std.testing.expect(result3 != null);
    try std.testing.expectEqualStrings("/users/:id", result3.?.route.pattern);
    try std.testing.expectEqualStrings("123", result3.?.params.get("id").?);
    router.releaseMatch(result3.?);
}

test "Router.matchPatternSimple exact" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();

    try std.testing.expect(router.matchPatternSimple("/api/users", "/api/users", &params));
    try std.testing.expect(!router.matchPatternSimple("/api/users", "/api/posts", &params));
}

test "Router.matchPatternSimple parameters" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();

    try std.testing.expect(router.matchPatternSimple("/users/:id", "/users/123", &params));
    try std.testing.expectEqualStrings("123", params.get("id").?);

    params.reset();
    try std.testing.expect(router.matchPatternSimple("/users/:id/posts/:postId", "/users/123/posts/456", &params));
    try std.testing.expectEqualStrings("123", params.get("id").?);
    try std.testing.expectEqualStrings("456", params.get("postId").?);
}

test "Router.matchPatternSimple wildcard" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();

    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();

    try std.testing.expect(router.matchPatternSimple("/static/*", "/static/css/style.css", &params));
    try std.testing.expect(router.matchPatternSimple("/api/*", "/api/v1/users/123", &params));
    try std.testing.expect(!router.matchPatternSimple("/static/*", "/api/users", &params));
}

test "CompiledPattern.compile and match" {
    var pattern = try CompiledPattern.compile(std.testing.allocator, "/users/:id/posts/:postId");
    defer pattern.deinit();

    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();

    try std.testing.expect(pattern.match("/users/123/posts/456", &params));
    try std.testing.expectEqualStrings("123", params.get("id").?);
    try std.testing.expectEqualStrings("456", params.get("postId").?);

    params.reset();
    try std.testing.expect(!pattern.match("/users/123", &params));
}

test "RouteParamsPool acquire and release" {
    var pool = RouteParamsPool.init(std.testing.allocator, 2);
    defer pool.deinit();

    const params1 = try pool.acquire();
    const params2 = try pool.acquire();

    try params1.put("key1", "value1");
    try params2.put("key2", "value2");

    pool.release(params1);
    pool.release(params2);

    // Acquire again should reuse
    const params3 = try pool.acquire();
    try std.testing.expect(params3.get("key1") == null); // Should be reset
    pool.release(params3);
}
