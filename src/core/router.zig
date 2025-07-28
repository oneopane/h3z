//! Ultra-high-performance router with Trie, LRU cache, and compile-time optimizations
//! Now implemented as a decoupled component

const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;
const H3Event = @import("event.zig").H3Event;
const RouteCache = @import("route_cache.zig").RouteCache;
const config = @import("config.zig");
const component = @import("component.zig");
const Component = component.Component;
const BaseComponent = component.BaseComponent;
const ComponentContext = component.ComponentContext;

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
            if (params) |p| {
                p.reset();
                return p;
            }
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

/// Trie node for efficient route matching (internal implementation)
const TrieNode = struct {
    // Static path segments (exact matches)
    children: std.HashMap([]const u8, *TrieNode, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    // Parameter node (matches any segment)
    param_child: ?*TrieNode = null,
    param_name: ?[]const u8 = null,

    // Wildcard node (matches remaining path)
    wildcard_child: ?*TrieNode = null,

    // Handler for this exact path
    handler: ?Handler = null,

    // Method-specific handlers and patterns
    method_handlers: [std.meta.fields(HttpMethod).len]?Handler,
    method_patterns: [std.meta.fields(HttpMethod).len]?[]const u8,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*TrieNode {
        const node = try allocator.create(TrieNode);
        node.* = TrieNode{
            .children = std.HashMap([]const u8, *TrieNode, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .method_handlers = [_]?Handler{null} ** std.meta.fields(HttpMethod).len,
            .method_patterns = [_]?[]const u8{null} ** std.meta.fields(HttpMethod).len,
            .allocator = allocator,
        };
        return node;
    }

    pub fn deinit(self: *TrieNode) void {
        if (self.children.count() > 0) {
            var keys_to_remove = std.ArrayList([]const u8).init(self.allocator);
            defer keys_to_remove.deinit();

            var iter = self.children.iterator();
            while (iter.next()) |entry| {
                keys_to_remove.append(entry.key_ptr.*) catch {};
            }

            for (keys_to_remove.items) |key| {
                if (self.children.get(key)) |child| {
                    child.deinit();
                    _ = self.children.remove(key);
                    // Free the key since we duplicated it during insertion
                    self.allocator.free(key);
                }
            }
        }

        self.children.deinit();

        if (self.param_child) |child| {
            child.deinit();
        }

        if (self.wildcard_child) |child| {
            child.deinit();
        }

        self.allocator.destroy(self);
    }

    /// Insert a route into the trie
    pub fn insert(self: *TrieNode, path: []const u8, method: HttpMethod, handler: Handler) !void {
        var current = self;
        var path_iter = std.mem.splitScalar(u8, path, '/');

        while (path_iter.next()) |segment| {
            if (segment.len == 0) continue;

            if (std.mem.startsWith(u8, segment, ":")) {
                // Parameter segment
                const param_name = segment[1..];

                if (current.param_child == null) {
                    current.param_child = try TrieNode.init(current.allocator);
                    current.param_name = param_name;
                }
                current = current.param_child.?;
            } else if (std.mem.eql(u8, segment, "*")) {
                // Wildcard segment
                if (current.wildcard_child == null) {
                    current.wildcard_child = try TrieNode.init(current.allocator);
                }
                current = current.wildcard_child.?;
                break; // Wildcard consumes rest of path
            } else {
                // Static segment - need to duplicate the key since it might be temporary
                const segment_copy = try current.allocator.dupe(u8, segment);
                const result = try current.children.getOrPut(segment_copy);
                if (!result.found_existing) {
                    result.value_ptr.* = try TrieNode.init(current.allocator);
                } else {
                    // Free the copy if we didn't use it
                    current.allocator.free(segment_copy);
                }
                current = result.value_ptr.*;
            }
        }

        // Set handler and pattern for this method
        const method_index = @intFromEnum(method);
        current.method_handlers[method_index] = handler;
        current.method_patterns[method_index] = path;
    }

    /// Search for a route in the trie
    pub fn search(self: *TrieNode, path: []const u8, method: HttpMethod, params: *RouteParams) ?SearchResult {
        return self.searchRecursive(path, method, params, 0);
    }

    fn searchRecursive(self: *TrieNode, path: []const u8, method: HttpMethod, params: *RouteParams, start_pos: usize) ?SearchResult {
        // Find next segment
        var pos = start_pos;
        while (pos < path.len and path[pos] == '/') pos += 1;

        if (pos >= path.len) {
            // End of path - check if we have a handler for this method
            const method_index = @intFromEnum(method);
            if (self.method_handlers[method_index]) |handler| {
                const pattern = self.method_patterns[method_index] orelse "";
                return .{ .handler = handler, .pattern = pattern };
            }
            return null;
        }

        // Find end of current segment
        var end_pos = pos;
        while (end_pos < path.len and path[end_pos] != '/') end_pos += 1;

        const segment = path[pos..end_pos];

        // Try static match first (most specific)
        if (self.children.get(segment)) |child| {
            if (child.searchRecursive(path, method, params, end_pos)) |result| {
                return result;
            }
        }

        // Try parameter match
        if (self.param_child) |child| {
            if (self.param_name) |param_name| {
                params.put(param_name, segment) catch {};
                if (child.searchRecursive(path, method, params, end_pos)) |result| {
                    return result;
                }
                // Remove parameter if match failed
                _ = params.params.remove(param_name);
            }
        }

        // Try wildcard match (least specific)
        if (self.wildcard_child) |child| {
            const method_index = @intFromEnum(method);
            if (child.method_handlers[method_index]) |handler| {
                const pattern = child.method_patterns[method_index] orelse "";
                return .{ .handler = handler, .pattern = pattern };
            }
        }

        return null;
    }
};

/// Search result from Trie
const SearchResult = struct {
    handler: Handler,
    pattern: []const u8,
};

/// Trie-based route match result
const TrieRouteMatch = struct {
    handler: Handler,
    params: *RouteParams,
    pattern: []const u8,
};

/// High-performance Trie-based router (internal implementation)
const TrieRouter = struct {
    // Separate trie for each HTTP method for maximum performance
    method_tries: [std.meta.fields(HttpMethod).len]*TrieNode,
    params_pool: RouteParamsPool,
    allocator: std.mem.Allocator,

    // Performance statistics
    route_count: usize = 0,
    search_count: usize = 0,
    cache_hits: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !TrieRouter {
        var method_tries: [std.meta.fields(HttpMethod).len]*TrieNode = undefined;

        // Initialize a separate trie for each HTTP method
        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            method_tries[i] = try TrieNode.init(allocator);
        }

        return TrieRouter{
            .method_tries = method_tries,
            .params_pool = RouteParamsPool.init(allocator, 200), // Larger pool for better performance
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TrieRouter) void {
        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            self.method_tries[i].deinit();
        }
        self.params_pool.deinit();
    }

    /// Add a route to the trie
    pub fn addRoute(self: *TrieRouter, method: HttpMethod, path: []const u8, handler: Handler) !void {
        const method_index = @intFromEnum(method);
        try self.method_tries[method_index].insert(path, method, handler);
        self.route_count += 1;
    }

    /// Find a route using trie search - O(log n) performance
    pub fn findRoute(self: *TrieRouter, method: HttpMethod, path: []const u8) ?TrieRouteMatch {
        self.search_count += 1;

        const method_index = @intFromEnum(method);
        const trie = self.method_tries[method_index];

        const params = self.params_pool.acquire() catch return null;

        if (trie.search(path, method, params)) |result| {
            return TrieRouteMatch{
                .handler = result.handler,
                .params = params,
                .pattern = result.pattern,
            };
        }

        // No match found, release params
        self.params_pool.release(params);
        return null;
    }

    /// Release route match resources
    pub fn releaseMatch(self: *TrieRouter, match: TrieRouteMatch) void {
        self.params_pool.release(match.params);
    }

    /// Get performance statistics
    pub fn getStats(self: *const TrieRouter) struct {
        route_count: usize,
        search_count: usize,
        cache_hits: usize,
        hit_ratio: f64,
    } {
        const hit_ratio = if (self.search_count > 0)
            @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(self.search_count))
        else
            0.0;

        return .{
            .route_count = self.route_count,
            .search_count = self.search_count,
            .cache_hits = self.cache_hits,
            .hit_ratio = hit_ratio,
        };
    }

    /// Clear all routes
    pub fn clear(self: *TrieRouter) void {
        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            self.method_tries[i].deinit();
            self.method_tries[i] = TrieNode.init(self.allocator) catch unreachable;
        }
        self.route_count = 0;
        self.search_count = 0;
        self.cache_hits = 0;
    }
};

