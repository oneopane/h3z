//! Cookie handling utilities for H3 framework
//! Provides comprehensive cookie parsing, creation, and management

const std = @import("std");
const H3Event = @import("../core/event.zig").H3Event;
const body_utils = @import("body.zig");

/// Cookie attributes
pub const CookieOptions = struct {
    /// Maximum age in seconds
    max_age: ?i32 = null,
    /// Expiration date
    expires: ?[]const u8 = null,
    /// Path scope
    path: ?[]const u8 = null,
    /// Domain scope
    domain: ?[]const u8 = null,
    /// Secure flag (HTTPS only)
    secure: bool = false,
    /// HttpOnly flag (no JavaScript access)
    http_only: bool = false,
    /// SameSite attribute
    same_site: ?SameSite = null,
};

/// SameSite cookie attribute values
pub const SameSite = enum {
    strict,
    lax,
    none,

    pub fn toString(self: SameSite) []const u8 {
        return switch (self) {
            .strict => "Strict",
            .lax => "Lax",
            .none => "None",
        };
    }
};

/// Parsed cookie structure
pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    options: CookieOptions = .{},

    pub fn init(name: []const u8, value: []const u8) Cookie {
        return Cookie{
            .name = name,
            .value = value,
        };
    }

    pub fn initWithOptions(name: []const u8, value: []const u8, options: CookieOptions) Cookie {
        return Cookie{
            .name = name,
            .value = value,
            .options = options,
        };
    }

    /// Serialize cookie to Set-Cookie header value
    pub fn serialize(self: Cookie, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        // Basic name=value
        try result.writer().print("{s}={s}", .{ self.name, self.value });

        // Add attributes
        if (self.options.max_age) |max_age| {
            try result.writer().print("; Max-Age={d}", .{max_age});
        }

        if (self.options.expires) |expires| {
            try result.writer().print("; Expires={s}", .{expires});
        }

        if (self.options.path) |path| {
            try result.writer().print("; Path={s}", .{path});
        }

        if (self.options.domain) |domain| {
            try result.writer().print("; Domain={s}", .{domain});
        }

        if (self.options.secure) {
            try result.writer().writeAll("; Secure");
        }

        if (self.options.http_only) {
            try result.writer().writeAll("; HttpOnly");
        }

        if (self.options.same_site) |same_site| {
            try result.writer().print("; SameSite={s}", .{same_site.toString()});
        }

        return result.toOwnedSlice();
    }
};

/// Cookie jar for managing multiple cookies
pub const CookieJar = struct {
    cookies: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CookieJar {
        return CookieJar{
            .cookies = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CookieJar) void {
        self.cookies.deinit();
    }

    /// Add a cookie to the jar
    pub fn set(self: *CookieJar, name: []const u8, value: []const u8) !void {
        try self.cookies.put(name, value);
    }

    /// Get a cookie value by name
    pub fn get(self: *CookieJar, name: []const u8) ?[]const u8 {
        return self.cookies.get(name);
    }

    /// Remove a cookie from the jar
    pub fn remove(self: *CookieJar, name: []const u8) bool {
        return self.cookies.remove(name);
    }

    /// Check if a cookie exists
    pub fn has(self: *CookieJar, name: []const u8) bool {
        return self.cookies.contains(name);
    }

    /// Get all cookie names
    pub fn getNames(self: *CookieJar, allocator: std.mem.Allocator) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        var iterator = self.cookies.iterator();
        while (iterator.next()) |entry| {
            try names.append(entry.key_ptr.*);
        }
        return names.toOwnedSlice();
    }

    /// Clear all cookies
    pub fn clear(self: *CookieJar) void {
        self.cookies.clearRetainingCapacity();
    }
};

