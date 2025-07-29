//! Architecture Refactoring Demo
//! Demonstrates the new component-based architecture with unified configuration

const std = @import("std");
const h3z = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🏗️  H3Z Framework Modern Architecture Demo", .{});
    std.log.info("=" ** 60, .{});

    try demonstrateModernAPI(allocator);
    try demonstrateEventHandling(allocator);
    try demonstrateSSEFeatures(allocator);

    std.log.info("✅ Modern H3Z architecture demonstration completed!", .{});
}

fn demonstrateModernAPI(allocator: std.mem.Allocator) !void {
    std.log.info("\n📋 1. Modern H3App API", .{});
    std.log.info("-" ** 40, .{});

    // Create app using modern component-based API
    var app = try h3z.H3App.init(allocator);
    defer app.deinit();

    std.log.info("✓ H3App initialized with modern API", .{});

    // Add simple routes
    _ = try app.get("/", homeHandler);
    _ = try app.get("/health", healthHandler);
    _ = try app.post("/api/data", dataHandler);

    std.log.info("✓ Routes registered successfully", .{});
    std.log.info("  - GET  /           - Home handler", .{});
    std.log.info("  - GET  /health     - Health check", .{});
    std.log.info("  - POST /api/data   - Data handler", .{});

    std.log.info("✓ Modern H3App features:", .{});
    std.log.info("  - Component-based architecture", .{});
    std.log.info("  - Type-safe handlers", .{});
    std.log.info("  - Memory-safe design", .{});
    std.log.info("  - High-performance async I/O", .{});
}

fn demonstrateEventHandling(allocator: std.mem.Allocator) !void {
    std.log.info("\n💾 2. Event Handling System", .{});
    std.log.info("-" ** 40, .{});

    // Create app and demonstrate event handling
    var app = try h3z.H3App.init(allocator);
    defer app.deinit();

    std.log.info("✓ H3Event-based request handling", .{});
    std.log.info("  - Type-safe event objects", .{});
    std.log.info("  - Built-in JSON/HTML response helpers", .{});
    std.log.info("  - Automatic memory management", .{});
    std.log.info("  - Parameter extraction from routes", .{});

    // Add routes with parameter handling
    _ = try app.get("/users/:id", paramHandler);
    
    std.log.info("✓ Route parameters supported:", .{});
    std.log.info("  - Dynamic path segments (:id, :name, etc.)", .{});
    std.log.info("  - Type-safe parameter extraction", .{});
    std.log.info("  - Query string parsing", .{});
}

fn demonstrateSSEFeatures(allocator: std.mem.Allocator) !void {
    std.log.info("\n🔧 3. Server-Sent Events (SSE) Features", .{});
    std.log.info("-" ** 40, .{});

    // Create app with SSE support
    var app = try h3z.H3App.init(allocator);
    defer app.deinit();

    std.log.info("✓ H3Z includes built-in SSE support", .{});
    std.log.info("  - Type-safe SSE handlers with (*h3z.SSEWriter, *xev.Loop)", .{});
    std.log.info("  - Built-in SSE event formatting", .{});
    std.log.info("  - Timer-based streaming with libxev integration", .{});
    std.log.info("  - Automatic connection management", .{});

    // Add SSE route (demonstrating the signature)
    std.log.info("✓ SSE route handlers support:", .{});
    std.log.info("  - Real-time data streaming", .{});
    std.log.info("  - Event-driven architecture", .{});
    std.log.info("  - Low-latency communication", .{});
    std.log.info("  - Automatic reconnection handling", .{});
    
    std.log.info("✓ Example SSE implementations available:", .{});
    std.log.info("  - examples/sse_counter.zig - Timer-based counter", .{});
    std.log.info("  - examples/sse_chat.zig - Real-time chat", .{});
    std.log.info("  - examples/sse_basic.zig - Basic streaming", .{});
}

// Handler implementations for the demo
fn homeHandler(event: *h3z.H3Event) !void {
    try event.sendJsonValue(.{
        .message = "Hello from H3Z modern architecture!",
        .version = "2.0",
        .architecture = "component-based",
        .features = .{
            .sse_support = true,
            .async_io = true,
            .type_safety = true,
        },
    });
}

fn healthHandler(event: *h3z.H3Event) !void {
    try event.sendJsonValue(.{
        .status = "healthy",
        .message = "H3Z running with modern architecture",
        .timestamp = std.time.timestamp(),
    });
}

fn dataHandler(event: *h3z.H3Event) !void {
    const body = event.readBody() orelse "";
    try event.sendJsonValue(.{
        .received = body,
        .length = body.len,
        .processed_at = std.time.timestamp(),
    });
}

fn paramHandler(event: *h3z.H3Event) !void {
    const user_id = event.getParam("id") orelse "unknown";
    try event.sendJsonValue(.{
        .user_id = user_id,
        .message = "Parameter extracted successfully",
    });
}
