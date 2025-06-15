# H3 - Zig HTTP Framework

⚡️ A minimal, fast, and composable HTTP server framework for Zig, inspired by [H3.js](https://h3.dev).

## Features

- **Minimal & Fast**: Small core with low latency and minimal memory footprint
- **Composable**: Modular design with tree-shakeable utilities
- **Type Safe**: Leverages Zig's compile-time type safety
- **Zero Dependencies**: Only uses Zig standard library
- **Memory Safe**: Built with Zig's memory safety guarantees

## Quick Start

### Installation

Add H3 to your `build.zig.zon`:

```zig
.dependencies = .{
    .h3 = .{
        .url = "https://github.com/dg0230/h3z/archive/main.tar.gz",
        .hash = "...",
    },
},
```

### Basic Usage

```zig
const std = @import("std");
const h3 = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create H3 app
    var app = h3.createApp(allocator);
    defer app.deinit();

    // Add routes
    _ = app.get("/", helloHandler);
    _ = app.get("/api/users/:id", getUserHandler);
    _ = app.post("/api/users", createUserHandler);

    // Start server
    try h3.serve(&app, .{ .port = 3000 });
}

fn helloHandler(event: *h3.Event) !void {
    try h3.sendText(event, "⚡️ Hello from H3!");
}

fn getUserHandler(event: *h3.Event) !void {
    const user_id = h3.getParam(event, "id") orelse {
        try h3.utils.response.badRequest(event, "Missing user ID");
        return;
    };

    const user = .{ .id = user_id, .name = "John Doe" };
    try h3.sendJson(event, user);
}

fn createUserHandler(event: *h3.Event) !void {
    const User = struct { name: []const u8 };
    const user_data = try h3.readJson(event, User);

    event.setStatus(.created);
    try h3.sendJson(event, .{ .id = 123, .name = user_data.name });
}
```

## API Reference

### H3 Application

```zig
// Create app
var app = h3.createApp(allocator);
defer app.deinit();

// HTTP methods
_ = app.get("/path", handler);
_ = app.post("/path", handler);
_ = app.put("/path", handler);
_ = app.delete("/path", handler);
_ = app.patch("/path", handler);
_ = app.head("/path", handler);
_ = app.options("/path", handler);
_ = app.all("/path", handler); // All methods

// Middleware
_ = app.use(middleware);
```

### H3Event

The `H3Event` is the central context object that carries request and response data:

```zig
fn handler(event: *h3.Event) !void {
    // Request info
    const method = event.getMethod();
    const path = event.getPath();
    const url = event.getUrl();

    // Headers
    const auth = event.getHeader("authorization");
    try event.setHeader("x-custom", "value");

    // Parameters and query
    const id = h3.getParam(event, "id");
    const page = h3.getQuery(event, "page");

    // Body
    const body = h3.readBody(event);
    const json_data = try h3.readJson(event, MyStruct);

    // Response
    event.setStatus(.ok);
    try h3.sendText(event, "Hello");
    try h3.sendJson(event, "{\"message\": \"Hello\"}");
    try h3.sendJson(event, .{ .message = "Hello" });
    try h3.response.redirect(event, "/new-path", .moved_permanently);
}
```

### Utilities

```zig
// Response helpers
try h3.sendText(event, "text");
try h3.sendJson(event, json_string);
try h3.sendJson(event, struct_or_value);
try h3.utils.response.redirect(event, "/path", .found);

// Error responses
try h3.utils.response.notFound(event, "Custom message");
try h3.utils.response.badRequest(event, "Invalid input");
try h3.utils.response.unauthorized(event, null);
try h3.utils.response.forbidden(event, null);
try h3.utils.response.internalServerError(event, null);

// Request helpers
const header = event.getHeader("content-type");
const param = h3.getParam(event, "id");
const query = h3.getQuery(event, "page");
const body = h3.readBody(event);
const json = try h3.readJson(event, MyStruct);

// Security and CORS
try h3.utils.response.setCors(event, "*");
try h3.utils.response.setSecurity(event);
try h3.utils.response.setNoCache(event);
```

### Middleware

```zig
fn loggerMiddleware(event: *h3.Event, context: h3.MiddlewareContext, index: usize, final_handler: h3.Handler) !void {
    std.log.info("{s} {s}", .{ event.getMethod().toString(), event.getPath() });
    try context.next(event, index, final_handler);
}

fn corsMiddleware(event: *h3.Event, context: h3.MiddlewareContext, index: usize, final_handler: h3.Handler) !void {
    try h3.utils.response.setCors(event, "*");
    if (event.getMethod() == .OPTIONS) {
        event.setStatus(.no_content);
        return;
    }
    try context.next(event, index, final_handler);
}

// Built-in middleware
_ = app.use(h3.middleware.logger);
_ = app.use(h3.middleware.cors("*"));
_ = app.use(h3.middleware.security);
```

### Server

```zig
// Start server with options
try h3.serve(&app, .{
    .port = 3000,
    .host = "127.0.0.1",
    .backlog = 128,
});

// Start with defaults (port 3000)
try h3.serve(&app, .{});
```

## Route Patterns

H3 supports simple route patterns:

- **Exact match**: `/api/users`
- **Parameters**: `/api/users/:id` (accessible via `event.getParam("id")`)
- **Wildcards**: `/static/*` (matches any path starting with `/static/`)

## Building and Testing

```bash
# Build the project
zig build

# Run tests
zig build test

# Run the example
zig build run

# Build in release mode
zig build -Doptimize=ReleaseFast
```

## Requirements

- Zig 0.14.0 or later

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Roadmap

- [ ] Advanced routing (regex patterns, route groups)
- [ ] WebSocket support
- [ ] Static file serving
- [ ] Template engine integration
- [ ] Database integration helpers
- [ ] Session management
- [ ] Rate limiting
- [ ] Compression middleware
- [ ] File upload handling
- [ ] Testing utilities

## Inspiration

This project is inspired by [H3.js](https://h3.dev), bringing similar concepts and ergonomics to the Zig ecosystem while leveraging Zig's unique strengths in performance and safety.
