//! Real HTTP Server Example
//! Demonstrates running an actual HTTP server with H3

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

    // Add routes
    _ = try app.get("/", homeHandler);
    _ = try app.get("/api/health", healthHandler);
    _ = try app.get("/api/time", timeHandler);
    _ = try app.post("/api/echo", echoHandler);
    _ = try app.get("/api/users/:id", getUserHandler);

    std.log.info("🚀 Starting H3 HTTP Server", .{});
    std.log.info("============================", .{});
    std.log.info("", .{});
    std.log.info("Server will start on: http://127.0.0.1:3000", .{});
    std.log.info("", .{});
    std.log.info("Available endpoints:", .{});
    std.log.info("  GET  /              - Home page", .{});
    std.log.info("  GET  /api/health    - Health check", .{});
    std.log.info("  GET  /api/time      - Current time", .{});
    std.log.info("  POST /api/echo      - Echo request", .{});
    std.log.info("  GET  /api/users/:id - Get user by ID", .{});
    std.log.info("", .{});
    std.log.info("Press Ctrl+C to stop the server", .{});
    std.log.info("", .{});

    // Start the server
    try h3z.serve(&app, h3z.ServeOptions{
        .host = "127.0.0.1",
        .port = 3000,
    });
}

// Route handlers
fn homeHandler(event: *h3z.H3Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>H3 HTTP Server</title>
        \\    <style>
        \\        body { 
        \\            font-family: Arial, sans-serif; 
        \\            max-width: 800px; 
        \\            margin: 0 auto; 
        \\            padding: 20px;
        \\            background: #f5f5f5;
        \\        }
        \\        .container {
        \\            background: white;
        \\            padding: 30px;
        \\            border-radius: 10px;
        \\            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        \\        }
        \\        .endpoint {
        \\            background: #f8f9fa;
        \\            padding: 10px;
        \\            margin: 10px 0;
        \\            border-radius: 5px;
        \\            border-left: 4px solid #007acc;
        \\        }
        \\        .method {
        \\            font-weight: bold;
        \\            color: #007acc;
        \\        }
        \\        a {
        \\            color: #007acc;
        \\            text-decoration: none;
        \\        }
        \\        a:hover {
        \\            text-decoration: underline;
        \\        }
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="container">
        \\        <h1>⚡ H3 HTTP Server</h1>
        \\        <p>Welcome! This is a real HTTP server built with the H3 framework for Zig.</p>
        \\        
        \\        <h2>🔗 Available Endpoints</h2>
        \\        
        \\        <div class="endpoint">
        \\            <span class="method">GET</span> <a href="/api/health">/api/health</a>
        \\            <p>Health check endpoint</p>
        \\        </div>
        \\        
        \\        <div class="endpoint">
        \\            <span class="method">GET</span> <a href="/api/time">/api/time</a>
        \\            <p>Get current server time</p>
        \\        </div>
        \\        
        \\        <div class="endpoint">
        \\            <span class="method">GET</span> <a href="/api/users/123">/api/users/:id</a>
        \\            <p>Get user by ID (try different IDs)</p>
        \\        </div>
        \\        
        \\        <div class="endpoint">
        \\            <span class="method">POST</span> /api/echo
        \\            <p>Echo request body (use curl or Postman)</p>
        \\            <pre>curl -X POST http://localhost:3000/api/echo -H "Content-Type: application/json" -d '{"message": "Hello H3!"}'</pre>
        \\        </div>
        \\        
        \\        <h2>🛠️ Framework Features</h2>
        \\        <ul>
        \\            <li>✅ Zero dependencies (only Zig standard library)</li>
        \\            <li>✅ Fast HTTP request/response handling</li>
        \\            <li>✅ Middleware system with proper chain execution</li>
        \\            <li>✅ Route parameters and query strings</li>
        \\            <li>✅ JSON request/response handling</li>
        \\            <li>✅ CORS support</li>
        \\            <li>✅ Request logging</li>
        \\        </ul>
        \\        
        \\        <h2>📚 Learn More</h2>
        \\        <p>Check out the <a href="https://github.com/dg0230/h3z">H3 GitHub repository</a> for documentation and examples.</p>
        \\    </div>
        \\</body>
        \\</html>
    ;

    try event.sendHtml(html);
}

fn healthHandler(event: *h3z.H3Event) !void {
    const health = .{
        .status = "healthy",
        .server = "H3",
        .version = "0.1.0",
        .timestamp = std.time.timestamp(),
        .uptime = "running",
        .memory = .{
            .used = "unknown",
            .available = "unknown",
        },
    };

    try event.sendJsonValue(health);
}

fn timeHandler(event: *h3z.H3Event) !void {
    const now = std.time.timestamp();
    const time_info = .{
        .timestamp = now,
        .iso_string = "2025-01-14T01:30:00Z", // In real app, format properly
        .timezone = "UTC",
        .server_time = now,
    };

    try event.sendJsonValue(time_info);
}

fn echoHandler(event: *h3z.H3Event) !void {
    const body = event.readBody() orelse "";

    const echo_response = .{
        .message = "Echo response from H3 server",
        .method = @tagName(event.request.method),
        .path = event.getPath(),
        .headers = .{
            .content_type = event.request.getHeader("content-type"),
            .user_agent = event.request.getHeader("user-agent"),
            .host = event.request.getHeader("host"),
        },
        .body = .{
            .received = body,
            .length = body.len,
            .is_json = event.request.isJson(),
        },
        .timestamp = std.time.timestamp(),
    };

    try event.sendJsonValue(echo_response);
}

fn getUserHandler(event: *h3z.H3Event) !void {
    const user_id = event.getParam("id") orelse "unknown";

    // Parse user ID
    const id = std.fmt.parseInt(u32, user_id, 10) catch {
        try event.sendError(.bad_request, "Invalid user ID format");
        return;
    };

    // Mock user data
    const user = .{
        .id = id,
        .username = try std.fmt.allocPrint(event.allocator, "user_{d}", .{id}),
        .email = try std.fmt.allocPrint(event.allocator, "user_{d}@example.com", .{id}),
        .created_at = std.time.timestamp() - (id * 86400), // Mock creation time
        .active = id % 2 == 1, // Odd IDs are active
        .profile = .{
            .display_name = try std.fmt.allocPrint(event.allocator, "User {d}", .{id}),
            .bio = "This is a mock user profile generated by H3",
            .location = "Internet",
        },
    };

    try event.sendJsonValue(user);
}
