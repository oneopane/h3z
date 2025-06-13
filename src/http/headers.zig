//! HTTP headers handling with case-insensitive keys

const std = @import("std");

/// Case-insensitive string context for header names
const HeaderContext = struct {
    pub fn hash(self: @This(), s: []const u8) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        for (s) |c| {
            hasher.update(&[_]u8{std.ascii.toLower(c)});
        }
        return hasher.final();
    }

    pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
        _ = self;
        if (a.len != b.len) return false;
        for (a, b) |a_char, b_char| {
            if (std.ascii.toLower(a_char) != std.ascii.toLower(b_char)) {
                return false;
            }
        }
        return true;
    }
};

/// HTTP headers map with case-insensitive keys
pub const Headers = std.HashMap([]const u8, []const u8, HeaderContext, std.hash_map.default_max_load_percentage);

/// Common HTTP header names as constants
pub const HeaderNames = struct {
    pub const ACCEPT = "Accept";
    pub const ACCEPT_ENCODING = "Accept-Encoding";
    pub const ACCEPT_LANGUAGE = "Accept-Language";
    pub const AUTHORIZATION = "Authorization";
    pub const CACHE_CONTROL = "Cache-Control";
    pub const CONNECTION = "Connection";
    pub const CONTENT_ENCODING = "Content-Encoding";
    pub const CONTENT_LENGTH = "Content-Length";
    pub const CONTENT_TYPE = "Content-Type";
    pub const COOKIE = "Cookie";
    pub const DATE = "Date";
    pub const ETAG = "ETag";
    pub const EXPIRES = "Expires";
    pub const HOST = "Host";
    pub const IF_MODIFIED_SINCE = "If-Modified-Since";
    pub const IF_NONE_MATCH = "If-None-Match";
    pub const LAST_MODIFIED = "Last-Modified";
    pub const LOCATION = "Location";
    pub const ORIGIN = "Origin";
    pub const REFERER = "Referer";
    pub const SERVER = "Server";
    pub const SET_COOKIE = "Set-Cookie";
    pub const TRANSFER_ENCODING = "Transfer-Encoding";
    pub const UPGRADE = "Upgrade";
    pub const USER_AGENT = "User-Agent";
    pub const VARY = "Vary";
    pub const WWW_AUTHENTICATE = "WWW-Authenticate";

    // CORS headers
    pub const ACCESS_CONTROL_ALLOW_ORIGIN = "Access-Control-Allow-Origin";
    pub const ACCESS_CONTROL_ALLOW_METHODS = "Access-Control-Allow-Methods";
    pub const ACCESS_CONTROL_ALLOW_HEADERS = "Access-Control-Allow-Headers";
    pub const ACCESS_CONTROL_ALLOW_CREDENTIALS = "Access-Control-Allow-Credentials";
    pub const ACCESS_CONTROL_EXPOSE_HEADERS = "Access-Control-Expose-Headers";
    pub const ACCESS_CONTROL_MAX_AGE = "Access-Control-Max-Age";
    pub const ACCESS_CONTROL_REQUEST_METHOD = "Access-Control-Request-Method";
    pub const ACCESS_CONTROL_REQUEST_HEADERS = "Access-Control-Request-Headers";

    // Security headers
    pub const STRICT_TRANSPORT_SECURITY = "Strict-Transport-Security";
    pub const X_CONTENT_TYPE_OPTIONS = "X-Content-Type-Options";
    pub const X_FRAME_OPTIONS = "X-Frame-Options";
    pub const X_XSS_PROTECTION = "X-XSS-Protection";
    pub const CONTENT_SECURITY_POLICY = "Content-Security-Policy";

    // Proxy headers
    pub const X_FORWARDED_FOR = "X-Forwarded-For";
    pub const X_FORWARDED_HOST = "X-Forwarded-Host";
    pub const X_FORWARDED_PROTO = "X-Forwarded-Proto";
    pub const X_FORWARDED_SSL = "X-Forwarded-SSL";
    pub const X_REAL_IP = "X-Real-IP";
};

