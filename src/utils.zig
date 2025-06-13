//! Utility functions for H3 framework
//! This module provides organized utility functions for HTTP operations

const std = @import("std");

// Export utility modules
pub const request = @import("utils/request.zig");
pub const response = @import("utils/response.zig");
pub const middleware = @import("utils/middleware.zig");

// Additional utility functions

/// URL decode a string (simplified implementation)
pub fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            // Parse hex digits
            const hex_str = encoded[i + 1 .. i + 3];
            if (std.fmt.parseInt(u8, hex_str, 16)) |byte| {
                try result.append(byte);
                i += 3;
            } else |_| {
                try result.append(encoded[i]);
                i += 1;
            }
        } else if (encoded[i] == '+') {
            try result.append(' ');
            i += 1;
        } else {
            try result.append(encoded[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

/// URL encode a string (simplified implementation)
pub fn urlEncode(allocator: std.mem.Allocator, decoded: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (decoded) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~') {
            try result.append(byte);
        } else {
            try result.writer().print("%{X:0>2}", .{byte});
        }
    }

    return result.toOwnedSlice();
}

/// Parse form data from request body
pub fn parseFormData(allocator: std.mem.Allocator, body: []const u8) !std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) {
    var result = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);

    var iter = std.mem.splitSequence(u8, body, "&");
    while (iter.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
            const key = try urlDecode(allocator, pair[0..eq_pos]);
            const value = try urlDecode(allocator, pair[eq_pos + 1 ..]);
            try result.put(key, value);
        }
    }

    return result;
}

// Tests for the utility functions
test "utils.urlDecode" {
    const allocator = std.testing.allocator;

    const decoded = try urlDecode(allocator, "Hello%20World%21");
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings("Hello World!", decoded);
}

test "utils.urlEncode" {
    const allocator = std.testing.allocator;

    const encoded = try urlEncode(allocator, "Hello World!");
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings("Hello%20World%21", encoded);
}
