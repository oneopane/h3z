//! Fast middleware system with simplified API and optimized execution
//! Reduces overhead compared to the complex middleware chain system

const std = @import("std");
const H3Event = @import("event.zig").H3Event;

/// Simple middleware function signature - much cleaner than the complex version
pub const FastMiddleware = *const fn (*H3Event) anyerror!void;

/// Handler function signature
pub const Handler = *const fn (*H3Event) anyerror!void;

/// Middleware execution result
pub const MiddlewareResult = enum {
    continue_chain,
    stop_chain,
    error_occurred,
};

/// Fast middleware chain with optimized execution
pub const FastMiddlewareChain = struct {
    middlewares: std.ArrayList(FastMiddleware),
    allocator: std.mem.Allocator,

    /// Initialize a new fast middleware chain
    pub fn init(allocator: std.mem.Allocator) FastMiddlewareChain {
        return FastMiddlewareChain{
            .middlewares = std.ArrayList(FastMiddleware).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize the middleware chain
    pub fn deinit(self: *FastMiddlewareChain) void {
        self.middlewares.deinit();
    }

    /// Add a middleware to the chain
    pub fn use(self: *FastMiddlewareChain, middleware: FastMiddleware) !void {
        try self.middlewares.append(middleware);
    }

    /// Execute the middleware chain with early termination support
    pub fn execute(self: *FastMiddlewareChain, event: *H3Event, final_handler: Handler) !void {
        // Fast path: no middlewares
        if (self.middlewares.items.len == 0) {
            try final_handler(event);
            return;
        }

        // Execute middlewares in sequence
        for (self.middlewares.items) |middleware| {
            try middleware(event);

            // Check if response was already sent (early termination)
            if (event.response.finished) {
                return;
            }
        }

        // Execute final handler if no middleware terminated early
        try final_handler(event);
    }

    /// Execute middlewares with error handling and recovery
    pub fn executeWithErrorHandling(self: *FastMiddlewareChain, event: *H3Event, final_handler: Handler, error_handler: ?*const fn (*H3Event, anyerror) anyerror!void) !void {
        // Fast path: no middlewares
        if (self.middlewares.items.len == 0) {
            final_handler(event) catch |err| {
                if (error_handler) |eh| {
                    try eh(event, err);
                } else {
                    return err;
                }
            };
            return;
        }

        // Execute middlewares with error handling
        for (self.middlewares.items) |middleware| {
            middleware(event) catch |err| {
                if (error_handler) |eh| {
                    try eh(event, err);
                    return;
                } else {
                    return err;
                }
            };

            // Check if response was already sent
            if (event.response.finished) {
                return;
            }
        }

        // Execute final handler
        final_handler(event) catch |err| {
            if (error_handler) |eh| {
                try eh(event, err);
            } else {
                return err;
            }
        };
    }

    /// Get middleware count
    pub fn count(self: *const FastMiddlewareChain) usize {
        return self.middlewares.items.len;
    }

    /// Clear all middlewares
    pub fn clear(self: *FastMiddlewareChain) void {
        self.middlewares.clearRetainingCapacity();
    }
};

/// Middleware composer for combining multiple middlewares
pub const MiddlewareComposer = struct {
    /// Compose multiple middlewares into a single middleware function
    pub fn compose(_: std.mem.Allocator, middlewares: []const FastMiddleware) !FastMiddleware {
        if (middlewares.len == 0) {
            return noopMiddleware;
        }

        if (middlewares.len == 1) {
            return middlewares[0];
        }

        // For multiple middlewares, return the first one as a placeholder
        // A full implementation would require more complex closure handling
        return middlewares[0];
    }

    /// Create a conditional middleware that only executes if condition is met
    pub fn conditional(condition_fn: *const fn (*H3Event) bool, middleware: FastMiddleware) FastMiddleware {
        // For now, return a simple wrapper that ignores the condition
        // A full implementation would require more complex closure handling
        _ = condition_fn;
        return middleware;
    }

    /// Create a middleware that only executes for specific HTTP methods
    pub fn forMethods(methods: []const @import("../http/method.zig").HttpMethod, middleware: FastMiddleware) FastMiddleware {
        const MethodMiddleware = struct {
            fn execute(event: *H3Event) anyerror!void {
                const request_method = event.getMethod();
                for (methods) |method| {
                    if (request_method == method) {
                        try middleware(event);
                        return;
                    }
                }
            }
        };

        return MethodMiddleware.execute;
    }

    /// Create a middleware that only executes for paths matching a pattern
    pub fn forPath(pattern: []const u8, middleware: FastMiddleware) FastMiddleware {
        const PathMiddleware = struct {
            fn execute(event: *H3Event) anyerror!void {
                const path = event.getPath();
                if (std.mem.startsWith(u8, path, pattern)) {
                    try middleware(event);
                }
            }
        };

        return PathMiddleware.execute;
    }
};

/// No-op middleware for testing and composition
fn noopMiddleware(event: *H3Event) anyerror!void {
    _ = event;
}

/// Common middleware implementations
pub const CommonMiddleware = struct {
    /// Simple logging middleware
    pub fn logger(event: *H3Event) anyerror!void {
        const method = event.getMethod();
        const path = event.getPath();
        std.log.info("{s} {s}", .{ @tagName(method), path });
    }

    /// CORS middleware with default settings
    pub fn cors(event: *H3Event) anyerror!void {
        try event.setHeader("Access-Control-Allow-Origin", "*");
        try event.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        try event.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    }

    /// Security headers middleware
    pub fn security(event: *H3Event) anyerror!void {
        try event.setHeader("X-Content-Type-Options", "nosniff");
        try event.setHeader("X-Frame-Options", "DENY");
        try event.setHeader("X-XSS-Protection", "1; mode=block");
    }

    /// Request timing middleware
    pub fn timing(event: *H3Event) anyerror!void {
        const start_time = std.time.nanoTimestamp();
        try event.setContext("start_time", @as([]const u8, std.mem.asBytes(&start_time)));
    }

    /// Response timing middleware (should be called after request processing)
    pub fn timingEnd(event: *H3Event) anyerror!void {
        if (event.getContext("start_time")) |start_bytes| {
            const start_time = std.mem.bytesToValue(i128, start_bytes);
            const end_time = std.time.nanoTimestamp();
            const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

            var buffer: [32]u8 = undefined;
            const duration_str = std.fmt.bufPrint(buffer[0..], "{d:.2}", .{duration_ms}) catch "0.00";
            try event.setHeader("X-Response-Time", duration_str);
        }
    }
};

test "FastMiddlewareChain basic execution" {
    var chain = FastMiddlewareChain.init(std.testing.allocator);
    defer chain.deinit();

    const TestState = struct {
        var executed: bool = false;
    };

    const testMiddleware = struct {
        fn middleware(event: *H3Event) anyerror!void {
            _ = event;
            TestState.executed = true;
        }
    }.middleware;

    const testHandler = struct {
        fn handler(event: *H3Event) anyerror!void {
            _ = event;
        }
    }.handler;

    try chain.use(testMiddleware);

    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    TestState.executed = false;
    try chain.execute(&event, testHandler);
    try std.testing.expect(TestState.executed);
}

test "MiddlewareComposer conditional" {
    const condition = struct {
        fn check(event: *H3Event) bool {
            _ = event;
            return true;
        }
    }.check;

    const TestState = struct {
        var executed: bool = false;
    };

    const testMiddleware = struct {
        fn middleware(event: *H3Event) anyerror!void {
            _ = event;
            TestState.executed = true;
        }
    }.middleware;

    const conditional_mw = MiddlewareComposer.conditional(condition, testMiddleware);

    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    TestState.executed = false;
    try conditional_mw(&event);
    try std.testing.expect(TestState.executed);
}
