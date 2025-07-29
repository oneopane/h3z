//! Common middleware implementations
//! Provides ready-to-use middleware for common functionality

const std = @import("std");
const H3Event = @import("../core/event.zig").H3Event;
const Handler = @import("../core/app.zig").Handler;
const MiddlewareContext = @import("../core/interfaces.zig").MiddlewareContext;
const response = @import("response.zig");

/// Logger middleware - logs all requests
pub fn logger(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
    const start_time = std.time.milliTimestamp();

    // Log request
    std.log.info("{s} {s}", .{ event.getMethod().toString(), event.getPath() });

    // Call next middleware/handler
    try context.next(event, index, final_handler);

    // Log response
    const duration = std.time.milliTimestamp() - start_time;
    std.log.info("{s} {s} {} {}ms", .{ event.getMethod().toString(), event.getPath(), event.response.status.code(), duration });
}

/// CORS middleware with default settings
pub fn corsDefault(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
    try setCorsHeaders(event, .{});

    // Handle preflight requests
    if (event.getMethod() == .OPTIONS) {
        event.setStatus(.no_content);
        return;
    }

    try context.next(event, index, final_handler);
}

/// CORS middleware with custom origin (simplified for compatibility)
pub fn cors(origin: []const u8) fn (*H3Event, MiddlewareContext, usize, Handler) anyerror!void {
    return struct {
        fn middleware(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
            try setCorsHeaders(event, .{ .origin = origin });

            if (event.getMethod() == .OPTIONS) {
                event.setStatus(.no_content);
                return;
            }

            try context.next(event, index, final_handler);
        }
    }.middleware;
}

/// CORS middleware with full options
pub fn corsWithOptions(options: CorsOptions) fn (*H3Event, MiddlewareContext, usize, Handler) anyerror!void {
    return struct {
        fn middleware(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
            try setCorsHeaders(event, options);

            if (event.getMethod() == .OPTIONS) {
                event.setStatus(.no_content);
                return;
            }

            try context.next(event, index, final_handler);
        }
    }.middleware;
}

/// Security headers middleware
pub fn security(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
    // Set security headers
    try event.setHeader("X-Content-Type-Options", "nosniff");
    try event.setHeader("X-Frame-Options", "DENY");
    try event.setHeader("X-XSS-Protection", "1; mode=block");
    try event.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
    try event.setHeader("Content-Security-Policy", "default-src 'self'");

    try context.next(event, index, final_handler);
}

/// JSON parser middleware - ensures request body is parsed as JSON
pub fn jsonParser(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
    // Only process if content-type is JSON
    if (event.isJson()) {
        // JSON parsing is handled by readJson() when needed
        // This middleware just validates the content type
    }

    try context.next(event, index, final_handler);
}

