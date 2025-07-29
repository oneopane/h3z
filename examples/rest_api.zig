//! H3 Example Application
//!
//! This demonstrates how to use the H3 HTTP framework with the new API.

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

    // Add routes
    _ = try app.get("/", helloHandler);
    _ = try app.get("/api/users", getUsersHandler);
    _ = try app.get("/api/users/:id", getUserHandler);
    _ = try app.post("/api/users", createUserHandler);
    // Note: app.all() may not be available, using get() instead
    _ = try app.get("/health", healthHandler);

    // Start server
    std.log.info("Starting H3 server...", .{});
    try h3z.serve(&app, h3z.ServeOptions{ .port = 3000 });
}

fn helloHandler(event: *h3z.H3Event) !void {
    try event.sendText("⚡️ Hello from H3Z!");
}

fn getUsersHandler(event: *h3z.H3Event) !void {
    const users = [_]struct { id: u32, name: []const u8 }{
        .{ .id = 1, .name = "Alice" },
        .{ .id = 2, .name = "Bob" },
        .{ .id = 3, .name = "Charlie" },
    };

    try event.sendJsonValue(.{ .users = users });
}

fn getUserHandler(event: *h3z.H3Event) !void {
    const user_id = event.getParam("id") orelse {
        try event.sendError(.bad_request, "Missing user ID");
        return;
    };

    const id = std.fmt.parseInt(u32, user_id, 10) catch {
        try event.sendError(.bad_request, "Invalid user ID");
        return;
    };

    if (id > 3) {
        try event.sendError(.not_found, "User not found");
        return;
    }

    const user = .{ .id = id, .name = "User Name" };
    try event.sendJsonValue(user);
}

fn createUserHandler(event: *h3z.H3Event) !void {
    if (!event.request.isJson()) {
        try event.sendError(.bad_request, "Expected JSON content type");
        return;
    }

    const User = struct { name: []const u8 };
    const user_data = event.readJson(User) catch {
        try event.sendError(.bad_request, "Invalid JSON");
        return;
    };

    event.setStatus(.created);
    const new_user = .{ .id = 4, .name = user_data.name };
    try event.sendJsonValue(new_user);
}

fn healthHandler(event: *h3z.H3Event) !void {
    try event.sendJsonValue(.{
        .status = "ok",
        .timestamp = std.time.timestamp(),
        .method = @tagName(event.request.method),
    });
}

test "main module tests" {
    // Import all test files to run them
    _ = @import("h3z");
}