/// Route entry
pub const Route = struct {
    method: HttpMethod,
    pattern: []const u8,
    handler: Handler,
};

/// Route match result
pub const RouteMatch = struct {
    handler: Handler,
    params: *RouteParams,
    method: HttpMethod,
    pattern: []const u8,
};

/// Ultra-high-performance router with Trie, cache, and compile-time optimizations
pub const Router = struct {
    // Trie-based router for O(log n) lookups
    trie_router: TrieRouter,

    // LRU cache for hot path optimization
    route_cache: RouteCache,

    // Legacy route storage for compatibility
    method_routes: [std.meta.fields(HttpMethod).len]std.ArrayList(Route),
    params_pool: RouteParamsPool,
    allocator: std.mem.Allocator,

    // Performance configuration
    config: config.RouterConfig,

    /// Initialize a new ultra-high-performance router
    pub fn init(allocator: std.mem.Allocator) !Router {
        return Router.initWithConfig(allocator, config.RouterConfig{});
    }

    /// Initialize router with custom configuration
    pub fn initWithConfig(allocator: std.mem.Allocator, router_config: config.RouterConfig) !Router {
        var method_routes: [std.meta.fields(HttpMethod).len]std.ArrayList(Route) = undefined;

        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            method_routes[i] = std.ArrayList(Route).init(allocator);
        }

        const trie_router = try TrieRouter.init(allocator);
        errdefer trie_router.deinit();

        // Use smaller pool size for testing to reduce memory overhead
        const pool_size: usize = 10;

        return Router{
            .trie_router = trie_router,
            .route_cache = RouteCache.init(allocator, router_config.cache_size),
            .method_routes = method_routes,
            .params_pool = RouteParamsPool.init(allocator, pool_size),
            .allocator = allocator,
            .config = router_config,
        };
    }

    /// Deinitialize the router
    pub fn deinit(self: *Router) void {
        self.trie_router.deinit();
        if (self.config.enable_cache) {
            self.route_cache.deinit();
        }

        inline for (std.meta.fields(HttpMethod), 0..) |_, i| {
            self.method_routes[i].deinit();
        }
        self.params_pool.deinit();
    }

    /// Add a route with multi-tier optimization
    pub fn addRoute(self: *Router, method: HttpMethod, pattern: []const u8, handler: Handler) !void {
        const method_index = @intFromEnum(method);

        // Add to Trie router for O(log n) lookups
        try self.trie_router.addRoute(method, pattern, handler);

        const route = Route{
            .method = method,
            .pattern = pattern,
            .handler = handler,
        };
        try self.method_routes[method_index].append(route);
    }

    /// Ultra-fast route lookup with multi-tier optimization
    pub fn findRoute(self: *Router, method: HttpMethod, path: []const u8) ?RouteMatch {
        // Tier 1: LRU Cache lookup (O(1))
        if (self.config.enable_cache) {
            if (self.route_cache.get(method, path)) |cached| {
                const params = self.params_pool.acquire() catch return null;

                // Copy cached parameters
                var param_iter = cached.params.iterator();
                while (param_iter.next()) |entry| {
                    params.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
                }

                return RouteMatch{
                    .handler = cached.handler.?,
                    .params = params,
                    .method = method,
                    .pattern = path,
                };
            }
        }

        // Tier 2: Trie router lookup (O(log n))
        if (self.trie_router.findRoute(method, path)) |trie_match| {
            // Cache the result for future lookups
            if (self.config.enable_cache) {
                self.route_cache.put(method, path, trie_match.handler, trie_match.params.params) catch {};
            }

            return RouteMatch{
                .handler = trie_match.handler,
                .params = trie_match.params,
                .method = method,
                .pattern = trie_match.pattern,
            };
        }

        return null;
    }

    /// Release route match resources
    pub fn releaseMatch(self: *Router, match: RouteMatch) void {
        self.params_pool.release(match.params);
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
            self.method_routes[i].clearAndFree();
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

/// Component-based router implementation
pub const RouterComponent = struct {
    base: BaseComponent(RouterComponent, config.RouterConfig),
    router: Router,

    const Self = @This();

    /// Create a new router component
    pub fn init(allocator: std.mem.Allocator, router_config: config.RouterConfig) !Self {
        const router = try Router.initWithConfig(allocator, router_config);

        return Self{
            .base = .{
                .component_config = router_config,
                .name = "router",
            },
            .router = router,
        };
    }

    /// Component initialization implementation
    pub fn initImpl(self: *Self, context: *ComponentContext) !void {
        _ = self;
        _ = context;
        // Router is already initialized in init()
    }

    /// Component deinitialization implementation
    pub fn deinitImpl(self: *Self) void {
        self.router.deinit();
    }

    /// Component start implementation
    pub fn startImpl(self: *Self) !void {
        _ = self;
        // Router doesn't need explicit start
    }

    /// Component stop implementation
    pub fn stopImpl(self: *Self) !void {
        _ = self;
        // Router doesn't need explicit stop
    }

    /// Handle configuration updates
    pub fn configUpdated(self: *Self) !void {
        // For now, configuration changes require restart
        // In the future, we could implement hot-reloading
        _ = self;
    }

    /// Get the underlying router
    pub fn getRouter(self: *Self) *Router {
        return &self.router;
    }

    /// Add a route through the component
    pub fn addRoute(self: *Self, method: HttpMethod, pattern: []const u8, handler: Handler) !void {
        return self.router.addRoute(method, pattern, handler);
    }

    /// Find a route through the component
    pub fn findRoute(self: *Self, method: HttpMethod, path: []const u8) ?RouteMatch {
        return self.router.findRoute(method, path);
    }

    /// Release route match resources
    pub fn releaseMatch(self: *Self, match: RouteMatch) void {
        self.router.releaseMatch(match);
    }

    /// Get route count
    pub fn getRouteCount(self: *const Self) usize {
        return self.router.getRouteCount();
    }

    /// Clear all routes
    pub fn clear(self: *Self) void {
        self.router.clear();
    }

    /// Get component interface
    pub fn component(self: *Self) Component {
        return self.base.component();
    }
};

test "Router.addRoute and findRoute" {
    var router = try Router.init(std.testing.allocator);
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
    try std.testing.expectEqualStrings("/", result1.?.pattern);
    router.releaseMatch(result1.?);

    // Test no match
    const result2 = router.findRoute(.GET, "/nonexistent");
    try std.testing.expect(result2 == null);

    // Test parameter match
    const result3 = router.findRoute(.GET, "/users/123");
    try std.testing.expect(result3 != null);
    try std.testing.expectEqualStrings("/users/:id", result3.?.pattern);
    try std.testing.expectEqualStrings("123", result3.?.params.get("id").?);
    router.releaseMatch(result3.?);
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
