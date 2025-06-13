//! Handler types and utilities for H3 framework
//! Defines the core handler interfaces and common handler patterns

const std = @import("std");
const H3Event = @import("event.zig").H3Event;
const HttpMethod = @import("../http/method.zig").HttpMethod;
const HttpStatus = @import("../http/status.zig").HttpStatus;

/// Basic handler function signature
pub const Handler = *const fn (*H3Event) anyerror!void;

/// Async handler function signature (for future async support)
pub const AsyncHandler = *const fn (*H3Event) anyerror!void;

/// Error handler function signature
pub const ErrorHandler = *const fn (*H3Event, anyerror) anyerror!void;

/// Handler with context data
pub const ContextHandler = struct {
    handler: Handler,
    context: ?*anyopaque = null,
    name: ?[]const u8 = null,

    pub fn init(handler: Handler) ContextHandler {
        return ContextHandler{
            .handler = handler,
        };
    }

    pub fn initWithContext(handler: Handler, context: *anyopaque) ContextHandler {
        return ContextHandler{
            .handler = handler,
            .context = context,
        };
    }

    pub fn initWithName(handler: Handler, name: []const u8) ContextHandler {
        return ContextHandler{
            .handler = handler,
            .name = name,
        };
    }

    pub fn call(self: ContextHandler, event: *H3Event) !void {
        try self.handler(event);
    }
};

