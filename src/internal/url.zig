//! URL parsing and manipulation utilities for H3 framework
//! Provides comprehensive URL parsing, query string handling, and path manipulation

const std = @import("std");

/// URL parsing errors
pub const UrlError = error{
    InvalidUrl,
    InvalidScheme,
    InvalidHost,
    InvalidPort,
    InvalidPath,
    InvalidQuery,
    InvalidFragment,
};

/// Parsed URL structure
pub const Url = struct {
    scheme: ?[]const u8 = null,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    host: ?[]const u8 = null,
    port: ?u16 = null,
    path: []const u8 = "/",
    query: ?[]const u8 = null,
    fragment: ?[]const u8 = null,
    raw: []const u8,

    /// Parse URL from string
    pub fn parse(_: std.mem.Allocator, url_string: []const u8) !Url {
        var url = Url{
            .raw = url_string,
        };

        var remaining = url_string;

        // Parse scheme
        if (std.mem.indexOf(u8, remaining, "://")) |scheme_end| {
            url.scheme = remaining[0..scheme_end];
            remaining = remaining[scheme_end + 3 ..];
        }

        // Parse fragment first (appears at the end)
        if (std.mem.lastIndexOf(u8, remaining, "#")) |fragment_start| {
            url.fragment = remaining[fragment_start + 1 ..];
            remaining = remaining[0..fragment_start];
        }

        // Parse query
        if (std.mem.lastIndexOf(u8, remaining, "?")) |query_start| {
            url.query = remaining[query_start + 1 ..];
            remaining = remaining[0..query_start];
        }

        // Parse path (everything after first '/')
        if (std.mem.indexOf(u8, remaining, "/")) |path_start| {
            url.path = remaining[path_start..];
            remaining = remaining[0..path_start];
        }

        // Parse authority (user:pass@host:port)
        if (remaining.len > 0) {
            try url.parseAuthority(remaining);
        }

        return url;
    }

    /// Parse authority part (user:pass@host:port)
    fn parseAuthority(self: *Url, authority: []const u8) !void {
        var remaining = authority;

        // Parse userinfo (user:pass@)
        if (std.mem.indexOf(u8, remaining, "@")) |at_pos| {
            const userinfo = remaining[0..at_pos];
            remaining = remaining[at_pos + 1 ..];

            if (std.mem.indexOf(u8, userinfo, ":")) |colon_pos| {
                self.username = userinfo[0..colon_pos];
                self.password = userinfo[colon_pos + 1 ..];
            } else {
                self.username = userinfo;
            }
        }

        // Parse host and port
        if (remaining.len > 0) {
            if (remaining[0] == '[') {
                // IPv6 address
                const close_bracket = std.mem.indexOf(u8, remaining, "]") orelse return UrlError.InvalidHost;
                self.host = remaining[0 .. close_bracket + 1];
                remaining = remaining[close_bracket + 1 ..];

                if (remaining.len > 0 and remaining[0] == ':') {
                    const port_str = remaining[1..];
                    self.port = std.fmt.parseInt(u16, port_str, 10) catch return UrlError.InvalidPort;
                }
            } else {
                // IPv4 or hostname
                if (std.mem.lastIndexOf(u8, remaining, ":")) |colon_pos| {
                    self.host = remaining[0..colon_pos];
                    const port_str = remaining[colon_pos + 1 ..];
                    self.port = std.fmt.parseInt(u16, port_str, 10) catch return UrlError.InvalidPort;
                } else {
                    self.host = remaining;
                }
            }
        }
    }

    /// Get default port for scheme
    pub fn getDefaultPort(self: Url) ?u16 {
        if (self.scheme) |scheme| {
            if (std.mem.eql(u8, scheme, "http")) return 80;
            if (std.mem.eql(u8, scheme, "https")) return 443;
            if (std.mem.eql(u8, scheme, "ftp")) return 21;
            if (std.mem.eql(u8, scheme, "ssh")) return 22;
        }
        return null;
    }

    /// Get effective port (explicit or default)
    pub fn getPort(self: Url) ?u16 {
        return self.port orelse self.getDefaultPort();
    }

    /// Check if URL is absolute
    pub fn isAbsolute(self: Url) bool {
        return self.scheme != null;
    }

    /// Check if URL is secure (HTTPS)
    pub fn isSecure(self: Url) bool {
        if (self.scheme) |scheme| {
            return std.mem.eql(u8, scheme, "https");
        }
        return false;
    }

    /// Reconstruct URL string
    pub fn toString(self: Url, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        if (self.scheme) |scheme| {
            try result.writer().print("{s}://", .{scheme});
        }

        if (self.username) |username| {
            try result.writer().print("{s}", .{username});
            if (self.password) |password| {
                try result.writer().print(":{s}", .{password});
            }
            try result.writer().writeAll("@");
        }

        if (self.host) |host| {
            try result.writer().print("{s}", .{host});
        }

        if (self.port) |port| {
            if (self.getDefaultPort() != port) {
                try result.writer().print(":{d}", .{port});
            }
        }

        try result.writer().print("{s}", .{self.path});

        if (self.query) |query| {
            try result.writer().print("?{s}", .{query});
        }

        if (self.fragment) |fragment| {
            try result.writer().print("#{s}", .{fragment});
        }

        return result.toOwnedSlice();
    }
};

