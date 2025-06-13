//! H3 - Zero-dependency HTTP framework for Zig
//!
//! H3 is a fast, lightweight HTTP framework inspired by H3.js but built specifically for Zig.
//! It provides a clean API for building web applications and APIs with zero external dependencies.
//!
//! ## Quick Start
//!
//! ```zig
//! const std = @import("std");
//! const h3 = @import("h3");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!     const allocator = gpa.allocator();
//!
//!     var app = h3.createApp(allocator);
//!     defer app.deinit();
//!
//!     _ = app.get("/", homeHandler);
//!     _ = app.post("/api/users", createUserHandler);
//!
//!     try h3.serve(app, .{ .port = 3000 });
//! }
//!
//! fn homeHandler(event: *h3.Event) !void {
//!     try h3.sendText(event, "Hello, H3!");
//! }
//! ```

const std = @import("std");

// Re-export core types and functions
pub const App = @import("core/app.zig").H3;
pub const Event = @import("core/event.zig").H3Event;
pub const Handler = @import("core/handler.zig").Handler;
pub const ContextHandler = @import("core/handler.zig").ContextHandler;
pub const HandlerRegistry = @import("core/handler.zig").HandlerRegistry;
pub const Middleware = @import("core/middleware.zig").Middleware;
pub const MiddlewareChain = @import("core/middleware.zig").MiddlewareChain;
pub const MiddlewareContext = @import("core/interfaces.zig").MiddlewareContext;

// Re-export HTTP types
pub const HttpMethod = @import("http/method.zig").HttpMethod;
pub const HttpStatus = @import("http/status.zig").HttpStatus;
pub const Request = @import("http/request.zig").Request;
pub const Response = @import("http/response.zig").Response;
pub const Headers = @import("http/headers.zig").Headers;

// Re-export server functions
pub const serve = @import("server/serve.zig").serve;
pub const ServeOptions = @import("server/serve.zig").ServeOptions;

// Re-export utility functions
pub const utils = struct {
    pub const request = @import("utils/request.zig");
    pub const response = @import("utils/response.zig");
    pub const middleware = @import("utils/middleware.zig");
    pub const cookie = @import("utils/cookie.zig");
    pub const security = @import("utils/security.zig");
    pub const proxy = @import("utils/proxy.zig");
    pub const body = @import("utils/body.zig");
};

// Internal modules
pub const internal = struct {
    pub const url = @import("internal/url.zig");
    pub const mime = @import("internal/mime.zig");
    pub const patterns = @import("internal/patterns.zig");
};

// Convenience functions for better API
/// Create a new H3 application
pub fn createApp(allocator: std.mem.Allocator) App {
    return App.init(allocator);
}

/// Send a text response
pub fn sendText(event: *Event, text: []const u8) !void {
    try event.sendText(text);
}

/// Send a JSON response
pub fn sendJson(event: *Event, data: anytype) !void {
    try utils.response.sendJsonValue(event, data);
}

/// Send an HTML response
pub fn sendHtml(event: *Event, html: []const u8) !void {
    try event.setHeader("Content-Type", "text/html; charset=utf-8");
    try event.sendText(html);
}

/// Get a path parameter
pub fn getParam(event: *Event, name: []const u8) ?[]const u8 {
    return utils.request.getParam(event, name);
}

/// Get a query parameter
pub fn getQuery(event: *Event, name: []const u8) ?[]const u8 {
    return utils.request.getQuery(event, name);
}

/// Read request body as text
pub fn readBody(event: *Event) ?[]const u8 {
    return utils.request.readBody(event);
}

/// Read and parse JSON request body
pub fn readJson(event: *Event, comptime T: type) !T {
    return utils.request.readJson(event, T);
}

/// Set response status
pub fn setStatus(event: *Event, status: HttpStatus) void {
    utils.response.setStatus(event, status);
}

/// Set response header
pub fn setHeader(event: *Event, name: []const u8, value: []const u8) !void {
    try utils.response.setHeader(event, name, value);
}

/// Get request header
pub fn getHeader(event: *Event, name: []const u8) ?[]const u8 {
    return utils.request.getHeader(event, name);
}

/// Check if request is JSON
pub fn isJson(event: *Event) bool {
    return utils.request.isJson(event);
}

/// Get request method
pub fn getMethod(event: *Event) HttpMethod {
    return utils.request.getMethod(event);
}

/// Get request path
pub fn getPath(event: *Event) []const u8 {
    return utils.request.getPath(event);
}

// Common middleware
pub const middleware = struct {
    /// Logger middleware
    pub const logger = utils.middleware.logger;

    /// CORS middleware with default settings
    pub const cors = utils.middleware.corsDefault;

    /// Security headers middleware
    pub const security = utils.middleware.security;

    /// JSON parser middleware
    pub const jsonParser = utils.middleware.jsonParser;
};

// Common response helpers
pub const response = struct {
    /// Send 200 OK with JSON
    pub fn ok(event: *Event, data: anytype) !void {
        try sendJson(event, data);
    }

    /// Send 201 Created with JSON
    pub fn created(event: *Event, data: anytype) !void {
        setStatus(event, .created);
        try sendJson(event, data);
    }

    /// Send 400 Bad Request
    pub fn badRequest(event: *Event, message: []const u8) !void {
        try utils.response.badRequest(event, message);
    }

    /// Send 401 Unauthorized
    pub fn unauthorized(event: *Event, message: []const u8) !void {
        try utils.response.unauthorized(event, message);
    }

    /// Send 404 Not Found
    pub fn notFound(event: *Event, message: []const u8) !void {
        try utils.response.notFound(event, message);
    }

    /// Send 500 Internal Server Error
    pub fn internalServerError(event: *Event, message: []const u8) !void {
        try utils.response.internalServerError(event, message);
    }

    /// Send 204 No Content
    pub fn noContent(event: *Event) !void {
        setStatus(event, .no_content);
        try sendText(event, "");
    }
};

// Version information
pub const version = "0.1.0";
pub const version_info = struct {
    pub const major = 0;
    pub const minor = 1;
    pub const patch = 0;
    pub const pre_release = "";
};

// Framework information
pub const info = struct {
    pub const name = "H3";
    pub const description = "Zero-dependency HTTP framework for Zig";
    pub const author = "H3 Contributors";
    pub const license = "MIT";
    pub const repository = "https://github.com/h3-framework/h3";
};
