# H3 Framework Documentation

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Basic Server Setup](#basic-server-setup)
4. [Routing System](#routing-system)
5. [Middleware](#middleware)
6. [Request & Response Handling](#request--response-handling)
7. [Advanced Features](#advanced-features)
8. [Component Architecture](#component-architecture)
9. [Performance Optimization](#performance-optimization)
10. [Examples](#examples)

## Introduction

H3 is a minimal, fast, and composable HTTP server framework for Zig. It's inspired by the H3.js framework but built specifically for Zig with zero external dependencies (except libxev for async I/O).

### Key Features

- **Zero Dependencies**: Only uses Zig standard library and libxev
- **Type Safety**: Leverages Zig's compile-time type checking
- **High Performance**: Event pooling, route caching, and optimized middleware
- **Flexible Architecture**: Both traditional and component-based APIs
- **Memory Safe**: Built-in memory management with pooling support

## Getting Started

### Installation

Add H3 to your `build.zig.zon`:

```zig
.{
    .dependencies = .{
        .h3 = .{
            .url = "https://github.com/dg0230/h3z/archive/<commit-hash>.tar.gz",
            .hash = "<hash>",
        },
    },
}
```

### Basic Example

```zig
const std = @import("std");
const h3 = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a new H3 application
    var app = try h3.createApp(allocator);
    defer app.deinit();

    // Define a simple route
    _ = app.get("/", homeHandler);

    // Start the server
    try h3.serve(&app, .{ .port = 3000 });
}

fn homeHandler(event: *h3.Event) !void {
    try h3.sendText(event, "Hello, World!");
}
```

## Basic Server Setup

### Creating an Application

H3 offers multiple ways to create an application:

```zig
// Basic application (legacy API)
var app = try h3.createApp(allocator);

// Performance-optimized application
var app = try h3.createFastApp(allocator);

// Component-based application (modern API)
var app = try h3.createComponentApp(allocator);

// Production-ready application with all optimizations
var app = try h3.createProductionApp(allocator);
```

### Custom Configuration

```zig
const config = h3.ConfigBuilder.init()
    .setUseEventPool(true)
    .setEventPoolSize(1000)
    .setUseFastMiddleware(true)
    .setMaxRequestSize(10 * 1024 * 1024) // 10MB
    .build();

var app = try h3.createAppWithConfig(allocator, config);
```

### Server Options

```zig
try h3.serve(&app, .{
    .port = 3000,
    .address = "127.0.0.1",
    .reuse_address = true,
    .reuse_port = true,
    .kernel_backlog = 128,
    .timeout_ms = 30000,
});
```

## Routing System

### Basic Routes

```zig
// HTTP methods
_ = app.get("/users", getUsers);
_ = app.post("/users", createUser);
_ = app.put("/users/:id", updateUser);
_ = app.patch("/users/:id", patchUser);
_ = app.delete("/users/:id", deleteUser);
_ = app.head("/users", headUsers);
_ = app.options("/users", optionsUsers);

// Match all methods
_ = app.all("/api/*", apiHandler);
```

### Route Parameters

```zig
// Named parameters
_ = app.get("/users/:id", getUserById);
_ = app.get("/posts/:postId/comments/:commentId", getComment);

// Wildcard parameters
_ = app.get("/static/*", serveStatic);

// Handler implementation
fn getUserById(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse return error.MissingParam;
    
    const user = .{
        .id = id,
        .name = "John Doe",
    };
    
    try h3.sendJson(event, user);
}
```

### Query Parameters

```zig
fn searchHandler(event: *h3.Event) !void {
    const query = h3.getQuery(event, "q");
    const page = h3.getQuery(event, "page") orelse "1";
    const limit = h3.getQuery(event, "limit") orelse "10";
    
    const results = .{
        .query = query,
        .page = page,
        .limit = limit,
    };
    
    try h3.sendJson(event, results);
}
```

### Under the Hood: Trie-Based Router

The router uses a trie (prefix tree) data structure for efficient pattern matching:

```zig
// Internal structure (simplified)
const TrieNode = struct {
    segment: []const u8,
    is_param: bool,
    is_wildcard: bool,
    handlers: [9]?Handler, // One for each HTTP method
    children: std.ArrayList(*TrieNode),
};
```

When you add a route:
1. The pattern is tokenized by `/` separators
2. Each segment is inserted into the trie
3. Parameter segments (`:param`) are marked as dynamic
4. Wildcard segments (`*`) capture remaining path

During request matching:
1. The URL path is tokenized
2. The trie is traversed, matching static segments exactly
3. Parameter segments extract values
4. The handler for the matching method is executed

## Middleware

### Traditional Middleware

```zig
// Built-in middleware
_ = app.use(h3.middleware.logger);
_ = app.use(h3.middleware.cors);
_ = app.use(h3.middleware.security);
_ = app.use(h3.middleware.jsonParser);

// Custom middleware
fn authMiddleware(ctx: *h3.MiddlewareContext, next: h3.Handler) !void {
    const token = h3.getHeader(ctx.event, "Authorization");
    
    if (token == null) {
        try h3.sendError(ctx.event, .unauthorized, "Missing token");
        return;
    }
    
    // Validate token...
    
    // Call next middleware/handler
    try next(ctx.event);
}

_ = app.use(authMiddleware);
```

### Fast Middleware (Optimized)

Fast middleware provides better performance by using an optimized execution model:

```zig
// Enable fast middleware in configuration
var app = try h3.createFastApp(allocator);

// Use fast middleware
_ = app.useFast(h3.fastMiddleware.logger);
_ = app.useFast(h3.fastMiddleware.cors);
_ = app.useFast(h3.fastMiddleware.security);
_ = app.useFast(h3.fastMiddleware.timing);
```

### Under the Hood: Middleware Chain

Traditional middleware uses a linked chain:
```zig
// Each middleware wraps the next
fn executeChain(ctx: *Context, middleware: []Middleware, index: usize) !void {
    if (index >= middleware.len) {
        return ctx.handler(ctx.event);
    }
    
    const next = struct {
        fn call(event: *Event) !void {
            executeChain(ctx, middleware, index + 1);
        }
    }.call;
    
    try middleware[index](ctx, next);
}
```

Fast middleware uses a more efficient approach:
- Pre-compiled execution order
- Reduced function call overhead
- Optimized context passing
- Inline-friendly design

## Request & Response Handling

### Reading Request Data

```zig
fn handleRequest(event: *h3.Event) !void {
    // Get request method
    const method = h3.getMethod(event);
    
    // Get path
    const path = h3.getPath(event);
    
    // Get headers
    const content_type = h3.getHeader(event, "Content-Type");
    
    // Read body
    const body = h3.readBody(event);
    
    // Parse JSON body
    const User = struct {
        name: []const u8,
        email: []const u8,
    };
    const user = try h3.readJson(event, User);
}
```

### Sending Responses

```zig
// Text response
try h3.sendText(event, "Hello, World!");

// JSON response
const data = .{ .message = "Success", .code = 200 };
try h3.sendJson(event, data);

// HTML response
try h3.sendHtml(event, "<h1>Welcome</h1>");

// Error responses
try h3.sendError(event, .bad_request, "Invalid input");
try h3.response.notFound(event, "Resource not found");
try h3.response.internalServerError(event, "Something went wrong");

// Redirect
try h3.redirect(event, "/login", .temporary_redirect);

// Custom status and headers
h3.setStatus(event, .created);
try h3.setHeader(event, "X-Custom-Header", "value");
try h3.sendJson(event, result);
```

### Under the Hood: Event Object

The `H3Event` object is the central context for request/response handling:

```zig
pub const H3Event = struct {
    request: *Request,
    response: *Response,
    params: ?std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    app_context: ?*anyopaque,
    matched_pattern: ?[]const u8,
    
    // Methods for handling requests/responses
    pub fn sendText(self: *H3Event, text: []const u8) !void {
        try self.response.headers.set("Content-Type", "text/plain");
        try self.response.write(text);
    }
    
    // ... more methods
};
```

## Advanced Features

### Event Pooling

Event pooling reduces allocation overhead by reusing `H3Event` objects:

```zig
// Enable in configuration
const config = h3.ConfigBuilder.init()
    .setUseEventPool(true)
    .setEventPoolSize(1000)
    .build();

var app = try h3.createAppWithConfig(allocator, config);
```

Under the hood:
- Pre-allocates a pool of `H3Event` objects
- Uses a free list for O(1) acquire/release
- Automatically cleans and resets events before reuse
- Falls back to allocation when pool is exhausted

### Route Caching

The LRU route cache speeds up pattern matching for frequently accessed routes:

```zig
// Automatic with fast app
var app = try h3.createFastApp(allocator);

// Or configure manually
const config = h3.ConfigBuilder.init()
    .setRouteCache(true)
    .setRouteCacheSize(100)
    .build();
```

Cache implementation:
- Stores URL → handler mappings
- LRU eviction policy
- Thread-safe operations
- Cache hit ratio monitoring

### Memory Management

H3 provides centralized memory management with monitoring:

```zig
// Access memory stats
const stats = app.getMemoryStats();
std.log.info("Total allocated: {} bytes", .{stats.total_allocated});
std.log.info("Active allocations: {}", .{stats.active_allocations});

// Configure memory limits
const config = h3.ConfigBuilder.init()
    .setMaxMemory(100 * 1024 * 1024) // 100MB limit
    .setMemoryMonitoring(true)
    .build();
```

### Security Features

```zig
// Built-in security headers
_ = app.use(h3.middleware.security);

// Custom security configuration
const security_config = h3.SecurityConfig{
    .enable_cors = true,
    .cors_origins = &.{"https://example.com"},
    .enable_csrf = true,
    .csrf_token_length = 32,
    .enable_helmet = true,
};

// Rate limiting
_ = app.use(h3.utils.middleware.rateLimit(.{
    .window_ms = 60 * 1000, // 1 minute
    .max_requests = 100,
    .message = "Too many requests",
}));
```

## Component Architecture

The modern component-based API provides better modularity:

```zig
const MyComponent = struct {
    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{};
    }
    
    pub fn configure(self: *@This(), app: *h3.H3App) !void {
        _ = try app.router.get("/component", handler);
    }
    
    fn handler(event: *h3.Event) !void {
        try h3.sendText(event, "From component!");
    }
};

// Usage
var app = try h3.createComponentApp(allocator);
try app.register(MyComponent);
```

## Performance Optimization

### Benchmarking

```zig
// Run built-in benchmarks
zig build benchmark

// Custom performance monitoring
_ = app.useFast(h3.fastMiddleware.timing);
_ = app.useFast(h3.fastMiddleware.timingEnd);
```

### Optimization Tips

1. **Use Fast Middleware**: 2-3x faster than traditional middleware
2. **Enable Event Pooling**: Reduces GC pressure
3. **Enable Route Caching**: Speeds up hot paths
4. **Use libxev Adapter**: Better async I/O performance
5. **Batch Operations**: Reduce syscalls

### Production Configuration

```zig
const config = h3.ConfigBuilder.init()
    // Performance
    .setUseEventPool(true)
    .setEventPoolSize(2000)
    .setUseFastMiddleware(true)
    .setRouteCache(true)
    .setRouteCacheSize(200)
    
    // Memory
    .setMaxMemory(512 * 1024 * 1024) // 512MB
    .setMemoryMonitoring(true)
    
    // Security
    .setSecurityHeaders(true)
    .setRateLimiting(true)
    
    // Monitoring
    .setMetricsEnabled(true)
    .setLoggingLevel(.info)
    .build();

var app = try h3.H3App.initWithConfig(allocator, config);
```

## Examples

### REST API Server

```zig
const std = @import("std");
const h3 = @import("h3");

const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
};

var users = std.ArrayList(User).init(allocator);

pub fn main() !void {
    var app = try h3.createFastApp(allocator);
    defer app.deinit();
    
    // Middleware
    _ = app.useFast(h3.fastMiddleware.logger);
    _ = app.useFast(h3.fastMiddleware.cors);
    _ = app.use(h3.middleware.jsonParser);
    
    // Routes
    _ = app.get("/api/users", getUsers);
    _ = app.get("/api/users/:id", getUser);
    _ = app.post("/api/users", createUser);
    _ = app.put("/api/users/:id", updateUser);
    _ = app.delete("/api/users/:id", deleteUser);
    
    try h3.serve(&app, .{ .port = 3000 });
}

fn getUsers(event: *h3.Event) !void {
    try h3.sendJson(event, users.items);
}

fn getUser(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse return error.MissingParam;
    const user_id = try std.fmt.parseInt(u32, id, 10);
    
    for (users.items) |user| {
        if (user.id == user_id) {
            try h3.sendJson(event, user);
            return;
        }
    }
    
    try h3.response.notFound(event, "User not found");
}

fn createUser(event: *h3.Event) !void {
    const user = try h3.readJson(event, User);
    try users.append(user);
    
    h3.setStatus(event, .created);
    try h3.sendJson(event, user);
}
```

### WebSocket Server (with Component Architecture)

```zig
const WebSocketComponent = struct {
    connections: std.ArrayList(*h3.Event),
    
    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{
            .connections = std.ArrayList(*h3.Event).init(allocator),
        };
    }
    
    pub fn configure(self: *@This(), app: *h3.H3App) !void {
        _ = try app.router.get("/ws", self.upgradeHandler);
    }
    
    fn upgradeHandler(self: *@This(), event: *h3.Event) !void {
        // WebSocket upgrade logic
        if (h3.utils.request.isWebSocketUpgrade(event)) {
            try h3.utils.response.upgradeWebSocket(event);
            try self.connections.append(event);
        }
    }
};
```

### Static File Server

```zig
fn serveStatic(event: *h3.Event) !void {
    const path = h3.getParam(event, "*") orelse "index.html";
    const safe_path = try h3.utils.security.sanitizePath(path);
    
    const file_path = try std.fmt.allocPrint(
        event.allocator,
        "public/{s}",
        .{safe_path}
    );
    defer event.allocator.free(file_path);
    
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            try h3.response.notFound(event, "File not found");
            return;
        }
        return err;
    };
    defer file.close();
    
    const content = try file.readToEndAlloc(event.allocator, 10 * 1024 * 1024);
    defer event.allocator.free(content);
    
    const ext = std.fs.path.extension(file_path);
    const mime_type = h3.getMimeType(ext);
    
    try h3.setHeader(event, "Content-Type", mime_type);
    try h3.sendText(event, content);
}
```

### Error Handling

```zig
fn errorHandler(event: *h3.Event, err: anyerror) !void {
    std.log.err("Request error: {}", .{err});
    
    const status = switch (err) {
        error.InvalidInput => h3.HttpStatus.bad_request,
        error.Unauthorized => h3.HttpStatus.unauthorized,
        error.NotFound => h3.HttpStatus.not_found,
        else => h3.HttpStatus.internal_server_error,
    };
    
    const message = switch (err) {
        error.InvalidInput => "Invalid input provided",
        error.Unauthorized => "Authentication required",
        error.NotFound => "Resource not found",
        else => "Internal server error",
    };
    
    try h3.sendError(event, status, message);
}

// Set as error handler
app.setErrorHandler(errorHandler);
```

## Best Practices

1. **Always defer cleanup**: Use `defer app.deinit()` and `defer allocator.free()`
2. **Handle errors gracefully**: Use error unions and provide meaningful messages
3. **Use appropriate middleware**: Fast middleware for production, traditional for development
4. **Monitor memory usage**: Enable memory monitoring in production
5. **Set reasonable limits**: Configure max request size, timeout, etc.
6. **Use type safety**: Leverage Zig's compile-time type checking
7. **Pool resources**: Enable event pooling for high-traffic applications
8. **Log appropriately**: Use different log levels for different environments

## Troubleshooting

### Common Issues

1. **Memory leaks**: Use `std.testing.allocator` in tests to detect leaks
2. **Route conflicts**: Check for overlapping patterns with wildcard routes
3. **Performance issues**: Enable route caching and event pooling
4. **Connection errors**: Check server adapter configuration and timeouts

### Debug Mode

```zig
// Enable debug logging
const config = h3.ConfigBuilder.init()
    .setLoggingLevel(.debug)
    .setLogConnection(true)
    .setLogRequest(true)
    .setLogRouting(true)
    .build();
```

## Conclusion

H3 provides a powerful yet simple framework for building HTTP servers in Zig. Its zero-dependency design, type safety, and performance optimizations make it suitable for both small applications and high-performance services.

For more examples and advanced usage, check out the `examples/` directory in the repository.