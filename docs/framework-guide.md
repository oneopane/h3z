# The H3 Framework: A Comprehensive Guide

## What is H3?

H3 is a minimal yet powerful HTTP server framework for Zig that takes inspiration from the JavaScript H3.js framework while embracing Zig's unique strengths. Think of it as a toolkit that gives you just what you need to build web servers - nothing more, nothing less.

The framework's philosophy centers around three core principles:
- **Zero dependencies**: Only relies on Zig's standard library and libxev for async I/O
- **Type safety**: Leverages Zig's compile-time guarantees to catch errors before they happen
- **Performance**: Built from the ground up with efficiency in mind

## Getting Started: Your First Server

Let's start with the simplest possible H3 server. If you look at `examples/simple_server.zig`, you'll see how straightforward it is:

```zig
var app = try h3.createApp(allocator);
defer app.deinit();

_ = app.get("/", homeHandler);

try h3.serve(&app, .{ .port = 3000 });
```

That's it! In just four lines, you have a working web server. The framework handles all the complexity of HTTP parsing, connection management, and request routing behind the scenes.

## Understanding the Request-Response Cycle

When a request comes in, H3 follows a predictable flow that you can hook into at various points. The central concept here is the `H3Event` - a context object that carries everything about the current request and provides methods to send responses.

Looking at the `homeHandler` in our simple server example:

```zig
fn homeHandler(event: *h3.Event) !void {
    try h3.sendText(event, "Hello, World!");
}
```

The event object is your window into the HTTP transaction. You can:
- Read request data: `h3.getPath(event)`, `h3.getMethod(event)`
- Access parameters: `h3.getParam(event, "id")` 
- Read headers: `h3.getHeader(event, "Authorization")`
- Send responses: `h3.sendJson(event, data)`, `h3.sendHtml(event, html)`

## Routing: Matching URLs to Handlers

H3's routing system uses a trie (prefix tree) data structure internally, which makes pattern matching extremely fast even with hundreds of routes. You define routes using familiar HTTP method names:

```zig
_ = app.get("/users", listUsers);
_ = app.post("/users", createUser);
_ = app.put("/users/:id", updateUser);
_ = app.delete("/users/:id", deleteUser);
```

The `:id` syntax creates a parameter that you can extract in your handler. For a real-world example, check out `examples/auth_api.zig` where we use this pattern extensively:

```zig
_ = app.delete("/users/:id", deleteUserHandler);

fn deleteUserHandler(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse return error.MissingParam;
    // ... handle the deletion
}
```

### Wildcard Routes

Sometimes you need to capture multiple path segments. The wildcard syntax (`*`) is perfect for this. In `examples/file_upload.zig`, we use it for serving static files:

```zig
_ = app.get("/static/*", serveStatic);
```

This matches any path starting with `/static/` and makes the rest available as a parameter.

## Middleware: The Power of Composition

Middleware is code that runs before your handlers, allowing you to add cross-cutting concerns like logging, authentication, or CORS headers. H3 offers two middleware systems: traditional and fast.

### Traditional Middleware

Traditional middleware follows a familiar pattern where each middleware calls the next in the chain:

```zig
fn authMiddleware(ctx: *h3.MiddlewareContext, next: h3.Handler) !void {
    const token = h3.getHeader(ctx.event, "Authorization");
    
    if (token == null) {
        try h3.sendError(ctx.event, .unauthorized, "Missing token");
        return; // Stop the chain here
    }
    
    // Token is valid, continue to the next middleware/handler
    try next(ctx.event);
}
```

You can see this pattern in action in `examples/auth_api.zig`, where we protect certain routes with authentication middleware.

### Fast Middleware

For performance-critical applications, H3 provides an optimized middleware system:

```zig
var app = try h3.createFastApp(allocator);
_ = app.useFast(h3.fastMiddleware.logger);
_ = app.useFast(h3.fastMiddleware.cors);
```

Fast middleware uses a pre-compiled execution strategy that reduces function call overhead and improves cache locality.

## Working with JSON

Modern web APIs are all about JSON, and H3 makes it incredibly easy to work with. The framework can automatically parse JSON requests and serialize responses:

```zig
const User = struct {
    name: []const u8,
    email: []const u8,
};

fn createUserHandler(event: *h3.Event) !void {
    // Parse JSON from request body
    const user = try h3.readJson(event, User);
    
    // Process the user...
    
    // Send JSON response
    const response = .{
        .success = true,
        .user = user,
    };
    try h3.sendJson(event, response);
}
```

The `auth_api.zig` example demonstrates this extensively with user registration and login endpoints.

## Performance Optimizations

H3 isn't just easy to use - it's also blazing fast. The framework includes several optimization strategies that you can enable based on your needs.

### Event Pooling

Instead of allocating a new event object for each request, H3 can reuse objects from a pool:

```zig
const config = h3.ConfigBuilder.init()
    .setUseEventPool(true)
    .setEventPoolSize(1000)
    .build();

var app = try h3.createAppWithConfig(allocator, config);
```

This reduces garbage collection pressure and improves performance under high load.

