//! Security utilities for H3 framework
//! Provides security headers, CSRF protection, and other security features

const std = @import("std");
const H3Event = @import("../core/event.zig").H3Event;

/// Security headers configuration
pub const SecurityHeaders = struct {
    /// X-Content-Type-Options
    content_type_options: bool = true,
    /// X-Frame-Options
    frame_options: FrameOptions = .deny,
    /// X-XSS-Protection
    xss_protection: bool = true,
    /// Referrer-Policy
    referrer_policy: ReferrerPolicy = .strict_origin_when_cross_origin,
    /// Content-Security-Policy
    content_security_policy: ?[]const u8 = "default-src 'self'",
    /// Strict-Transport-Security
    hsts: ?HSTSOptions = null,
    /// Permissions-Policy
    permissions_policy: ?[]const u8 = null,
};

/// X-Frame-Options values
pub const FrameOptions = enum {
    deny,
    sameorigin,
    allow_from,

    pub fn toString(self: FrameOptions) []const u8 {
        return switch (self) {
            .deny => "DENY",
            .sameorigin => "SAMEORIGIN",
            .allow_from => "ALLOW-FROM",
        };
    }
};

/// Referrer-Policy values
pub const ReferrerPolicy = enum {
    no_referrer,
    no_referrer_when_downgrade,
    origin,
    origin_when_cross_origin,
    same_origin,
    strict_origin,
    strict_origin_when_cross_origin,
    unsafe_url,

    pub fn toString(self: ReferrerPolicy) []const u8 {
        return switch (self) {
            .no_referrer => "no-referrer",
            .no_referrer_when_downgrade => "no-referrer-when-downgrade",
            .origin => "origin",
            .origin_when_cross_origin => "origin-when-cross-origin",
            .same_origin => "same-origin",
            .strict_origin => "strict-origin",
            .strict_origin_when_cross_origin => "strict-origin-when-cross-origin",
            .unsafe_url => "unsafe-url",
        };
    }
};

/// HSTS (HTTP Strict Transport Security) options
pub const HSTSOptions = struct {
    max_age: u32 = 31536000, // 1 year
    include_subdomains: bool = false,
    preload: bool = false,

    pub fn toString(self: HSTSOptions, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        try result.writer().print("max-age={d}", .{self.max_age});

        if (self.include_subdomains) {
            try result.writer().writeAll("; includeSubDomains");
        }

        if (self.preload) {
            try result.writer().writeAll("; preload");
        }

        return result.toOwnedSlice();
    }
};

/// CSRF protection utilities
pub const CSRF = struct {
    /// Generate a CSRF token
    pub fn generateToken(allocator: std.mem.Allocator) ![]u8 {
        var random_bytes: [32]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);

        const token = try allocator.alloc(u8, 64);
        _ = std.fmt.bufPrint(token, "{}", .{std.fmt.fmtSliceHexLower(&random_bytes)}) catch unreachable;

        return token;
    }

    /// Validate CSRF token
    pub fn validateToken(provided_token: []const u8, expected_token: []const u8) bool {
        if (provided_token.len != expected_token.len) return false;
        return std.crypto.utils.timingSafeEql([*]const u8, provided_token.ptr, expected_token.ptr, provided_token.len);
    }

    /// Get CSRF token from request (header or form data)
    pub fn getTokenFromRequest(event: *H3Event) ?[]const u8 {
        // Try X-CSRF-Token header first
        if (event.getHeader("x-csrf-token")) |token| {
            return token;
        }

        // Try _csrf form field (would need form parsing)
        // This is a simplified implementation
        return null;
    }

    /// Set CSRF token in response cookie
    pub fn setTokenCookie(event: *H3Event, token: []const u8) !void {
        const cookie_value = try std.fmt.allocPrint(event.allocator, "_csrf={s}; Path=/; HttpOnly; SameSite=Strict", .{token});
        defer event.allocator.free(cookie_value);
        try event.setHeader("Set-Cookie", cookie_value);
    }
};