/// Handler registry for organizing handlers
pub const HandlerRegistry = struct {
    handlers: std.HashMap([]const u8, ContextHandler, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HandlerRegistry {
        return HandlerRegistry{
            .handlers = std.HashMap([]const u8, ContextHandler, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HandlerRegistry) void {
        self.handlers.deinit();
    }

    /// Register a handler with a name
    pub fn register(self: *HandlerRegistry, name: []const u8, handler: Handler) !void {
        try self.handlers.put(name, ContextHandler.initWithName(handler, name));
    }

    /// Register a context handler
    pub fn registerContext(self: *HandlerRegistry, name: []const u8, context_handler: ContextHandler) !void {
        try self.handlers.put(name, context_handler);
    }

    /// Get a handler by name
    pub fn get(self: *HandlerRegistry, name: []const u8) ?ContextHandler {
        return self.handlers.get(name);
    }

    /// Remove a handler
    pub fn remove(self: *HandlerRegistry, name: []const u8) bool {
        return self.handlers.remove(name);
    }

    /// Check if a handler exists
    pub fn has(self: *HandlerRegistry, name: []const u8) bool {
        return self.handlers.contains(name);
    }

    /// Get all handler names
    pub fn getNames(self: *HandlerRegistry, allocator: std.mem.Allocator) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        var iterator = self.handlers.iterator();
        while (iterator.next()) |entry| {
            try names.append(entry.key_ptr.*);
        }
        return names.toOwnedSlice();
    }
};

/// Common handler patterns and utilities
pub const Handlers = struct {
    /// Create a simple text response handler
    pub fn text(comptime response_text: []const u8) Handler {
        return struct {
            fn handler(event: *H3Event) !void {
                try event.sendText(response_text);
            }
        }.handler;
    }

    /// Create a JSON response handler
    pub fn json(comptime T: type, data: T) Handler {
        return struct {
            fn handler(event: *H3Event) !void {
                try event.sendJsonValue(data);
            }
        }.handler;
    }

    /// Create a status-only response handler
    pub fn status(comptime http_status: HttpStatus) Handler {
        return struct {
            fn handler(event: *H3Event) !void {
                event.setStatus(http_status);
                try event.sendText("");
            }
        }.handler;
    }

    /// Create a redirect handler
    pub fn redirect(comptime url: []const u8, comptime http_status: HttpStatus) Handler {
        return struct {
            fn handler(event: *H3Event) !void {
                event.setStatus(http_status);
                try event.setHeader("Location", url);
                try event.sendText("");
            }
        }.handler;
    }

    /// Create a method-specific handler wrapper
    pub fn methodGuard(method: HttpMethod, handler: Handler) Handler {
        return struct {
            fn guardedHandler(event: *H3Event) !void {
                if (event.getMethod() != method) {
                    event.setStatus(.method_not_allowed);
                    try event.sendText("Method Not Allowed");
                    return;
                }
                try handler(event);
            }
        }.guardedHandler;
    }

    /// Create a handler that serves static content
    pub fn staticContent(comptime content_type: []const u8, comptime content: []const u8) Handler {
        return struct {
            fn handler(event: *H3Event) !void {
                try event.setHeader("Content-Type", content_type);
                try event.sendText(content);
            }
        }.handler;
    }

    /// Create an error handler that returns JSON error responses
    pub fn jsonError(comptime http_status: HttpStatus, comptime message: []const u8) Handler {
        return struct {
            fn handler(event: *H3Event) !void {
                event.setStatus(http_status);
                const error_response = .{
                    .@"error" = @tagName(http_status),
                    .message = message,
                    .status = http_status.code(),
                };
                try event.sendJsonValue(error_response);
            }
        }.handler;
    }

    /// Create a CORS preflight handler
    pub fn corsPreflightHandler(comptime origin: []const u8, comptime methods: []const u8, comptime headers: []const u8) Handler {
        return struct {
            fn handler(event: *H3Event) !void {
                try event.setHeader("Access-Control-Allow-Origin", origin);
                try event.setHeader("Access-Control-Allow-Methods", methods);
                try event.setHeader("Access-Control-Allow-Headers", headers);
                try event.setHeader("Access-Control-Max-Age", "86400");
                event.setStatus(.no_content);
                try event.sendText("");
            }
        }.handler;
    }

    /// Create a health check handler
    pub fn healthCheck(comptime service_name: []const u8) Handler {
        return struct {
            fn handler(event: *H3Event) !void {
                const health = .{
                    .status = "healthy",
                    .service = service_name,
                    .timestamp = std.time.timestamp(),
                    .uptime = "running",
                };
                try event.sendJsonValue(health);
            }
        }.handler;
    }
};

/// Handler composition utilities
pub const Composition = struct {
    /// Compose multiple handlers with fallback logic
    pub fn fallback(primary: Handler, fallback_handler: Handler) Handler {
        return struct {
            fn composedHandler(event: *H3Event) !void {
                primary(event) catch {
                    try fallback_handler(event);
                };
            }
        }.composedHandler;
    }

    /// Create a conditional handler
    pub fn conditional(condition_fn: fn (*H3Event) bool, true_handler: Handler, false_handler: Handler) Handler {
        return struct {
            fn conditionalHandler(event: *H3Event) !void {
                if (condition_fn(event)) {
                    try true_handler(event);
                } else {
                    try false_handler(event);
                }
            }
        }.conditionalHandler;
    }

    /// Create a handler that logs execution time
    pub fn timed(handler: Handler, comptime name: []const u8) Handler {
        return struct {
            fn timedHandler(event: *H3Event) !void {
                const start = std.time.milliTimestamp();
                try handler(event);
                const duration = std.time.milliTimestamp() - start;
                std.log.info("Handler '{s}' executed in {}ms", .{ name, duration });
            }
        }.timedHandler;
    }
};

// Tests
test "ContextHandler basic functionality" {
    const testing = std.testing;

    const testHandler = struct {
        fn handler(event: *H3Event) !void {
            _ = event;
            // Test handler does nothing
        }
    }.handler;

    const context_handler = ContextHandler.init(testHandler);
    try testing.expect(context_handler.context == null);
    try testing.expect(context_handler.name == null);
}

test "HandlerRegistry operations" {
    const testing = std.testing;
    var registry = HandlerRegistry.init(testing.allocator);
    defer registry.deinit();

    const testHandler = struct {
        fn handler(event: *H3Event) !void {
            _ = event;
        }
    }.handler;

    // Test registration
    try registry.register("test", testHandler);
    try testing.expect(registry.has("test"));

    // Test retrieval
    const retrieved = registry.get("test");
    try testing.expect(retrieved != null);

    // Test removal
    try testing.expect(registry.remove("test"));
    try testing.expect(!registry.has("test"));
}

test "Handler patterns" {
    // Test text handler creation
    const text_handler = Handlers.text("Hello, World!");
    _ = text_handler;

    // Test status handler creation
    const status_handler = Handlers.status(.ok);
    _ = status_handler;

    // Test redirect handler creation
    const redirect_handler = Handlers.redirect("/new-path", .found);
    _ = redirect_handler;
}
