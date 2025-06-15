//! Response utility functions
//! Provides helper functions for working with HTTP responses

const std = @import("std");
const H3Event = @import("../core/event.zig").H3Event;
const HttpStatus = @import("../http/status.zig").HttpStatus;

pub fn send(event: *H3Event, text: []const u8) !void {
    try event.sendText(text);
}

pub fn sendJsonValue(event: *H3Event, data: anytype) !void {
    try event.sendJsonValue(data);
}

pub fn sendJson(event: *H3Event, json: []const u8) !void {
    try event.setHeader("Content-Type", "application/json");
    try event.sendText(json);
}

pub fn sendHtml(event: *H3Event, html: []const u8) !void {
    try event.setHeader("Content-Type", "text/html; charset=utf-8");
    try event.sendText(html);
}

/// Send file with automatic MIME type detection
pub fn sendFile(event: *H3Event, file_path: []const u8) !void {
    const file_content = std.fs.cwd().readFileAlloc(event.allocator, file_path, 10 * 1024 * 1024) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try notFound(event, "File not found");
                return;
            },
            else => {
                try internalServerError(event, "Failed to read file");
                return;
            },
        }
    };

    // Set appropriate content type based on file extension
    const content_type = getMimeType(file_path);
    try event.setHeader("Content-Type", content_type);

    try event.sendText(file_content);
}

pub fn redirect(event: *H3Event, url: []const u8) !void {
    event.setStatus(.found);
    try event.setHeader("Location", url);
    try event.sendText("");
}

pub fn redirectPermanent(event: *H3Event, url: []const u8) !void {
    event.setStatus(.moved_permanently);
    try event.setHeader("Location", url);
    try event.sendText("");
}

pub fn setStatus(event: *H3Event, status: HttpStatus) void {
    event.setStatus(status);
}

pub fn setHeader(event: *H3Event, name: []const u8, value: []const u8) !void {
    try event.setHeader(name, value);
}

/// Set multiple headers in a single call
pub fn setHeaders(event: *H3Event, headers: []const struct { name: []const u8, value: []const u8 }) !void {
    for (headers) |header| {
        try setHeader(event, header.name, header.value);
    }
}

/// Set HTTP cookie with configurable options
pub fn setCookie(event: *H3Event, name: []const u8, value: []const u8, options: struct {
    max_age: ?i32 = null,
    path: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    secure: bool = false,
    http_only: bool = false,
    same_site: ?[]const u8 = null,
}) !void {
    var cookie_value = std.ArrayList(u8).init(event.allocator);
    defer cookie_value.deinit();

    try cookie_value.writer().print("{s}={s}", .{ name, value });

    if (options.max_age) |max_age| {
        try cookie_value.writer().print("; Max-Age={d}", .{max_age});
    }

    if (options.path) |path| {
        try cookie_value.writer().print("; Path={s}", .{path});
    }

    if (options.domain) |domain| {
        try cookie_value.writer().print("; Domain={s}", .{domain});
    }

    if (options.secure) {
        try cookie_value.writer().writeAll("; Secure");
    }

    if (options.http_only) {
        try cookie_value.writer().writeAll("; HttpOnly");
    }

    if (options.same_site) |same_site| {
        try cookie_value.writer().print("; SameSite={s}", .{same_site});
    }

    try setHeader(event, "Set-Cookie", cookie_value.items);
}

pub fn clearCookie(event: *H3Event, name: []const u8, path: ?[]const u8) !void {
    try setCookie(event, name, "", .{
        .max_age = 0,
        .path = path,
    });
}

// Common HTTP status responses

pub fn ok(event: *H3Event, data: anytype) !void {
    try sendJsonValue(event, data);
}

pub fn created(event: *H3Event, data: anytype) !void {
    setStatus(event, .created);
    try sendJsonValue(event, data);
}

pub fn noContent(event: *H3Event) !void {
    setStatus(event, .no_content);
    try send(event, "");
}

/// Send structured error response with JSON format
pub fn badRequest(event: *H3Event, message: []const u8) !void {
    setStatus(event, .bad_request);
    const error_response = struct {
        @"error": []const u8,
        message: []const u8,
        status: u16,
    }{
        .@"error" = "Bad Request",
        .message = message,
        .status = 400,
    };
    try sendJsonValue(event, error_response);
}

pub fn unauthorized(event: *H3Event, message: []const u8) !void {
    setStatus(event, .unauthorized);
    try sendJson(event, try std.fmt.allocPrint(event.allocator, "{{\"error\":\"Unauthorized\",\"message\":\"{s}\",\"status\":401}}", .{message}));
}

pub fn forbidden(event: *H3Event, message: []const u8) !void {
    setStatus(event, .forbidden);
    try sendJson(event, try std.fmt.allocPrint(event.allocator, "{{\"error\":\"Forbidden\",\"message\":\"{s}\",\"status\":403}}", .{message}));
}

pub fn notFound(event: *H3Event, message: []const u8) !void {
    setStatus(event, .not_found);
    try sendJson(event, try std.fmt.allocPrint(event.allocator, "{{\"error\":\"Not Found\",\"message\":\"{s}\",\"status\":404}}", .{message}));
}

pub fn conflict(event: *H3Event, message: []const u8) !void {
    setStatus(event, .conflict);
    try sendJson(event, try std.fmt.allocPrint(event.allocator, "{{\"error\":\"Conflict\",\"message\":\"{s}\",\"status\":409}}", .{message}));
}

pub fn unprocessableEntity(event: *H3Event, message: []const u8) !void {
    setStatus(event, .unprocessable_entity);
    try sendJson(event, try std.fmt.allocPrint(event.allocator, "{{\"error\":\"Unprocessable Entity\",\"message\":\"{s}\",\"status\":422}}", .{message}));
}

pub fn internalServerError(event: *H3Event, message: []const u8) !void {
    setStatus(event, .internal_server_error);
    try sendJson(event, try std.fmt.allocPrint(event.allocator, "{{\"error\":\"Internal Server Error\",\"message\":\"{s}\",\"status\":500}}", .{message}));
}

pub fn serviceUnavailable(event: *H3Event, message: []const u8) !void {
    setStatus(event, .service_unavailable);
    try sendJson(event, try std.fmt.allocPrint(event.allocator, "{{\"error\":\"Service Unavailable\",\"message\":\"{s}\",\"status\":503}}", .{message}));
}

// Helper function to get MIME type based on file extension
fn getMimeType(file_path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, file_path, ".html")) return "text/html";
    if (std.mem.endsWith(u8, file_path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, file_path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, file_path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, file_path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, file_path, ".jpg") or std.mem.endsWith(u8, file_path, ".jpeg")) return "image/jpeg";
    if (std.mem.endsWith(u8, file_path, ".gif")) return "image/gif";
    if (std.mem.endsWith(u8, file_path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, file_path, ".pdf")) return "application/pdf";
    if (std.mem.endsWith(u8, file_path, ".txt")) return "text/plain";
    if (std.mem.endsWith(u8, file_path, ".xml")) return "application/xml";
    return "application/octet-stream";
}
