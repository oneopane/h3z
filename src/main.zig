//! H3 Example Application
//!
//! This demonstrates how to use the H3 HTTP framework with the new API.

const std = @import("std");
const h3 = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create H3 app with new API
    var app = h3.createApp(allocator);
    defer app.deinit();

    // Add middleware
    _ = app.use(h3.middleware.logger);

    // Add routes
    _ = app.get("/", helloHandler);
    _ = app.get("/api/users", getUsersHandler);
    _ = app.get("/api/users/:id", getUserHandler);
    _ = app.post("/api/users", createUserHandler);
    _ = app.all("/health", healthHandler);

    // Start server
    std.log.info("Starting H3 server...", .{});
    try h3.serve(&app, .{ .port = 3000 });
}

fn helloHandler(event: *h3.Event) !void {
    try h3.sendText(event, "⚡️ Hello from H3!");
}

fn getUsersHandler(event: *h3.Event) !void {
    const users = [_]struct { id: u32, name: []const u8 }{
        .{ .id = 1, .name = "Alice" },
        .{ .id = 2, .name = "Bob" },
        .{ .id = 3, .name = "Charlie" },
    };

    try h3.sendJson(event, .{ .users = users });
}

fn getUserHandler(event: *h3.Event) !void {
    const user_id = h3.getParam(event, "id") orelse {
        try h3.response.badRequest(event, "Missing user ID");
        return;
    };

    const id = std.fmt.parseInt(u32, user_id, 10) catch {
        try h3.response.badRequest(event, "Invalid user ID");
        return;
    };

    if (id > 3) {
        try h3.response.notFound(event, "User not found");
        return;
    }

    const user = .{ .id = id, .name = "User Name" };
    try h3.sendJson(event, user);
}

fn createUserHandler(event: *h3.Event) !void {
    if (!h3.isJson(event)) {
        try h3.response.badRequest(event, "Expected JSON content type");
        return;
    }

    const User = struct { name: []const u8 };
    const user_data = h3.readJson(event, User) catch {
        try h3.response.badRequest(event, "Invalid JSON");
        return;
    };

    event.setStatus(.created);
    const new_user = .{ .id = 4, .name = user_data.name };
    try h3.sendJson(event, new_user);
}

fn healthHandler(event: *h3.Event) !void {
    try h3.sendJson(event, .{
        .status = "ok",
        .timestamp = std.time.timestamp(),
        .method = h3.getMethod(event).toString(),
    });
}

test "main module tests" {
    // Import all test files to run them
    _ = @import("h3");
}
