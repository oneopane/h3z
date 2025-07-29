//! Authentication API Example
//! Demonstrates JWT-like authentication, middleware, and protected routes

const std = @import("std");
const h3z = @import("h3");

const User = struct {
    id: u32,
    username: []const u8,
    email: []const u8,
    password_hash: []const u8,
};

const Token = struct {
    user_id: u32,
    username: []const u8,
    expires_at: i64,
};

const AuthContext = struct {
    users: std.ArrayList(User),
    tokens: std.StringHashMap(Token),
    allocator: std.mem.Allocator,
};

var auth_context: AuthContext = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize auth context
    auth_context = .{
        .users = std.ArrayList(User).init(allocator),
        .tokens = std.StringHashMap(Token).init(allocator),
        .allocator = allocator,
    };
    defer auth_context.users.deinit();
    defer auth_context.tokens.deinit();

    // Add demo user
    try auth_context.users.append(.{
        .id = 1,
        .username = "admin",
        .email = "admin@example.com",
        .password_hash = "hashed_password", // In real app, use proper hashing
    });

    // Create app using modern component-based API
    var app = try h3z.H3App.init(allocator);
    defer app.deinit();

    // Note: Middleware system may need to be updated for H3App API
    // Global middleware would be implemented differently
    // _ = app.use(middlewareFunction);

    // Public routes
    _ = try app.post("/api/auth/register", registerHandler);
    _ = try app.post("/api/auth/login", loginHandler);
    _ = try app.get("/api/health", healthHandler);

    // Protected routes with auth middleware
    const protected = app.group("/api/protected");
    _ = protected.use(authMiddleware);
    _ = protected.get("/profile", getProfileHandler);
    _ = protected.put("/profile", updateProfileHandler);
    _ = protected.get("/users", getUsersHandler);
    _ = protected.post("/logout", logoutHandler);

    // Admin routes with role middleware
    const admin = app.group("/api/admin");
    _ = admin.use(authMiddleware);
    _ = admin.use(adminMiddleware);
    _ = admin.get("/users", getAllUsersHandler);
    _ = admin.delete("/users/:id", deleteUserHandler);

    std.log.info("🔐 Authentication API server starting on http://127.0.0.1:3000", .{});
    std.log.info("Default user - username: admin, password: password", .{});

    try h3z.serve(&app, h3z.ServeOptions{ .port = 3000 });
}

fn healthHandler(event: *h3.Event) !void {
    const health = .{
        .status = "healthy",
        .timestamp = std.time.timestamp(),
        .service = "auth-api",
        .version = "1.0.0",
    };
    try h3.sendJson(event, health);
}

fn registerHandler(event: *h3.Event) !void {
    const RegisterRequest = struct {
        username: []const u8,
        email: []const u8,
        password: []const u8,
    };

    const req = try h3.readJson(event, RegisterRequest);

    // Validate input
    if (req.username.len < 3) {
        try h3.response.badRequest(event, "Username must be at least 3 characters");
        return;
    }

    // Check if user exists
    for (auth_context.users.items) |user| {
        if (std.mem.eql(u8, user.username, req.username)) {
            try h3.response.badRequest(event, "Username already exists");
            return;
        }
    }

    // Create new user
    const new_user = User{
        .id = @intCast(auth_context.users.items.len + 1),
        .username = try auth_context.allocator.dupe(u8, req.username),
        .email = try auth_context.allocator.dupe(u8, req.email),
        .password_hash = try auth_context.allocator.dupe(u8, "hashed_" ++ req.password),
    };

    try auth_context.users.append(new_user);

    const response = .{
        .success = true,
        .user = .{
            .id = new_user.id,
            .username = new_user.username,
            .email = new_user.email,
        },
    };

    h3.setStatus(event, .created);
    try h3.sendJson(event, response);
}

fn loginHandler(event: *h3.Event) !void {
    const LoginRequest = struct {
        username: []const u8,
        password: []const u8,
    };

    const req = try h3.readJson(event, LoginRequest);

    // Find user
    var found_user: ?User = null;
    for (auth_context.users.items) |user| {
        if (std.mem.eql(u8, user.username, req.username)) {
            found_user = user;
            break;
        }
    }

    const user = found_user orelse {
        try event.sendStatus(.unauthorized);
        try event.sendText("Invalid credentials");
        return;
    };

    // Verify password (simplified - use proper verification in production)
    const expected_hash = try std.fmt.allocPrint(
        event.allocator,
        "hashed_{s}",
        .{req.password}
    );
    defer event.allocator.free(expected_hash);

    if (!std.mem.eql(u8, user.password_hash, expected_hash)) {
        try event.sendStatus(.unauthorized);
        try event.sendText("Invalid credentials");
        return;
    }

    // Generate token
    const token = try generateToken(user);
    const token_str = try std.fmt.allocPrint(
        auth_context.allocator,
        "token_{d}_{s}",
        .{ std.time.timestamp(), user.username }
    );

    try auth_context.tokens.put(token_str, token);

    const response = .{
        .success = true,
        .token = token_str,
        .user = .{
            .id = user.id,
            .username = user.username,
            .email = user.email,
        },
    };

    try h3.sendJson(event, response);
}

