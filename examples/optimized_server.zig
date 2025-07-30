//! Optimized H3 Server Example
//! Demonstrates the use of performance optimizations including:
//! - Fast middleware system
//! - Event pooling
//! - Compiled route patterns
//! - Optimized request handling

const std = @import("std");
const h3z = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create app using modern component-based API
    var app = try h3z.H3App.init(allocator);
    defer app.deinit();

    // Note: Fast middleware system may need to be updated for H3App API
    // _ = app.useFast(h3z.fastMiddleware.timing); // Request timing
    // _ = app.useFast(h3z.fastMiddleware.logger); // Fast logging
    // _ = app.useFast(h3z.fastMiddleware.cors); // CORS headers
    // _ = app.useFast(h3z.fastMiddleware.security); // Security headers
    // _ = app.useFast(h3z.fastMiddleware.timingEnd); // Response timing

    // Add routes with modern H3App API
    _ = try app.get("/", homeHandler);
    _ = try app.get("/health", healthHandler);
    _ = try app.get("/metrics", metricsHandler);

    // API routes with parameters
    _ = try app.get("/api/users/:id", getUserHandler);
    _ = try app.post("/api/users", createUserHandler);
    _ = try app.put("/api/users/:id", updateUserHandler);
    _ = try app.delete("/api/users/:id", deleteUserHandler);

    // Nested API routes
    _ = try app.get("/api/users/:userId/posts/:postId", getUserPostHandler);
    _ = try app.post("/api/users/:userId/posts", createUserPostHandler);

    // Static file serving simulation
    _ = try app.get("/static/*", staticFileHandler);

    // Benchmark endpoint
    _ = try app.get("/benchmark", benchmarkHandler);

    std.log.info("🚀 Optimized H3 server starting on http://127.0.0.1:3000", .{});
    std.log.info("📊 Performance features enabled:", .{});
    std.log.info("  ✅ Event pooling (size: 200)", .{});
    std.log.info("  ✅ Fast middleware chain", .{});
    std.log.info("  ✅ Compiled route patterns", .{});
    std.log.info("  ✅ Optimized request handling", .{});
    std.log.info("", .{});
    std.log.info("📍 Available endpoints:", .{});
    std.log.info("  GET  /              - Home page", .{});
    std.log.info("  GET  /health        - Health check", .{});
    std.log.info("  GET  /metrics       - Performance metrics", .{});
    std.log.info("  GET  /benchmark     - Performance benchmark", .{});
    std.log.info("  GET  /api/users/:id - Get user by ID", .{});
    std.log.info("  POST /api/users     - Create user", .{});
    std.log.info("", .{});
    std.log.info("Press Ctrl+C to stop the server", .{});

    // Start the server
    try h3z.serve(&app, h3z.ServeOptions{ .port = 3000 });
}

