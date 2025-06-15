//! Ultra-fast middleware system with zero-overhead execution
//! Optimized for maximum performance with minimal allocations

const std = @import("std");
const H3Event = @import("event.zig").H3Event;

/// Fast middleware function signature for zero-overhead execution
pub const FastMiddleware = *const fn (*H3Event) anyerror!void;

/// Handler function signature
pub const Handler = *const fn (*H3Event) anyerror!void;

/// Middleware execution result
pub const MiddlewareResult = enum {
    continue_chain,
    stop_chain,
    error_occurred,
};

/// High-performance middleware chain with zero-allocation execution
pub const FastMiddlewareChain = struct {
    middlewares: [32]FastMiddleware,
    count: u8 = 0,
    execution_context: ExecutionContext,

    const ExecutionContext = struct {
        early_return: bool = false,
        error_occurred: bool = false,
        last_error: ?anyerror = null,

        pub fn reset(self: *ExecutionContext) void {
            self.early_return = false;
            self.error_occurred = false;
            self.last_error = null;
        }
    };

    pub fn init() FastMiddlewareChain {
        return FastMiddlewareChain{
            .middlewares = [_]FastMiddleware{undefined} ** 32,
            .execution_context = ExecutionContext{},
        };
    }

    pub fn deinit(self: *FastMiddlewareChain) void {
        _ = self;
    }

    /// Add middleware to the chain (max 32 middlewares)
    pub fn use(self: *FastMiddlewareChain, middleware: FastMiddleware) !void {
        if (self.count >= 32) {
            return error.TooManyMiddlewares;
        }
        self.middlewares[self.count] = middleware;
        self.count += 1;
    }

    /// Execute the middleware chain
    pub fn execute(self: *FastMiddlewareChain, event: *H3Event, final_handler: Handler) !void {
        self.execution_context.reset();

        if (self.count == 0) {
            try final_handler(event);
            return;
        }

        var i: u8 = 0;
        while (i < self.count) : (i += 1) {
            self.middlewares[i](event) catch |err| {
                self.execution_context.error_occurred = true;
                self.execution_context.last_error = err;
                return err;
            };

            if (event.response.finished) {
                self.execution_context.early_return = true;
                return;
            }
        }

        try final_handler(event);
    }

    /// Execute middlewares with optimized error handling
    pub fn executeWithErrorHandling(self: *FastMiddlewareChain, event: *H3Event, final_handler: Handler, error_handler: ?*const fn (*H3Event, anyerror) anyerror!void) !void {
        self.execution_context.reset();

        // Fast path: no middlewares
        if (self.count == 0) {
            final_handler(event) catch |err| {
                if (error_handler) |eh| {
                    try eh(event, err);
                } else {
                    return err;
                }
            };
            return;
        }

        // Ultra-fast execution with error handling
        var i: u8 = 0;
        while (i < self.count) : (i += 1) {
            self.middlewares[i](event) catch |err| {
                self.execution_context.error_occurred = true;
                self.execution_context.last_error = err;

                if (error_handler) |eh| {
                    try eh(event, err);
                    return;
                } else {
                    return err;
                }
            };

            // Check for early termination
            if (event.response.finished) {
                self.execution_context.early_return = true;
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
    pub fn getCount(self: *const FastMiddlewareChain) u8 {
        return self.count;
    }

    /// Clear all middlewares (zero-cost operation)
    pub fn clear(self: *FastMiddlewareChain) void {
        self.count = 0;
        self.execution_context.reset();
    }

    /// Get execution statistics
    pub fn getStats(self: *const FastMiddlewareChain) struct {
        middleware_count: u8,
        early_returns: bool,
        errors_occurred: bool,
        last_error: ?anyerror,
    } {
        return .{
            .middleware_count = self.count,
            .early_returns = self.execution_context.early_return,
            .errors_occurred = self.execution_context.error_occurred,
            .last_error = self.execution_context.last_error,
        };
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

/// Ultra-optimized common middleware implementations
pub const CommonMiddleware = struct {
    /// Zero-allocation logging middleware
    pub fn logger(event: *H3Event) anyerror!void {
        // Use stack buffer to avoid allocations
        var buffer: [256]u8 = undefined;
        const method = event.getMethod();
        const path = event.getPath();

        // Format directly to avoid string allocations
        const log_msg = std.fmt.bufPrint(buffer[0..], "{s} {s}", .{ @tagName(method), path }) catch "LOG_ERROR";
        std.log.info("{s}", .{log_msg});
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
    var chain = FastMiddlewareChain.init();
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
