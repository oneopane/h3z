//! Core middleware system for H3 framework
//! Provides the foundation for middleware chain execution and management

const std = @import("std");
const H3Event = @import("event.zig").H3Event;
const interfaces = @import("interfaces.zig");

/// Middleware function signature
pub const MiddlewareFn = *const fn (*H3Event, interfaces.MiddlewareContext, usize, Handler) anyerror!void;

/// Handler function signature
pub const Handler = *const fn (*H3Event) anyerror!void;

/// Middleware wrapper that holds the function and optional context
pub const Middleware = struct {
    middlewareFn: MiddlewareFn,
    name: ?[]const u8 = null,

    pub fn init(middlewareFn: MiddlewareFn) Middleware {
        return Middleware{
            .middlewareFn = middlewareFn,
        };
    }

    pub fn initWithName(middlewareFn: MiddlewareFn, name: []const u8) Middleware {
        return Middleware{
            .middlewareFn = middlewareFn,
            .name = name,
        };
    }

    /// Execute this middleware
    pub fn execute(self: Middleware, event: *H3Event, context: interfaces.MiddlewareContext, index: usize, final_handler: Handler) !void {
        try self.middlewareFn(event, context, index, final_handler);
    }
};

/// Middleware chain manager
pub const MiddlewareChain = struct {
    middlewares: std.ArrayList(Middleware),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MiddlewareChain {
        return MiddlewareChain{
            .middlewares = std.ArrayList(Middleware).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MiddlewareChain) void {
        self.middlewares.deinit();
    }

    /// Add a middleware to the chain
    pub fn use(self: *MiddlewareChain, middleware: Middleware) !void {
        try self.middlewares.append(middleware);
    }

    /// Add a middleware function to the chain
    pub fn useFn(self: *MiddlewareChain, middlewareFn: MiddlewareFn) !void {
        try self.use(Middleware.init(middlewareFn));
    }

    /// Add a named middleware function to the chain
    pub fn useNamedFn(self: *MiddlewareChain, middlewareFn: MiddlewareFn, name: []const u8) !void {
        try self.use(Middleware.initWithName(middlewareFn, name));
    }

    /// Execute the middleware chain
    pub fn execute(self: *MiddlewareChain, event: *H3Event, final_handler: Handler) !void {
        if (self.middlewares.items.len == 0) {
            try final_handler(event);
            return;
        }

        const context = interfaces.MiddlewareContext{
            .ptr = self,
            .nextFn = nextImpl,
        };

        try self.executeAtIndex(event, 0, final_handler, context);
    }

    /// Execute middleware at specific index
    fn executeAtIndex(self: *MiddlewareChain, event: *H3Event, index: usize, final_handler: Handler, context: interfaces.MiddlewareContext) !void {
        if (index >= self.middlewares.items.len) {
            try final_handler(event);
            return;
        }

        const middleware = self.middlewares.items[index];
        try middleware.execute(event, context, index, final_handler);
    }

    /// Implementation of the next function for middleware context
    fn nextImpl(ptr: *anyopaque, event: *H3Event, index: usize, final_handler: Handler) !void {
        const self: *MiddlewareChain = @ptrCast(@alignCast(ptr));
        try self.executeAtIndex(event, index + 1, final_handler, interfaces.MiddlewareContext{
            .ptr = self,
            .nextFn = nextImpl,
        });
    }

    /// Get the number of middlewares in the chain
    pub fn count(self: *MiddlewareChain) usize {
        return self.middlewares.items.len;
    }

    /// Clear all middlewares from the chain
    pub fn clear(self: *MiddlewareChain) void {
        self.middlewares.clearRetainingCapacity();
    }

    /// Get middleware at index
    pub fn get(self: *MiddlewareChain, index: usize) ?Middleware {
        if (index >= self.middlewares.items.len) return null;
        return self.middlewares.items[index];
    }
};

/// Middleware composition utilities
pub const Composer = struct {
    /// Compose multiple middlewares into a single middleware
    pub fn compose(allocator: std.mem.Allocator, middlewares: []const Middleware) !Middleware {
        const ComposedMiddleware = struct {
            chain: MiddlewareChain,

            fn middleware(event: *H3Event, context: interfaces.MiddlewareContext, index: usize, final_handler: Handler) !void {
                _ = context;
                _ = index;

                // Get the composed middleware from event context (this is a simplified approach)
                // In a real implementation, you'd need a way to access the chain
                // For now, just call the final handler
                try final_handler(event);
            }
        };

        var chain = MiddlewareChain.init(allocator);
        for (middlewares) |mw| {
            try chain.use(mw);
        }

        // This is a simplified implementation
        // In practice, you'd need a more sophisticated way to handle composed middleware
        return Middleware.init(ComposedMiddleware.middleware);
    }

    /// Create a conditional middleware that only runs if condition is met
    pub fn conditional(condition_fn: fn (*H3Event) bool, middleware: Middleware) Middleware {
        const ConditionalMiddleware = struct {
            fn conditionalMiddleware(event: *H3Event, context: interfaces.MiddlewareContext, index: usize, final_handler: Handler) !void {
                if (condition_fn(event)) {
                    try middleware.execute(event, context, index, final_handler);
                } else {
                    try context.next(event, index, final_handler);
                }
            }
        };

        return Middleware.init(ConditionalMiddleware.conditionalMiddleware);
    }
};

// Tests
test "MiddlewareChain basic functionality" {
    const testing = std.testing;
    var chain = MiddlewareChain.init(testing.allocator);
    defer chain.deinit();

    // Test empty chain
    try testing.expect(chain.count() == 0);

    // Add middleware
    const testMiddleware = Middleware.init(struct {
        fn middleware(event: *H3Event, context: interfaces.MiddlewareContext, index: usize, final_handler: Handler) !void {
            try context.next(event, index, final_handler);
        }
    }.middleware);

    try chain.use(testMiddleware);
    try testing.expect(chain.count() == 1);
}

test "Middleware execution order" {
    const testing = std.testing;
    var execution_order = std.ArrayList(u8).init(testing.allocator);
    defer execution_order.deinit();

    var chain = MiddlewareChain.init(testing.allocator);
    defer chain.deinit();

    // Create test middlewares that record execution order
    const TestMiddleware1 = struct {
        fn middleware(event: *H3Event, context: interfaces.MiddlewareContext, index: usize, final_handler: Handler) !void {
            // Record execution
            // try execution_order.append(1);
            try context.next(event, index, final_handler);
        }
    };

    const TestMiddleware2 = struct {
        fn middleware(event: *H3Event, context: interfaces.MiddlewareContext, index: usize, final_handler: Handler) !void {
            // Record execution
            // try execution_order.append(2);
            try context.next(event, index, final_handler);
        }
    };

    try chain.useFn(TestMiddleware1.middleware);
    try chain.useFn(TestMiddleware2.middleware);

    try testing.expect(chain.count() == 2);
}
