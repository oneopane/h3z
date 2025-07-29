//! Minimal SSE Example
//! Sends just one event to test the connection

const std = @import("std");
const h3z = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create app using legacy API
    var app = try h3z.H3.init(allocator);
    defer app.deinit();

    // SSE endpoint
    _ = app.get("/events", sseHandler);
    
    // HTML page
    _ = app.get("/", htmlHandler);

    // Start server
    std.log.info("Minimal SSE example starting on http://localhost:3000", .{});
    
    try h3z.serve(&app, h3z.ServeOptions{
        .port = 3000,
        .host = "127.0.0.1",
    });
}

/// Handler that sets up SSE streaming
fn sseHandler(event: *h3z.Event) !void {
    // Start SSE mode
    try event.startSSE();
    
    // Set the streaming callback
    event.setStreamCallback(streamMinimal);
}

/// Minimal streaming callback - just send one event
fn streamMinimal(writer: *h3z.SSEWriter) !void {
    defer writer.close();
    
    std.log.info("SSE minimal streaming started", .{});
    
    // Send just one event
    try writer.sendEvent(h3z.SSEEvent{
        .data = "Hello from SSE!",
        .event = "test",
        .id = "1",
    });
    
    std.log.info("SSE minimal streaming completed", .{});
}

/// Serve HTML page with curl command
fn htmlHandler(event: *h3z.Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>Minimal SSE Test</title>
        \\    <style>
        \\        body { font-family: Arial, sans-serif; margin: 40px; }
        \\        .command { background: #f4f4f4; padding: 10px; font-family: monospace; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <h1>Minimal SSE Test</h1>
        \\    <p>Test with:</p>
        \\    <div class="command">curl -N http://localhost:3000/events</div>
        \\</body>
        \\</html>
    ;
    
    try event.sendHtml(html);
}