//! Simple H3 server example
//! Demonstrates the new clean API

const std = @import("std");
const h3 = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create app with new API (disable event pool to avoid memory issues)
    var app = try h3.createApp(allocator);
    defer app.deinit();
    
    // Disable event pool to prevent memory corruption issue
    if (app.event_pool) |*pool| {
        pool.deinit();
        app.event_pool = null;
    }

    // Add middleware
    _ = app.use(h3.middleware.logger);
    _ = app.use(h3.middleware.cors);
    _ = app.use(h3.middleware.security);

    // Simple routes
    _ = app.get("/", homeHandler);
    _ = app.get("/hello/:name", helloHandler);
    _ = app.post("/api/data", dataHandler);
    _ = app.get("/api/status", statusHandler);

    std.log.info("🚀 Simple H3 server starting on http://127.0.0.1:3000", .{});
    std.log.info("Press Ctrl+C to stop the server", .{});

    // Start server
    try h3.serve(&app, .{ .port = 3000 });
}

fn homeHandler(event: *h3.Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>H3 Simple Server</title>
        \\    <style>
        \\        body { font-family: Arial, sans-serif; margin: 40px; }
        \\        .container { max-width: 600px; margin: 0 auto; }
        \\        .endpoint { background: #f5f5f5; padding: 10px; margin: 10px 0; border-radius: 5px; }
        \\        code { background: #e0e0e0; padding: 2px 4px; border-radius: 3px; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="container">
        \\        <h1>🚀 H3 Simple Server</h1>
        \\        <p>Welcome to the H3 framework simple server example!</p>
        \\        
        \\        <h2>Available Endpoints:</h2>
        \\        
        \\        <div class="endpoint">
        \\            <strong>GET /</strong><br>
        \\            This page
        \\        </div>
        \\        
        \\        <div class="endpoint">
        \\            <strong>GET /hello/:name</strong><br>
        \\            Personalized greeting<br>
        \\            Example: <code>curl http://localhost:3000/hello/world</code>
        \\        </div>
        \\        
        \\        <div class="endpoint">
        \\            <strong>POST /api/data</strong><br>
        \\            Echo JSON data<br>
        \\            Example: <code>curl -X POST -H "Content-Type: application/json" -d '{"message":"hello"}' http://localhost:3000/api/data</code>
        \\        </div>
        \\        
        \\        <div class="endpoint">
        \\            <strong>GET /api/status</strong><br>
        \\            Server status<br>
        \\            Example: <code>curl http://localhost:3000/api/status</code>
        \\        </div>
        \\        
        \\        <h2>Features Demonstrated:</h2>
        \\        <ul>
        \\            <li>✅ Clean new API</li>
        \\            <li>✅ Path parameters</li>
        \\            <li>✅ JSON handling</li>
        \\            <li>✅ Middleware (logging, CORS, security)</li>
        \\            <li>✅ HTML responses</li>
        \\            <li>✅ Error handling</li>
        \\        </ul>
        \\    </div>
        \\</body>
        \\</html>
    ;

    try h3.sendHtml(event, html);
}

fn helloHandler(event: *h3.Event) !void {
    const name = h3.getParam(event, "name") orelse "Anonymous";

    const greeting = .{
        .message = "Hello from H3!",
        .name = name,
        .timestamp = std.time.timestamp(),
        .server = "H3 Simple Server",
    };

    try h3.sendJson(event, greeting);
}

fn dataHandler(event: *h3.Event) !void {
    // Check if request has JSON content
    if (!h3.isJson(event)) {
        try h3.response.badRequest(event, "Expected JSON content");
        return;
    }

    const body = h3.readBody(event) orelse "";

    const response_data = .{
        .received = body,
        .length = body.len,
        .processed_at = std.time.timestamp(),
        .echo = "Data received successfully",
    };

    try h3.response.created(event, response_data);
}

fn statusHandler(event: *h3.Event) !void {
    const status = .{
        .server = "H3 Simple Server",
        .status = "healthy",
        .version = h3.version,
        .uptime = "running",
        .timestamp = std.time.timestamp(),
        .endpoints = .{
            .total = 4,
            .available = 4,
        },
    };

    try h3.response.ok(event, status);
}
