# ZH3 - Zig HTTP Framework

⚡️ A minimal, fast, and composable HTTP server framework for Zig, inspired by [H3.js](https://h3.dev).

## Features

- **Minimal & Fast**: Small core with low latency and minimal memory footprint
- **Composable**: Modular design with tree-shakeable utilities
- **Type Safe**: Leverages Zig's compile-time type safety
- **Zero Dependencies**: Only uses Zig standard library
- **Memory Safe**: Built with Zig's memory safety guarantees

## Quick Start

### Installation

Add ZH3 to your `build.zig.zon`:

```zig
.dependencies = .{
    .zh3 = .{
        .url = "https://github.com/your-repo/zh3/archive/main.tar.gz",
        .hash = "...",
    },
},
```

### Basic Usage

```zig
const std = @import("std");
const zh3 = @import("zh3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create H3 app
    var app = zh3.H3.init(allocator);
    defer app.deinit();

    // Add routes
    _ = app.get("/", helloHandler);
    _ = app.get("/api/users/:id", getUserHandler);
    _ = app.post("/api/users", createUserHandler);

    // Start server
    try zh3.serve(&app, .{ .port = 3000 });
}

fn helloHandler(event: *zh3.H3Event) !void {
    try zh3.utils.send(event, "⚡️ Hello from ZH3!");
}

fn getUserHandler(event: *zh3.H3Event) !void {
    const user_id = zh3.utils.getParam(event, "id") orelse {
        try zh3.utils.badRequest(event, "Missing user ID");
        return;
    };

    const user = .{ .id = user_id, .name = "John Doe" };
    try zh3.utils.sendJsonValue(event, user);
}

fn createUserHandler(event: *zh3.H3Event) !void {
    const User = struct { name: []const u8 };
    const user_data = try zh3.utils.readJson(event, User);

    event.setStatus(.created);
    try zh3.utils.sendJsonValue(event, .{ .id = 123, .name = user_data.name });
}
```

## API Reference

### H3 Application

```zig
// Create app
var app = zh3.H3.init(allocator);
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
fn handler(event: *zh3.H3Event) !void {
    // Request info
    const method = event.getMethod();
    const path = event.getPath();
    const url = event.getUrl();

    // Headers
    const auth = event.getHeader("authorization");
    try event.setHeader("x-custom", "value");

    // Parameters and query
    const id = event.getParam("id");
    const page = event.getQuery("page");

    // Body
    const body = event.readBody();
    const json_data = try event.readJson(MyStruct);

    // Response
    event.setStatus(.ok);
    try event.sendText("Hello");
    try event.sendJson("{\"message\": \"Hello\"}");
    try event.sendJsonValue(.{ .message = "Hello" });
    try event.redirect("/new-path", .moved_permanently);
}
```

### Utilities

```zig
// Response helpers
try zh3.utils.send(event, "text");
try zh3.utils.sendJson(event, json_string);
try zh3.utils.sendJsonValue(event, struct_or_value);
try zh3.utils.redirect(event, "/path", .found);

// Error responses
try zh3.utils.notFound(event, "Custom message");
try zh3.utils.badRequest(event, "Invalid input");
try zh3.utils.unauthorized(event, null);
try zh3.utils.forbidden(event, null);
try zh3.utils.internalServerError(event, null);

// Request helpers
const header = zh3.utils.getHeader(event, "content-type");
const param = zh3.utils.getParam(event, "id");
const query = zh3.utils.getQuery(event, "page");
const body = zh3.utils.readBody(event);
const json = try zh3.utils.readJson(event, MyStruct);

// Security and CORS
try zh3.utils.setCors(event, "*");
try zh3.utils.setSecurity(event);
try zh3.utils.setNoCache(event);
```

### Middleware

```zig
fn loggerMiddleware(event: *zh3.H3Event, next: zh3.Handler) !void {
    std.log.info("{s} {s}", .{ event.getMethod().toString(), event.getPath() });
    try next(event);
}

fn corsMiddleware(event: *zh3.H3Event, next: zh3.Handler) !void {
    try zh3.utils.setCors(event, "*");
    if (event.getMethod() == .OPTIONS) {
        event.setStatus(.no_content);
        return;
    }
    try next(event);
}

// Built-in middleware
_ = app.use(zh3.utils.logger);
_ = app.use(zh3.utils.cors("*"));
_ = app.use(zh3.utils.security());
```

### Server

```zig
// Start server with options
try zh3.serve(&app, .{
    .port = 3000,
    .host = "127.0.0.1",
    .backlog = 128,
});

// Start with defaults (port 3000)
try zh3.serveDefault(&app);
```

## Route Patterns

ZH3 supports simple route patterns:

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
