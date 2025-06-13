//! Core interfaces for H3 framework
//! This module defines interfaces to break circular dependencies

const std = @import("std");
const H3Event = @import("event.zig").H3Event;
const Handler = @import("router.zig").Handler;

/// Interface for middleware execution context
/// This allows middleware to call next() without knowing the concrete app type
pub const MiddlewareContext = struct {
    ptr: *anyopaque,
    nextFn: *const fn (*anyopaque, *H3Event, usize, Handler) anyerror!void,

    /// Call the next middleware in the chain
    pub fn next(self: MiddlewareContext, event: *H3Event, index: usize, final_handler: Handler) !void {
        try self.nextFn(self.ptr, event, index, final_handler);
    }
};

/// Middleware function type with clean interface
pub const Middleware = *const fn (*H3Event, MiddlewareContext, usize, Handler) anyerror!void;

/// Create a middleware context from an H3 app
pub fn createMiddlewareContext(app: anytype) MiddlewareContext {
    const AppType = @TypeOf(app.*); // Get the type of what the pointer points to

    const impl = struct {
        fn nextImpl(ptr: *anyopaque, event: *H3Event, index: usize, final_handler: Handler) !void {
            const typed_app: *AppType = @ptrCast(@alignCast(ptr));
            try typed_app.next(event, index, final_handler);
        }
    };

    return MiddlewareContext{
        .ptr = app,
        .nextFn = impl.nextImpl,
    };
}
