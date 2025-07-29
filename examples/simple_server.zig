//! Simple H3 server example
//! Demonstrates the new clean API

const std = @import("std");
const h3z = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create app using modern component-based API
    var app = try h3z.H3App.init(allocator);
    defer app.deinit();

    // Note: Middleware system may need to be updated for H3App API
    // _ = app.use(h3z.middleware.logger);
    // _ = app.use(h3z.middleware.cors);
    // _ = app.use(h3z.middleware.security);

    // Simple routes
    _ = try app.get("/", homeHandler);
    _ = try app.get("/hello/:name", helloHandler);
    _ = try app.post("/api/data", dataHandler);
    _ = try app.get("/api/status", statusHandler);

    std.log.info("🚀 Simple H3 server starting on http://127.0.0.1:3000", .{});
    std.log.info("Press Ctrl+C to stop the server", .{});

    // Start server
    try h3z.serve(&app, h3z.ServeOptions{ .port = 3000 });
}

fn homeHandler(event: *h3z.H3Event) !void {
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

    try event.sendHtml(html);
}

fn helloHandler(event: *h3z.H3Event) !void {
    const name = event.getParam("name") orelse "Anonymous";

    const greeting = .{
        .message = "Hello from H3!",
        .name = name,
        .timestamp = std.time.timestamp(),
        .server = "H3 Simple Server",
    };

    try event.sendJsonValue(greeting);
}

fn dataHandler(event: *h3z.H3Event) !void {
    // Check if request has JSON content
    if (!event.request.isJson()) {
        event.setStatus(.bad_request);
        try event.sendError(.bad_request, "Expected JSON content");
        return;
    }

    const body = event.readBody() orelse "";

    const response_data = .{
        .received = body,
        .length = body.len,
        .processed_at = std.time.timestamp(),
        .echo = "Data received successfully",
    };

    event.setStatus(.created);
    try event.sendJsonValue(response_data);
}

fn statusHandler(event: *h3z.H3Event) !void {
    const status = .{
        .server = "H3 Simple Server",
        .status = "healthy",
        .version = "0.1.0", // h3z version
        .uptime = "running",
        .timestamp = std.time.timestamp(),
        .endpoints = .{
            .total = 4,
            .available = 4,
        },
    };

    try event.sendJsonValue(status);
}