/// Query string parser
pub const QueryParser = struct {
    /// Parse query string into key-value map
    pub fn parse(allocator: std.mem.Allocator, query_string: []const u8) !std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) {
        var result = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);

        if (query_string.len == 0) return result;

        var pairs = std.mem.splitScalar(u8, query_string, '&');
        while (pairs.next()) |pair| {
            if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
                const key = try urlDecode(allocator, pair[0..eq_pos]);
                const value = try urlDecode(allocator, pair[eq_pos + 1 ..]);
                try result.put(key, value);
            } else {
                const key = try urlDecode(allocator, pair);
                try result.put(key, "");
            }
        }

        return result;
    }

    /// Build query string from key-value map
    pub fn build(allocator: std.mem.Allocator, params: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage)) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var iterator = params.iterator();
        var first = true;
        while (iterator.next()) |entry| {
            if (!first) {
                try result.append('&');
            }
            first = false;

            const encoded_key = try urlEncode(allocator, entry.key_ptr.*);
            defer allocator.free(encoded_key);
            const encoded_value = try urlEncode(allocator, entry.value_ptr.*);
            defer allocator.free(encoded_value);

            try result.writer().print("{s}={s}", .{ encoded_key, encoded_value });
        }

        return result.toOwnedSlice();
    }
};

/// Path manipulation utilities
pub const PathUtils = struct {
    /// Join path segments
    pub fn join(allocator: std.mem.Allocator, segments: []const []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        for (segments, 0..) |segment, i| {
            if (i > 0 and !std.mem.endsWith(u8, result.items, "/") and !std.mem.startsWith(u8, segment, "/")) {
                try result.append('/');
            }
            try result.appendSlice(segment);
        }

        return result.toOwnedSlice();
    }

    /// Normalize path (resolve . and ..)
    pub fn normalize(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        var segments = std.ArrayList([]const u8).init(allocator);
        defer segments.deinit();

        var parts = std.mem.splitScalar(u8, path, '/');
        while (parts.next()) |part| {
            if (std.mem.eql(u8, part, ".") or part.len == 0) {
                continue;
            } else if (std.mem.eql(u8, part, "..")) {
                if (segments.items.len > 0) {
                    _ = segments.pop();
                }
            } else {
                try segments.append(part);
            }
        }

        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        if (std.mem.startsWith(u8, path, "/")) {
            try result.append('/');
        }

        for (segments.items, 0..) |segment, i| {
            if (i > 0) {
                try result.append('/');
            }
            try result.appendSlice(segment);
        }

        if (result.items.len == 0) {
            try result.append('/');
        }

        return result.toOwnedSlice();
    }

    /// Get file extension from path
    pub fn getExtension(path: []const u8) ?[]const u8 {
        const basename = std.fs.path.basename(path);
        const dot_pos = std.mem.lastIndexOf(u8, basename, ".") orelse return null;
        return basename[dot_pos + 1 ..];
    }

    /// Get directory from path
    pub fn getDirectory(path: []const u8) []const u8 {
        return std.fs.path.dirname(path) orelse "/";
    }

    /// Get filename from path
    pub fn getFilename(path: []const u8) []const u8 {
        return std.fs.path.basename(path);
    }
};

/// URL encoding/decoding utilities
pub const UrlEncoding = struct {
    /// URL encode a string
    pub fn encode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        return urlEncode(allocator, input);
    }

    /// URL decode a string
    pub fn decode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        return urlDecode(allocator, input);
    }
};

// Public API functions
/// URL encode a string
pub fn encode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return urlEncode(allocator, input);
}

/// URL decode a string
pub fn decode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return urlDecode(allocator, input);
}

// Helper functions

/// URL encode a string
fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (input) |char| {
        switch (char) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~' => {
                try result.append(char);
            },
            ' ' => {
                try result.append('+');
            },
            else => {
                try result.writer().print("%{X:0>2}", .{char});
            },
        }
    }

    return result.toOwnedSlice();
}

/// URL decode a string
fn urlDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hex = input[i + 1 .. i + 3];
            const byte = std.fmt.parseInt(u8, hex, 16) catch {
                try result.append(input[i]);
                i += 1;
                continue;
            };
            try result.append(byte);
            i += 3;
        } else if (input[i] == '+') {
            try result.append(' ');
            i += 1;
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

// Tests
test "URL parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const url = try Url.parse(allocator, "https://user:pass@example.com:8080/path/to/resource?query=value&foo=bar#section");

    try testing.expectEqualStrings("https", url.scheme.?);
    try testing.expectEqualStrings("user", url.username.?);
    try testing.expectEqualStrings("pass", url.password.?);
    try testing.expectEqualStrings("example.com", url.host.?);
    try testing.expect(url.port.? == 8080);
    try testing.expectEqualStrings("/path/to/resource", url.path);
    try testing.expectEqualStrings("query=value&foo=bar", url.query.?);
    try testing.expectEqualStrings("section", url.fragment.?);
}

test "Query string parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var params = try QueryParser.parse(allocator, "name=John%20Doe&age=30&city=New+York");
    defer params.deinit();

    try testing.expectEqualStrings("John Doe", params.get("name").?);
    try testing.expectEqualStrings("30", params.get("age").?);
    try testing.expectEqualStrings("New York", params.get("city").?);
}

test "Path normalization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const normalized = try PathUtils.normalize(allocator, "/path/to/../resource/./file.txt");
    defer allocator.free(normalized);

    try testing.expectEqualStrings("/path/resource/file.txt", normalized);
}

test "URL encoding/decoding" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const original = "Hello World! @#$%";
    const encoded = try urlEncode(allocator, original);
    defer allocator.free(encoded);

    const decoded = try urlDecode(allocator, encoded);
    defer allocator.free(decoded);

    try testing.expectEqualStrings(original, decoded);
}
