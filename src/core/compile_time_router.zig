//! Compile-time route analysis and optimization
//! Provides zero-runtime-cost route matching for static routes

const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;
const H3Event = @import("event.zig").H3Event;

/// Handler function type
pub const Handler = *const fn (*H3Event) anyerror!void;

/// Compile-time route information
pub const RouteInfo = struct {
    method: HttpMethod,
    path: []const u8,
    handler: Handler,
    is_static: bool,
    param_count: u8,
    has_wildcard: bool,

    pub fn analyze(method: HttpMethod, path: []const u8, handler: Handler) RouteInfo {
        var param_count: u8 = 0;
        var has_wildcard = false;
        var is_static = true;

        var i: usize = 0;
        while (i < path.len) {
            if (path[i] == ':') {
                param_count += 1;
                is_static = false;
                // Skip to next segment
                while (i < path.len and path[i] != '/') i += 1;
            } else if (path[i] == '*') {
                has_wildcard = true;
                is_static = false;
                break;
            } else {
                i += 1;
            }
        }

        return RouteInfo{
            .method = method,
            .path = path,
            .handler = handler,
            .is_static = is_static,
            .param_count = param_count,
            .has_wildcard = has_wildcard,
        };
    }

    pub fn priority(self: RouteInfo) u8 {
        // Static routes have highest priority
        if (self.is_static) return 100;

        // Routes with fewer parameters have higher priority
        if (self.has_wildcard) return 10;

        return 50 - self.param_count;
    }
};