/// Rate limiting utilities
pub const RateLimit = struct {
    /// Simple in-memory rate limiter
    pub const MemoryRateLimiter = struct {
        requests: std.HashMap([]const u8, RequestInfo, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
        max_requests: u32,
        window_seconds: i64,
        allocator: std.mem.Allocator,

        const RequestInfo = struct {
            count: u32,
            reset_time: i64,
        };

        pub fn init(allocator: std.mem.Allocator, max_requests: u32, window_seconds: i64) MemoryRateLimiter {
            return MemoryRateLimiter{
                .requests = std.HashMap([]const u8, RequestInfo, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
                .max_requests = max_requests,
                .window_seconds = window_seconds,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *MemoryRateLimiter) void {
            self.requests.deinit();
        }

        /// Check if request is allowed
        pub fn isAllowed(self: *MemoryRateLimiter, client_id: []const u8) !bool {
            const now = std.time.timestamp();

            var entry = try self.requests.getOrPut(client_id);
            if (!entry.found_existing) {
                entry.value_ptr.* = RequestInfo{
                    .count = 1,
                    .reset_time = now + self.window_seconds,
                };
                return true;
            }

            if (now > entry.value_ptr.reset_time) {
                // Reset window
                entry.value_ptr.count = 1;
                entry.value_ptr.reset_time = now + self.window_seconds;
                return true;
            }

            if (entry.value_ptr.count >= self.max_requests) {
                return false;
            }

            entry.value_ptr.count += 1;
            return true;
        }

        /// Get remaining requests for client
        pub fn getRemainingRequests(self: *MemoryRateLimiter, client_id: []const u8) u32 {
            const entry = self.requests.get(client_id) orelse return self.max_requests;
            const now = std.time.timestamp();

            if (now > entry.reset_time) {
                return self.max_requests;
            }

            return if (entry.count >= self.max_requests) 0 else self.max_requests - entry.count;
        }
    };
};

/// Input validation utilities
pub const Validation = struct {
    /// Validate email format (basic)
    pub fn isValidEmail(email: []const u8) bool {
        if (email.len == 0) return false;

        const at_pos = std.mem.indexOf(u8, email, "@") orelse return false;
        if (at_pos == 0 or at_pos == email.len - 1) return false;

        const dot_pos = std.mem.lastIndexOf(u8, email[at_pos..], ".") orelse return false;
        if (dot_pos == 0 or dot_pos == email.len - at_pos - 1) return false;

        return true;
    }

    /// Validate URL format (basic)
    pub fn isValidUrl(url: []const u8) bool {
        return std.mem.startsWith(u8, url, "http://") or std.mem.startsWith(u8, url, "https://");
    }

    /// Sanitize HTML input (basic)
    pub fn sanitizeHtml(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        for (input) |char| {
            switch (char) {
                '<' => try result.appendSlice("&lt;"),
                '>' => try result.appendSlice("&gt;"),
                '&' => try result.appendSlice("&amp;"),
                '"' => try result.appendSlice("&quot;"),
                '\'' => try result.appendSlice("&#x27;"),
                else => try result.append(char),
            }
        }

        return result.toOwnedSlice();
    }

    /// Check for SQL injection patterns (basic)
    pub fn hasSqlInjectionPattern(input: []const u8) bool {
        const dangerous_patterns = [_][]const u8{
            "union", "select", "insert", "update", "delete", "drop", "create",  "alter",
            "--",    "/*",     "*/",     "xp_",    "sp_",    "exec", "execute",
        };

        const lower_input = std.ascii.allocLowerString(std.heap.page_allocator, input) catch return true;
        defer std.heap.page_allocator.free(lower_input);

        for (dangerous_patterns) |pattern| {
            if (std.mem.indexOf(u8, lower_input, pattern) != null) {
                return true;
            }
        }

        return false;
    }
};

/// Security utility functions
pub const SecurityUtils = struct {
    /// Apply security headers to response
    pub fn applySecurityHeaders(event: *H3Event, config: SecurityHeaders) !void {
        if (config.content_type_options) {
            try event.setHeader("X-Content-Type-Options", "nosniff");
        }

        try event.setHeader("X-Frame-Options", config.frame_options.toString());

        if (config.xss_protection) {
            try event.setHeader("X-XSS-Protection", "1; mode=block");
        }

        try event.setHeader("Referrer-Policy", config.referrer_policy.toString());

        if (config.content_security_policy) |csp| {
            try event.setHeader("Content-Security-Policy", csp);
        }

        if (config.hsts) |hsts| {
            const hsts_value = try hsts.toString(event.allocator);
            defer event.allocator.free(hsts_value);
            try event.setHeader("Strict-Transport-Security", hsts_value);
        }

        if (config.permissions_policy) |pp| {
            try event.setHeader("Permissions-Policy", pp);
        }
    }

    /// Get client IP address (considering proxies)
    pub fn getClientIp(event: *H3Event) []const u8 {
        // Try X-Forwarded-For header first
        if (event.getHeader("x-forwarded-for")) |xff| {
            if (std.mem.indexOf(u8, xff, ",")) |comma| {
                return std.mem.trim(u8, xff[0..comma], " ");
            }
            return xff;
        }

        // Try X-Real-IP header
        if (event.getHeader("x-real-ip")) |real_ip| {
            return real_ip;
        }

        // Fallback to connection IP (would need to be passed from server)
        return "unknown";
    }

    /// Generate secure random string
    pub fn generateSecureRandomString(allocator: std.mem.Allocator, length: usize) ![]u8 {
        const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        const result = try allocator.alloc(u8, length);

        for (result) |*char| {
            const random_index = std.crypto.random.intRangeLessThan(usize, 0, charset.len);
            char.* = charset[random_index];
        }

        return result;
    }

    /// Hash password using a simple hash (in production, use proper password hashing)
    pub fn hashPassword(allocator: std.mem.Allocator, password: []const u8, salt: []const u8) ![]u8 {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(salt);
        hasher.update(password);

        var hash: [32]u8 = undefined;
        hasher.final(&hash);

        const result = try allocator.alloc(u8, 64);
        _ = std.fmt.bufPrint(result, "{}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;

        return result;
    }
};

// Tests
test "CSRF token generation and validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const token1 = try CSRF.generateToken(allocator);
    defer allocator.free(token1);

    const token2 = try CSRF.generateToken(allocator);
    defer allocator.free(token2);

    // Tokens should be different
    try testing.expect(!std.mem.eql(u8, token1, token2));

    // Token should validate against itself
    try testing.expect(CSRF.validateToken(token1, token1));

    // Token should not validate against different token
    try testing.expect(!CSRF.validateToken(token1, token2));
}

test "Email validation" {
    const testing = std.testing;

    try testing.expect(Validation.isValidEmail("test@example.com"));
    try testing.expect(Validation.isValidEmail("user.name@domain.co.uk"));
    try testing.expect(!Validation.isValidEmail("invalid-email"));
    try testing.expect(!Validation.isValidEmail("@example.com"));
    try testing.expect(!Validation.isValidEmail("test@"));
    try testing.expect(!Validation.isValidEmail(""));
}

test "HTML sanitization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "<script>alert('xss')</script>";
    const sanitized = try Validation.sanitizeHtml(allocator, input);
    defer allocator.free(sanitized);

    try testing.expectEqualStrings("&lt;script&gt;alert(&#x27;xss&#x27;)&lt;/script&gt;", sanitized);
}