/// Common MIME types
pub const MimeTypes = struct {
    pub const TEXT_PLAIN = "text/plain";
    pub const TEXT_HTML = "text/html";
    pub const TEXT_CSS = "text/css";
    pub const TEXT_JAVASCRIPT = "text/javascript";
    pub const APPLICATION_JSON = "application/json";
    pub const APPLICATION_XML = "application/xml";
    pub const APPLICATION_FORM_URLENCODED = "application/x-www-form-urlencoded";
    pub const MULTIPART_FORM_DATA = "multipart/form-data";
    pub const APPLICATION_OCTET_STREAM = "application/octet-stream";
    pub const IMAGE_PNG = "image/png";
    pub const IMAGE_JPEG = "image/jpeg";
    pub const IMAGE_GIF = "image/gif";
    pub const IMAGE_SVG = "image/svg+xml";
    pub const IMAGE_WEBP = "image/webp";
    pub const AUDIO_MPEG = "audio/mpeg";
    pub const VIDEO_MP4 = "video/mp4";
    pub const APPLICATION_PDF = "application/pdf";
    pub const APPLICATION_ZIP = "application/zip";
};

/// Helper functions for working with headers
pub const HeaderUtils = struct {
    /// Parse a header value that contains multiple comma-separated values
    pub fn parseCommaSeparated(allocator: std.mem.Allocator, value: []const u8) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(allocator);
        defer result.deinit();

        var iter = std.mem.splitSequence(u8, value, ",");
        while (iter.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len > 0) {
                try result.append(trimmed);
            }
        }

        return result.toOwnedSlice();
    }

    /// Parse quality values from Accept-* headers
    pub fn parseQualityValues(allocator: std.mem.Allocator, value: []const u8) ![]struct { value: []const u8, quality: f32 } {
        var result = std.ArrayList(struct { value: []const u8, quality: f32 }).init(allocator);
        defer result.deinit();

        var iter = std.mem.splitSequence(u8, value, ",");
        while (iter.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len == 0) continue;

            var quality: f32 = 1.0;
            var media_type = trimmed;

            if (std.mem.indexOf(u8, trimmed, ";q=")) |q_pos| {
                media_type = std.mem.trim(u8, trimmed[0..q_pos], " \t");
                const q_str = trimmed[q_pos + 3 ..];
                quality = std.fmt.parseFloat(f32, q_str) catch 1.0;
            }

            try result.append(.{ .value = media_type, .quality = quality });
        }

        return result.toOwnedSlice();
    }

    /// Check if a header value contains a specific token
    pub fn containsToken(header_value: []const u8, token: []const u8) bool {
        var iter = std.mem.splitSequence(u8, header_value, ",");
        while (iter.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (std.ascii.eqlIgnoreCase(trimmed, token)) {
                return true;
            }
        }
        return false;
    }
};

test "Headers case insensitive" {
    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();

    try headers.put("Content-Type", "application/json");

    try std.testing.expectEqualStrings("application/json", headers.get("content-type").?);
    try std.testing.expectEqualStrings("application/json", headers.get("CONTENT-TYPE").?);
    try std.testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
}

test "HeaderUtils.parseCommaSeparated" {
    const allocator = std.testing.allocator;

    const values = try HeaderUtils.parseCommaSeparated(allocator, "gzip, deflate, br");
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 3), values.len);
    try std.testing.expectEqualStrings("gzip", values[0]);
    try std.testing.expectEqualStrings("deflate", values[1]);
    try std.testing.expectEqualStrings("br", values[2]);
}

test "HeaderUtils.containsToken" {
    try std.testing.expect(HeaderUtils.containsToken("gzip, deflate, br", "gzip"));
    try std.testing.expect(HeaderUtils.containsToken("gzip, deflate, br", "DEFLATE"));
    try std.testing.expect(!HeaderUtils.containsToken("gzip, deflate, br", "brotli"));
}
