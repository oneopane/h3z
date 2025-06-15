//! True Trie-based router implementation for maximum performance
//! Replaces linear search with O(log n) tree traversal

const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;
const H3Event = @import("event.zig").H3Event;

/// Handler function type
pub const Handler = *const fn (*H3Event) anyerror!void;

/// Route parameters container
pub const RouteParams = @import("router.zig").RouteParams;
pub const RouteParamsPool = @import("router.zig").RouteParamsPool;

/// Trie node for efficient route matching
pub const TrieNode = struct {
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
        // Recursively deinit children
        var iter = self.children.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
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
                // Static segment
                const result = try current.children.getOrPut(segment);
                if (!result.found_existing) {
                    result.value_ptr.* = try TrieNode.init(current.allocator);
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

/// Route match result
pub const RouteMatch = struct {
    handler: Handler,
    params: *RouteParams,
    pattern: []const u8,
};

/// High-performance Trie-based router
pub const TrieRouter = struct {
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
    pub fn findRoute(self: *TrieRouter, method: HttpMethod, path: []const u8) ?RouteMatch {
        self.search_count += 1;

        const method_index = @intFromEnum(method);
        const trie = self.method_tries[method_index];

        const params = self.params_pool.acquire() catch return null;

        if (trie.search(path, method, params)) |result| {
            return RouteMatch{
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
    pub fn releaseMatch(self: *TrieRouter, match: RouteMatch) void {
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

test "TrieRouter basic functionality" {
    var router = try TrieRouter.init(std.testing.allocator);
    defer router.deinit();

    const testHandler = struct {
        fn handler(event: *H3Event) !void {
            _ = event;
        }
    }.handler;

    // Add routes
    try router.addRoute(.GET, "/", testHandler);
    try router.addRoute(.GET, "/users/:id", testHandler);
    try router.addRoute(.POST, "/users", testHandler);
    try router.addRoute(.GET, "/static/*", testHandler);

    // Test exact match
    const match1 = router.findRoute(.GET, "/");
    try std.testing.expect(match1 != null);
    router.releaseMatch(match1.?);

    // Test parameter match
    const match2 = router.findRoute(.GET, "/users/123");
    try std.testing.expect(match2 != null);
    try std.testing.expectEqualStrings("123", match2.?.params.get("id").?);
    router.releaseMatch(match2.?);

    // Test wildcard match
    const match3 = router.findRoute(.GET, "/static/css/style.css");
    try std.testing.expect(match3 != null);
    router.releaseMatch(match3.?);

    // Test no match
    const match4 = router.findRoute(.GET, "/nonexistent");
    try std.testing.expect(match4 == null);
}