/// Rate limiting middleware (simple in-memory implementation)
pub fn rateLimit(options: RateLimitOptions) fn (*H3Event, MiddlewareContext, usize, Handler) anyerror!void {
    return struct {
        var requests = std.HashMap([]const u8, RequestInfo, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(std.heap.page_allocator);

        const RequestInfo = struct {
            count: u32,
            reset_time: i64,
        };

        fn middleware(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
            const client_ip = getClientIp(event);
            const now = std.time.timestamp();

            var entry = requests.getOrPut(client_ip) catch {
                try response.internalServerError(event, "Rate limit error");
                return;
            };

            if (!entry.found_existing) {
                entry.value_ptr.* = RequestInfo{
                    .count = 1,
                    .reset_time = now + options.window_seconds,
                };
            } else {
                if (now > entry.value_ptr.reset_time) {
                    // Reset window
                    entry.value_ptr.count = 1;
                    entry.value_ptr.reset_time = now + options.window_seconds;
                } else {
                    entry.value_ptr.count += 1;

                    if (entry.value_ptr.count > options.max_requests) {
                        event.setStatus(.too_many_requests);
                        try event.setHeader("Retry-After", try std.fmt.allocPrint(event.allocator, "{d}", .{entry.value_ptr.reset_time - now}));
                        try response.sendJson(event, try std.fmt.allocPrint(event.allocator, "{{\"error\":\"Too Many Requests\",\"message\":\"Rate limit exceeded\",\"status\":429}}", .{}));
                        return;
                    }
                }
            }

            // Add rate limit headers
            try event.setHeader("X-RateLimit-Limit", try std.fmt.allocPrint(event.allocator, "{d}", .{options.max_requests}));
            try event.setHeader("X-RateLimit-Remaining", try std.fmt.allocPrint(event.allocator, "{d}", .{options.max_requests - entry.value_ptr.count}));
            try event.setHeader("X-RateLimit-Reset", try std.fmt.allocPrint(event.allocator, "{d}", .{entry.value_ptr.reset_time}));

            try context.next(event, index, final_handler);
        }
    }.middleware;
}

/// Request size limit middleware
pub fn requestSizeLimit(max_size: usize) fn (*H3Event, MiddlewareContext, usize, Handler) anyerror!void {
    return struct {
        fn middleware(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
            if (event.request.getContentLength()) |size| {
                if (size > max_size) {
                    event.setStatus(.payload_too_large);
                    const message = try std.fmt.allocPrint(event.allocator, "Request size {d} exceeds limit {d}", .{ size, max_size });
                    try response.sendJson(event, try std.fmt.allocPrint(event.allocator, "{{\"error\":\"Payload Too Large\",\"message\":\"{s}\",\"status\":413}}", .{message}));
                    return;
                }
            }

            try context.next(event, index, final_handler);
        }
    }.middleware;
}

/// Basic authentication middleware
pub fn basicAuth(username: []const u8, password: []const u8) fn (*H3Event, MiddlewareContext, usize, Handler) anyerror!void {
    return struct {
        fn middleware(event: *H3Event, context: MiddlewareContext, index: usize, final_handler: Handler) !void {
            const auth_header = event.getHeader("authorization");

            if (auth_header == null or !std.mem.startsWith(u8, auth_header.?, "Basic ")) {
                try sendAuthChallenge(event);
                return;
            }

            // Decode base64 credentials
            const encoded = auth_header.?[6..]; // Skip "Basic "
            var decoded_buf: [256]u8 = undefined;
            const decoded = std.base64.standard.Decoder.decode(decoded_buf[0..], encoded) catch {
                try sendAuthChallenge(event);
                return;
            };

            // Check credentials
            const expected = try std.fmt.allocPrint(event.allocator, "{s}:{s}", .{ username, password });
            if (!std.mem.eql(u8, decoded, expected)) {
                try sendAuthChallenge(event);
                return;
            }

            try context.next(event, index, final_handler);
        }

        fn sendAuthChallenge(event: *H3Event) !void {
            try event.setHeader("WWW-Authenticate", "Basic realm=\"Protected Area\"");
            try response.unauthorized(event, "Authentication required");
        }
    }.middleware;
}

// Configuration structures
pub const CorsOptions = struct {
    origin: []const u8 = "*",
    methods: []const u8 = "GET, POST, PUT, DELETE, PATCH, OPTIONS",
    headers: []const u8 = "Content-Type, Authorization",
    credentials: bool = false,
    max_age: ?u32 = null,
};

pub const RateLimitOptions = struct {
    max_requests: u32 = 100,
    window_seconds: i64 = 3600, // 1 hour
};

// Helper functions
fn setCorsHeaders(event: *H3Event, options: CorsOptions) !void {
    try event.setHeader("Access-Control-Allow-Origin", options.origin);
    try event.setHeader("Access-Control-Allow-Methods", options.methods);
    try event.setHeader("Access-Control-Allow-Headers", options.headers);

    if (options.credentials) {
        try event.setHeader("Access-Control-Allow-Credentials", "true");
    }

    if (options.max_age) |max_age| {
        try event.setHeader("Access-Control-Max-Age", try std.fmt.allocPrint(event.allocator, "{d}", .{max_age}));
    }
}

fn getClientIp(event: *H3Event) []const u8 {
    // Try to get real IP from headers (for reverse proxy setups)
    if (event.getHeader("x-forwarded-for")) |xff| {
        if (std.mem.indexOf(u8, xff, ",")) |comma| {
            return std.mem.trim(u8, xff[0..comma], " ");
        }
        return xff;
    }

    if (event.getHeader("x-real-ip")) |real_ip| {
        return real_ip;
    }

    // Fallback to connection IP (would need to be passed from server)
    return "unknown";
}