### Route Caching

For applications with many routes, H3 can cache recent URL-to-handler mappings:

```zig
var app = try h3.createFastApp(allocator); // Enables caching automatically
```

The cache uses an LRU (Least Recently Used) eviction policy to keep the most accessed routes hot.

## Component Architecture: Building Modular Applications

As your application grows, you'll want to organize code into reusable components. H3's component system, demonstrated in `examples/websocket_chat.zig`, provides a clean way to structure larger applications:

```zig
const ChatComponent = struct {
    rooms: std.StringHashMap(ChatRoom),
    
    pub fn configure(self: *ChatComponent, app: *h3.H3App) !void {
        _ = try app.router.get("/", chatUIHandler);
        _ = try app.router.get("/api/rooms", self.getRoomsHandler);
        _ = try app.router.post("/api/rooms", self.createRoomHandler);
    }
};
```

Components encapsulate related functionality and can be easily tested in isolation.

## File Uploads and Streaming

Handling file uploads requires special consideration for memory usage and performance. The `file_upload.zig` example shows how to:

1. Configure appropriate request size limits
2. Handle multipart form data
3. Stream large files efficiently
4. Implement chunked uploads for very large files

```zig
const config = h3.ConfigBuilder.init()
    .setMaxRequestSize(50 * 1024 * 1024) // 50MB limit
    .build();
```

## Error Handling

Zig's error handling philosophy carries through to H3. Instead of exceptions, we use error unions and explicit error handling:

```zig
fn riskyHandler(event: *h3.Event) !void {
    const data = h3.readBody(event) orelse {
        try h3.response.badRequest(event, "No data provided");
        return;
    };
    
    const result = processData(data) catch |err| {
        std.log.err("Processing failed: {}", .{err});
        try h3.response.internalServerError(event, "Processing failed");
        return;
    };
    
    try h3.sendJson(event, result);
}
```

This approach makes error paths explicit and ensures you handle failures appropriately.

## Security Considerations

H3 includes built-in security features that you can enable with middleware:

```zig
_ = app.use(h3.middleware.security); // Adds security headers
_ = app.use(h3.middleware.cors);     // Handles CORS
```

For authentication, the `auth_api.zig` example demonstrates token-based authentication with protected routes:

```zig
const protected = app.group("/api/protected");
_ = protected.use(authMiddleware);
_ = protected.get("/profile", getProfileHandler);
```

## Memory Management

One of Zig's strengths is explicit memory management, and H3 embraces this. The framework provides tools to monitor and control memory usage:

```zig
const stats = app.getMemoryStats();
std.log.info("Active allocations: {}", .{stats.active_allocations});
```

Always remember to clean up:
- Use `defer` for cleanup operations
- Call `deinit()` on application shutdown
- Free allocated memory in handlers

## Real-time Communication

While H3 focuses on HTTP, it provides the foundation for WebSocket upgrades. The `websocket_chat.zig` example shows how to:

1. Detect WebSocket upgrade requests
2. Manage persistent connections
3. Broadcast messages to multiple clients
4. Implement a real-time chat system

## Production Deployment

When deploying H3 applications to production, consider these configurations:

```zig
const config = h3.ConfigBuilder.init()
    // Performance
    .setUseEventPool(true)
    .setEventPoolSize(2000)
    .setUseFastMiddleware(true)
    .setRouteCache(true)
    
    // Security
    .setSecurityHeaders(true)
    .setRateLimiting(true)
    
    // Monitoring
    .setMetricsEnabled(true)
    .setLoggingLevel(.info)
    .build();
```

## Testing Your H3 Applications

The framework includes utilities for testing. Always test with the test allocator to catch memory leaks:

```zig
test "user creation" {
    const allocator = std.testing.allocator;
    var app = try h3.createApp(allocator);
    defer app.deinit();
    
    // Your test code here
}
```

## Debugging and Troubleshooting

Enable debug logging to understand what's happening inside H3:

```zig
const config = h3.ConfigBuilder.init()
    .setLoggingLevel(.debug)
    .setLogConnection(true)
    .setLogRequest(true)
    .build();
```

Common issues and solutions:
- **Memory leaks**: Use test allocator and check for missing `defer` statements
- **Route conflicts**: Wildcard routes can shadow specific routes - order matters
- **Performance issues**: Enable event pooling and route caching

## Conclusion

H3 demonstrates that a web framework doesn't need to be complex to be powerful. By leveraging Zig's strengths - compile-time safety, explicit memory management, and zero-cost abstractions - H3 provides a solid foundation for building everything from simple REST APIs to complex real-time applications.

The examples in this repository showcase various use cases:
- `simple_server.zig`: Basic routing and responses
- `auth_api.zig`: Authentication and protected routes
- `file_upload.zig`: File handling and streaming
- `websocket_chat.zig`: Real-time communication and components

Each example is self-contained and demonstrates specific framework features in a practical context. As you build with H3, you'll find that its minimalist design doesn't limit you - instead, it gives you the freedom to build exactly what you need, nothing more, nothing less.