/// Cookie utility functions
pub const CookieUtils = struct {
    /// Parse cookies from Cookie header
    pub fn parseCookieHeader(allocator: std.mem.Allocator, cookie_header: []const u8) !CookieJar {
        var jar = CookieJar.init(allocator);

        var pairs = std.mem.splitScalar(u8, cookie_header, ';');
        while (pairs.next()) |pair| {
            const trimmed = std.mem.trim(u8, pair, " \t");
            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const name = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");
                try jar.set(name, value);
            }
        }

        return jar;
    }

    /// Set a cookie in the response
    pub fn setCookie(event: *H3Event, cookie: Cookie) !void {
        const cookie_value = try cookie.serialize(event.allocator);
        defer event.allocator.free(cookie_value);
        try event.setHeader("Set-Cookie", cookie_value);
    }

    /// Set a simple cookie with name and value
    pub fn setSimpleCookie(event: *H3Event, name: []const u8, value: []const u8) !void {
        const cookie = Cookie.init(name, value);
        try setCookie(event, cookie);
    }

    /// Set a cookie with options
    pub fn setCookieWithOptions(event: *H3Event, name: []const u8, value: []const u8, options: CookieOptions) !void {
        const cookie = Cookie.initWithOptions(name, value, options);
        try setCookie(event, cookie);
    }

    /// Clear a cookie by setting it to expire
    pub fn clearCookie(event: *H3Event, name: []const u8, path: ?[]const u8) !void {
        const options = CookieOptions{
            .max_age = 0,
            .path = path,
            .expires = "Thu, 01 Jan 1970 00:00:00 GMT",
        };
        try setCookieWithOptions(event, name, "", options);
    }

    /// Get a cookie value from the request
    pub fn getCookie(event: *H3Event, name: []const u8) ?[]const u8 {
        const cookie_header = event.getHeader("cookie") orelse return null;

        var pairs = std.mem.split(u8, cookie_header, ";");
        while (pairs.next()) |pair| {
            const trimmed = std.mem.trim(u8, pair, " \t");
            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const cookie_name = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                if (std.mem.eql(u8, cookie_name, name)) {
                    return std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");
                }
            }
        }
        return null;
    }

    /// Get all cookies from the request
    pub fn getAllCookies(event: *H3Event) !CookieJar {
        const cookie_header = event.getHeader("cookie") orelse {
            return CookieJar.init(event.allocator);
        };
        return parseCookieHeader(event.allocator, cookie_header);
    }

    /// Create a secure session cookie
    pub fn createSessionCookie(name: []const u8, value: []const u8, secure: bool) Cookie {
        return Cookie.initWithOptions(name, value, .{
            .http_only = true,
            .secure = secure,
            .same_site = .lax,
            .path = "/",
        });
    }

    /// Create a persistent cookie with expiration
    pub fn createPersistentCookie(name: []const u8, value: []const u8, max_age_seconds: i32) Cookie {
        return Cookie.initWithOptions(name, value, .{
            .max_age = max_age_seconds,
            .http_only = true,
            .secure = true,
            .same_site = .lax,
            .path = "/",
        });
    }

    /// URL encode a cookie value
    pub fn urlEncode(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        for (value) |char| {
            switch (char) {
                'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~' => {
                    try result.append(char);
                },
                else => {
                    try result.writer().print("%{X:0>2}", .{char});
                },
            }
        }

        return result.toOwnedSlice();
    }

    /// URL decode a string
    pub fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
        return body_utils.urlDecode(allocator, encoded);
    }
};

// Tests
test "Cookie serialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cookie = Cookie.initWithOptions("session", "abc123", .{
        .max_age = 3600,
        .path = "/",
        .secure = true,
        .http_only = true,
        .same_site = .lax,
    });

    const serialized = try cookie.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "session=abc123") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Max-Age=3600") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Path=/") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Secure") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "HttpOnly") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "SameSite=Lax") != null);
}

test "Cookie parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cookie_header = "session=abc123; user=john; theme=dark";
    var jar = try CookieUtils.parseCookieHeader(allocator, cookie_header);
    defer jar.deinit();

    try testing.expectEqualStrings("abc123", jar.get("session").?);
    try testing.expectEqualStrings("john", jar.get("user").?);
    try testing.expectEqualStrings("dark", jar.get("theme").?);
    try testing.expect(jar.get("nonexistent") == null);
}