fn authMiddleware(ctx: *h3.MiddlewareContext, next: h3.Handler) !void {
    const auth_header = h3.getHeader(ctx.event, "Authorization") orelse {
        try h3.response.unauthorized(ctx.event, "Missing authorization header");
        return;
    };

    if (!std.mem.startsWith(u8, auth_header, "Bearer ")) {
        try h3.response.unauthorized(ctx.event, "Invalid authorization format");
        return;
    }

    const token_str = auth_header[7..];
    const token = auth_context.tokens.get(token_str) orelse {
        try h3.response.unauthorized(ctx.event, "Invalid token");
        return;
    };

    // Check expiration
    if (token.expires_at < std.time.timestamp()) {
        _ = auth_context.tokens.remove(token_str);
        try h3.response.unauthorized(ctx.event, "Token expired");
        return;
    }

    // Store user info in event context
    ctx.event.app_context = @ptrCast(@constCast(&token));

    try next(ctx.event);
}

fn adminMiddleware(ctx: *h3.MiddlewareContext, next: h3.Handler) !void {
    const token = @as(*const Token, @ptrCast(@alignCast(ctx.event.app_context.?)));

    // Check if user is admin (simplified - in real app, check roles)
    if (!std.mem.eql(u8, token.username, "admin")) {
        try h3.response.forbidden(event, "Admin access required");
        return;
    }

    try next(ctx.event);
}

fn getProfileHandler(event: *h3.Event) !void {
    const token = @as(*const Token, @ptrCast(@alignCast(event.app_context.?)));

    // Find user
    for (auth_context.users.items) |user| {
        if (user.id == token.user_id) {
            const profile = .{
                .id = user.id,
                .username = user.username,
                .email = user.email,
            };
            try h3.sendJson(event, profile);
            return;
        }
    }

    try h3.response.notFound(event, "User not found");
}

fn updateProfileHandler(event: *h3.Event) !void {
    const token = @as(*const Token, @ptrCast(@alignCast(event.app_context.?)));

    const UpdateRequest = struct {
        email: ?[]const u8,
    };

    const req = try h3.readJson(event, UpdateRequest);

    // Find and update user
    for (auth_context.users.items) |*user| {
        if (user.id == token.user_id) {
            if (req.email) |email| {
                user.email = try auth_context.allocator.dupe(u8, email);
            }

            const response = .{
                .success = true,
                .user = .{
                    .id = user.id,
                    .username = user.username,
                    .email = user.email,
                },
            };
            try h3.sendJson(event, response);
            return;
        }
    }

    try h3.response.notFound(event, "User not found");
}

fn getUsersHandler(event: *h3.Event) !void {
    _ = event;
    var users_list = std.ArrayList(struct {
        id: u32,
        username: []const u8,
        email: []const u8,
    }).init(event.allocator);
    defer users_list.deinit();

    for (auth_context.users.items) |user| {
        try users_list.append(.{
            .id = user.id,
            .username = user.username,
            .email = user.email,
        });
    }

    try h3.sendJson(event, users_list.items);
}

fn logoutHandler(event: *h3.Event) !void {
    const auth_header = h3.getHeader(event, "Authorization").?;
    const token_str = auth_header[7..];

    _ = auth_context.tokens.remove(token_str);

    const response = .{
        .success = true,
        .message = "Logged out successfully",
    };

    try h3.sendJson(event, response);
}

fn getAllUsersHandler(event: *h3.Event) !void {
    // Admin-only endpoint
    try getUsersHandler(event);
}

fn deleteUserHandler(event: *h3.Event) !void {
    const id_str = h3.getParam(event, "id") orelse return error.MissingParam;
    const id = try std.fmt.parseInt(u32, id_str, 10);

    // Find and remove user
    var index: ?usize = null;
    for (auth_context.users.items, 0..) |user, i| {
        if (user.id == id) {
            index = i;
            break;
        }
    }

    if (index) |i| {
        _ = auth_context.users.orderedRemove(i);
        try h3.response.noContent(event);
    } else {
        try h3.response.notFound(event, "User not found");
    }
}

fn generateToken(user: User) Token {
    return .{
        .user_id = user.id,
        .username = user.username,
        .expires_at = std.time.timestamp() + (60 * 60), // 1 hour
    };
}

// Add this helper for forbidden responses
const response = struct {
    fn forbidden(event: *h3.Event, message: []const u8) !void {
        h3.setStatus(event, .forbidden);
        const error_response = .{
            .error = "Forbidden",
            .message = message,
        };
        try h3.sendJson(event, error_response);
    }
};