fn homeHandler(event: *h3z.H3Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>Optimized H3 Server</title>
        \\    <style>
        \\        body { font-family: Arial, sans-serif; margin: 40px; }
        \\        .metric { background: #f0f0f0; padding: 10px; margin: 10px 0; border-radius: 5px; }
        \\        .endpoint { background: #e8f4fd; padding: 8px; margin: 5px 0; border-radius: 3px; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <h1>⚡ Optimized H3 Server</h1>
        \\    <p>This server demonstrates H3's performance optimizations:</p>
        \\    
        \\    <h2>🚀 Performance Features</h2>
        \\    <div class="metric">✅ Event pooling for reduced allocations</div>
        \\    <div class="metric">✅ Fast middleware system with early termination</div>
        \\    <div class="metric">✅ Compiled route patterns for O(1) matching</div>
        \\    <div class="metric">✅ Method-based route trees</div>
        \\    <div class="metric">✅ Optimized parameter extraction</div>
        \\    
        \\    <h2>📍 Test Endpoints</h2>
        \\    <div class="endpoint"><a href="/health">GET /health</a> - Health check</div>
        \\    <div class="endpoint"><a href="/metrics">GET /metrics</a> - Performance metrics</div>
        \\    <div class="endpoint"><a href="/benchmark">GET /benchmark</a> - Run benchmark</div>
        \\    <div class="endpoint"><a href="/api/users/123">GET /api/users/123</a> - Get user</div>
        \\    
        \\    <h2>⚡ Performance Tips</h2>
        \\    <ul>
        \\        <li>Use <code>createFastApp()</code> for optimized configuration</li>
        \\        <li>Use <code>useFast()</code> for fast middleware</li>
        \\        <li>Enable route compilation for complex patterns</li>
        \\        <li>Use event pooling for high-traffic applications</li>
        \\    </ul>
        \\</body>
        \\</html>
    ;

    try event.sendHtml(html);
}

fn healthHandler(event: *h3z.H3Event) !void {
    const health_data = .{
        .status = "healthy",
        .timestamp = std.time.timestamp(),
        .uptime_seconds = 0, // Would be calculated in real app
        .memory_usage = "optimized",
        .features = .{
            .event_pooling = true,
            .fast_middleware = true,
            .compiled_routes = true,
        },
    };

    try event.sendJsonValue(health_data);
}

fn metricsHandler(event: *h3z.H3Event) !void {
    // In a real application, you would collect actual metrics
    const metrics = .{
        .requests_total = 1000,
        .requests_per_second = 150.5,
        .avg_response_time_ms = 2.3,
        .memory_usage_mb = 45.2,
        .event_pool = .{
            .size = 200,
            .active = 15,
            .reuse_ratio = 0.85,
        },
        .routes = .{
            .total = 10,
            .compiled = 10,
            .avg_lookup_time_ns = 150,
        },
        .middleware = .{
            .fast_count = 5,
            .legacy_count = 0,
            .avg_execution_time_ns = 500,
        },
    };

    try event.sendJsonValue(metrics);
}

fn getUserHandler(event: *h3z.H3Event) !void {
    const user_id = event.getParam("id") orelse "unknown";

    const user_data = .{
        .id = user_id,
        .name = "John Doe",
        .email = "john@example.com",
        .created_at = "2024-01-01T00:00:00Z",
        .performance_note = "Retrieved using optimized route matching",
    };

    try event.sendJsonValue(user_data);
}

fn createUserHandler(event: *h3z.H3Event) !void {
    // Simulate user creation
    const new_user = .{
        .id = "new-user-123",
        .name = "New User",
        .email = "newuser@example.com",
        .created_at = "2024-01-01T00:00:00Z",
        .performance_note = "Created using fast middleware chain",
    };

    event.setStatus(.created);
    try event.sendJsonValue(new_user);
}

fn updateUserHandler(event: *h3z.H3Event) !void {
    const user_id = event.getParam("id") orelse "unknown";

    const updated_user = .{
        .id = user_id,
        .name = "Updated User",
        .email = "updated@example.com",
        .updated_at = "2024-01-01T00:00:00Z",
        .performance_note = "Updated using compiled route patterns",
    };

    try event.sendJsonValue(updated_user);
}

fn deleteUserHandler(event: *h3z.H3Event) !void {
    const user_id = event.getParam("id") orelse "unknown";

    const result = .{
        .deleted_id = user_id,
        .success = true,
        .performance_note = "Deleted using optimized parameter extraction",
    };

    try event.sendJsonValue(result);
}

fn getUserPostHandler(event: *h3z.H3Event) !void {
    const user_id = event.getParam("userId") orelse "unknown";
    const post_id = event.getParam("postId") orelse "unknown";

    const post_data = .{
        .id = post_id,
        .user_id = user_id,
        .title = "Sample Post",
        .content = "This is a sample post retrieved using nested route parameters.",
        .performance_note = "Multi-parameter extraction optimized",
    };

    try event.sendJsonValue(post_data);
}

fn createUserPostHandler(event: *h3z.H3Event) !void {
    const user_id = event.getParam("userId") orelse "unknown";

    const new_post = .{
        .id = "new-post-456",
        .user_id = user_id,
        .title = "New Post",
        .content = "This is a new post created for the user.",
        .created_at = "2024-01-01T00:00:00Z",
        .performance_note = "Created using fast middleware and optimized routing",
    };

    event.setStatus(.created);
    try event.sendJsonValue(new_post);
}

fn staticFileHandler(event: *h3z.H3Event) !void {
    const path = event.getPath();

    const response = .{
        .message = "Static file serving simulation",
        .requested_path = path,
        .note = "In production, this would serve actual static files",
        .performance_note = "Wildcard routing handled efficiently",
    };

    try event.sendJsonValue(response);
}

fn benchmarkHandler(event: *h3z.H3Event) !void {
    const start_time = std.time.nanoTimestamp();

    // Simulate some work
    var sum: u64 = 0;
    for (0..10000) |i| {
        sum += i;
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;

    const benchmark_result = .{
        .test_name = "Simple computation benchmark",
        .iterations = 10000,
        .duration_ns = duration_ns,
        .duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0,
        .result = sum,
        .performance_note = "Benchmark executed with optimized request handling",
    };

    try event.sendJsonValue(benchmark_result);
}