/// Compile-time route matcher for maximum performance
pub fn CompileTimeRouter(comptime routes: []const RouteInfo) type {
    // Sort routes by priority at compile time
    const sorted_routes = comptime blk: {
        var sorted = routes[0..routes.len].*;

        // Simple bubble sort for compile time
        var i: usize = 0;
        while (i < sorted.len) : (i += 1) {
            var j: usize = 0;
            while (j < sorted.len - 1 - i) : (j += 1) {
                if (sorted[j].priority() < sorted[j + 1].priority()) {
                    const temp = sorted[j];
                    sorted[j] = sorted[j + 1];
                    sorted[j + 1] = temp;
                }
            }
        }

        break :blk sorted;
    };

    // Separate static routes for O(1) lookup
    const static_routes = comptime blk: {
        var static_list: [routes.len]RouteInfo = undefined;
        var count: usize = 0;

        for (sorted_routes) |route| {
            if (route.is_static) {
                static_list[count] = route;
                count += 1;
            }
        }

        break :blk static_list[0..count];
    };

    // Dynamic routes for pattern matching
    const dynamic_routes = comptime blk: {
        var dynamic_list: [routes.len]RouteInfo = undefined;
        var count: usize = 0;

        for (sorted_routes) |route| {
            if (!route.is_static) {
                dynamic_list[count] = route;
                count += 1;
            }
        }

        break :blk dynamic_list[0..count];
    };

    return struct {
        const Self = @This();

        // Compile-time generated perfect hash for static routes
        const StaticRouteMap = std.ComptimeStringMap(Handler, blk: {
            var map_entries: [static_routes.len]struct { []const u8, Handler } = undefined;

            for (static_routes, 0..) |route, i| {
                // Create composite key: "METHOD:PATH"
                const key = std.fmt.comptimePrint("{s}:{s}", .{ @tagName(route.method), route.path });
                map_entries[i] = .{ key, route.handler };
            }

            break :blk map_entries;
        });

        /// Ultra-fast route matching with compile-time optimization
        pub fn findRoute(method: HttpMethod, path: []const u8, params: anytype) ?Handler {
            // Try static routes first (O(1) perfect hash lookup)
            const static_key = std.fmt.comptimePrint("{s}:{s}", .{ @tagName(method), path });
            if (StaticRouteMap.get(static_key)) |handler| {
                return handler;
            }

            // Try dynamic routes (compile-time optimized pattern matching)
            inline for (dynamic_routes) |route| {
                if (route.method == method) {
                    if (matchPattern(route.path, path, params)) {
                        return route.handler;
                    }
                }
            }

            return null;
        }

        /// Compile-time optimized pattern matching
        fn matchPattern(comptime pattern: []const u8, path: []const u8, params: anytype) bool {
            comptime var pattern_segments: [16][]const u8 = undefined;
            comptime var segment_types: [16]enum { static, param, wildcard } = undefined;
            comptime var param_names: [16][]const u8 = undefined;
            comptime var segment_count: usize = 0;

            // Parse pattern at compile time
            comptime {
                var pattern_iter = std.mem.splitScalar(u8, pattern, '/');
                while (pattern_iter.next()) |segment| {
                    if (segment.len == 0) continue;

                    pattern_segments[segment_count] = segment;

                    if (std.mem.startsWith(u8, segment, ":")) {
                        segment_types[segment_count] = .param;
                        param_names[segment_count] = segment[1..];
                    } else if (std.mem.eql(u8, segment, "*")) {
                        segment_types[segment_count] = .wildcard;
                    } else {
                        segment_types[segment_count] = .static;
                    }

                    segment_count += 1;
                }
            }

            // Runtime matching with compile-time optimized loop
            var path_iter = std.mem.splitScalar(u8, path, '/');
            var path_segment_index: usize = 0;

            while (path_iter.next()) |path_segment| {
                if (path_segment.len == 0) continue;

                if (path_segment_index >= segment_count) {
                    return false;
                }

                switch (segment_types[path_segment_index]) {
                    .static => {
                        if (!std.mem.eql(u8, pattern_segments[path_segment_index], path_segment)) {
                            return false;
                        }
                    },
                    .param => {
                        // Store parameter
                        params.put(param_names[path_segment_index], path_segment) catch return false;
                    },
                    .wildcard => {
                        return true; // Wildcard matches everything
                    },
                }

                path_segment_index += 1;
            }

            return path_segment_index == segment_count;
        }

        /// Get compile-time route statistics
        pub fn getCompileTimeStats() struct {
            total_routes: usize,
            static_routes: usize,
            dynamic_routes: usize,
            max_params: u8,
        } {
            comptime var max_params: u8 = 0;
            comptime {
                for (routes) |route| {
                    if (route.param_count > max_params) {
                        max_params = route.param_count;
                    }
                }
            }

            return .{
                .total_routes = routes.len,
                .static_routes = static_routes.len,
                .dynamic_routes = dynamic_routes.len,
                .max_params = max_params,
            };
        }

        /// Generate optimized route lookup code at compile time
        pub fn generateOptimizedLookup(comptime writer: anytype) !void {
            try writer.print("// Auto-generated optimized route lookup\n");
            try writer.print("pub fn fastRouteLookup(method: HttpMethod, path: []const u8) ?Handler {{\n");

            // Generate static route checks
            try writer.print("    // Static routes (O(1) lookup)\n");
            inline for (static_routes) |route| {
                try writer.print("    if (method == .{s} and std.mem.eql(u8, path, \"{s}\")) return {s};\n", .{ @tagName(route.method), route.path, @typeName(@TypeOf(route.handler)) });
            }

            // Generate dynamic route checks
            try writer.print("    // Dynamic routes (optimized pattern matching)\n");
            inline for (dynamic_routes) |route| {
                try writer.print("    if (method == .{s}) {{\n", .{@tagName(route.method)});
                try writer.print("        if (matchPattern_{s}(path)) return {s};\n", .{ @tagName(route.method), @typeName(@TypeOf(route.handler)) });
                try writer.print("    }}\n");
            }

            try writer.print("    return null;\n");
            try writer.print("}}\n");
        }
    };
}

test "CompileTimeRouter performance" {
    const testHandler1 = struct {
        fn handler(event: *H3Event) !void {
            _ = event;
        }
    }.handler;

    const testHandler2 = struct {
        fn handler(event: *H3Event) !void {
            _ = event;
        }
    }.handler;

    const routes = [_]RouteInfo{
        RouteInfo.analyze(.GET, "/", testHandler1),
        RouteInfo.analyze(.GET, "/users/:id", testHandler2),
        RouteInfo.analyze(.POST, "/users", testHandler1),
        RouteInfo.analyze(.GET, "/static/*", testHandler2),
    };

    const Router = CompileTimeRouter(routes);

    var params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(std.testing.allocator);
    defer params.deinit();

    // Test static route
    const handler1 = Router.findRoute(.GET, "/", params);
    try std.testing.expect(handler1 == testHandler1);

    // Test parameter route
    const handler2 = Router.findRoute(.GET, "/users/123", params);
    try std.testing.expect(handler2 == testHandler2);
    try std.testing.expectEqualStrings("123", params.get("id").?);

    // Test compile-time stats
    const stats = Router.getCompileTimeStats();
    try std.testing.expect(stats.total_routes == 4);
    try std.testing.expect(stats.static_routes == 2);
    try std.testing.expect(stats.dynamic_routes == 2);
}
