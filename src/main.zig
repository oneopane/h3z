//! ZH3 Example Application
//!
//! This demonstrates how to use the ZH3 HTTP framework.

const std = @import("std");
const zh3 = @import("zh3_lib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create H3 app
    var app = zh3.H3.init(allocator);
    defer app.deinit();

    // Add middleware
    _ = app.use(zh3.utils.logger);

    // Add routes
    _ = app.get("/", helloHandler);
    _ = app.get("/api/users", getUsersHandler);
    _ = app.get("/api/users/:id", getUserHandler);
    _ = app.post("/api/users", createUserHandler);
    _ = app.all("/health", healthHandler);

    // Start server
    std.log.info("Starting ZH3 server...", .{});
    try zh3.serve(&app, .{ .port = 3000 });
}

fn helloHandler(event: *zh3.H3Event) !void {
    try zh3.utils.send(event, "⚡️ Hello from ZH3!");
}

fn getUsersHandler(event: *zh3.H3Event) !void {
    const users = [_]struct { id: u32, name: []const u8 }{
        .{ .id = 1, .name = "Alice" },
        .{ .id = 2, .name = "Bob" },
        .{ .id = 3, .name = "Charlie" },
    };

    try zh3.utils.sendJsonValue(event, .{ .users = users });
}

fn getUserHandler(event: *zh3.H3Event) !void {
    const user_id = zh3.utils.getParam(event, "id") orelse {
        try zh3.utils.badRequest(event, "Missing user ID");
        return;
    };

    const id = std.fmt.parseInt(u32, user_id, 10) catch {
        try zh3.utils.badRequest(event, "Invalid user ID");
        return;
    };

    if (id > 3) {
        try zh3.utils.notFound(event, "User not found");
        return;
    }

    const user = .{ .id = id, .name = "User Name" };
    try zh3.utils.sendJsonValue(event, user);
}

fn createUserHandler(event: *zh3.H3Event) !void {
    if (!event.isJson()) {
        try zh3.utils.badRequest(event, "Expected JSON content type");
        return;
    }

    const User = struct { name: []const u8 };
    const user_data = zh3.utils.readJson(event, User) catch {
        try zh3.utils.badRequest(event, "Invalid JSON");
        return;
    };

    event.setStatus(.created);
    const new_user = .{ .id = 4, .name = user_data.name };
    try zh3.utils.sendJsonValue(event, new_user);
}

fn healthHandler(event: *zh3.H3Event) !void {
    try zh3.utils.sendJsonValue(event, .{
        .status = "ok",
        .timestamp = std.time.timestamp(),
        .method = event.getMethod().toString(),
    });
}

test "main module tests" {
    // Import all test files to run them
    _ = @import("zh3_lib");
}
