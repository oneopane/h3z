//! Request body parsing utilities for H3 framework
//! Provides parsing for JSON, form data, multipart, and other body formats

const std = @import("std");
const H3Event = @import("../core/event.zig").H3Event;

/// Body parsing errors
pub const BodyError = error{
    InvalidContentType,
    InvalidJson,
    InvalidFormData,
    InvalidMultipart,
    BodyTooLarge,
    NoBody,
    UnsupportedEncoding,
};

/// Content types for body parsing
pub const ContentType = enum {
    json,
    form_urlencoded,
    multipart_form,
    text_plain,
    octet_stream,
    unknown,

    pub fn fromString(content_type: []const u8) ContentType {
        if (std.mem.indexOf(u8, content_type, "application/json") != null) {
            return .json;
        } else if (std.mem.indexOf(u8, content_type, "application/x-www-form-urlencoded") != null) {
            return .form_urlencoded;
        } else if (std.mem.indexOf(u8, content_type, "multipart/form-data") != null) {
            return .multipart_form;
        } else if (std.mem.indexOf(u8, content_type, "text/plain") != null) {
            return .text_plain;
        } else if (std.mem.indexOf(u8, content_type, "application/octet-stream") != null) {
            return .octet_stream;
        } else {
            return .unknown;
        }
    }
};

/// Form field data
pub const FormField = struct {
    name: []const u8,
    value: []const u8,
    filename: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
};

/// Multipart form data
pub const MultipartData = struct {
    fields: std.ArrayList(FormField),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MultipartData {
        return MultipartData{
            .fields = std.ArrayList(FormField).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MultipartData) void {
        self.fields.deinit();
    }

    pub fn addField(self: *MultipartData, field: FormField) !void {
        try self.fields.append(field);
    }

    pub fn getField(self: *MultipartData, name: []const u8) ?FormField {
        for (self.fields.items) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return field;
            }
        }
        return null;
    }

    pub fn getFields(self: *MultipartData, name: []const u8, allocator: std.mem.Allocator) ![]FormField {
        var matching_fields = std.ArrayList(FormField).init(allocator);
        for (self.fields.items) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                try matching_fields.append(field);
            }
        }
        return matching_fields.toOwnedSlice();
    }
};

/// Body parser utilities
pub const BodyParser = struct {
    /// Parse JSON body
    pub fn parseJson(event: *H3Event, comptime T: type) !T {
        const body = event.request.body orelse return BodyError.NoBody;

        const content_type = event.getHeader("content-type") orelse return BodyError.InvalidContentType;
        if (ContentType.fromString(content_type) != .json) {
            return BodyError.InvalidContentType;
        }

        const parsed = std.json.parseFromSlice(T, event.allocator, body, .{}) catch {
            return BodyError.InvalidJson;
        };

        return parsed.value;
    }

    /// Parse form-urlencoded body
    pub fn parseFormUrlencoded(event: *H3Event) !std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) {
        const body = event.request.body orelse return BodyError.NoBody;

        const content_type = event.getHeader("content-type") orelse return BodyError.InvalidContentType;
        if (ContentType.fromString(content_type) != .form_urlencoded) {
            return BodyError.InvalidContentType;
        }

        var form_data = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(event.allocator);

        var pairs = std.mem.splitScalar(u8, body, '&');
        while (pairs.next()) |pair| {
            if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
                const key = try urlDecode(event.allocator, pair[0..eq_pos]);
                const value = try urlDecode(event.allocator, pair[eq_pos + 1 ..]);
                try form_data.put(key, value);
            }
        }

        return form_data;
    }

    /// Parse multipart form data
    pub fn parseMultipart(event: *H3Event) !MultipartData {
        const body = event.request.body orelse return BodyError.NoBody;

        const content_type = event.getHeader("content-type") orelse return BodyError.InvalidContentType;
        if (ContentType.fromString(content_type) != .multipart_form) {
            return BodyError.InvalidContentType;
        }

        // Extract boundary from content-type header
        const boundary = extractBoundary(content_type) orelse return BodyError.InvalidMultipart;

        var multipart_data = MultipartData.init(event.allocator);

        // Split body by boundary
        const boundary_marker = try std.fmt.allocPrint(event.allocator, "--{s}", .{boundary});
        defer event.allocator.free(boundary_marker);

        var parts = std.mem.splitSequence(u8, body, boundary_marker);
        _ = parts.next(); // Skip preamble

        while (parts.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, std.mem.trim(u8, part, "\r\n-"), "")) continue;

            const field = try parseMultipartField(event.allocator, part);
            try multipart_data.addField(field);
        }

        return multipart_data;
    }

    /// Get raw body as bytes
    pub fn getRawBody(event: *H3Event) ?[]const u8 {
        return event.request.body;
    }

    /// Get body as text
    pub fn getTextBody(event: *H3Event) ?[]const u8 {
        const body = event.request.body orelse return null;

        const content_type = event.getHeader("content-type") orelse return body;
        const ct = ContentType.fromString(content_type);

        return switch (ct) {
            .text_plain, .json => body,
            else => body,
        };
    }

    /// Check if body size is within limits
    pub fn checkBodySize(event: *H3Event, max_size: usize) !void {
        const content_length = event.request.getContentLength() orelse 0;
        if (content_length > max_size) {
            return BodyError.BodyTooLarge;
        }
    }

    /// Parse body based on content type
    pub fn parseBody(event: *H3Event, comptime T: type) !T {
        const content_type = event.getHeader("content-type") orelse return BodyError.InvalidContentType;
        const ct = ContentType.fromString(content_type);

        return switch (ct) {
            .json => parseJson(event, T),
            else => BodyError.UnsupportedEncoding,
        };
    }
};

/// Streaming body parser for large bodies
pub const StreamingBodyParser = struct {
    event: *H3Event,
    buffer: std.ArrayList(u8),
    max_size: usize,
    current_size: usize,

    pub fn init(event: *H3Event, allocator: std.mem.Allocator, max_size: usize) StreamingBodyParser {
        return StreamingBodyParser{
            .event = event,
            .buffer = std.ArrayList(u8).init(allocator),
            .max_size = max_size,
            .current_size = 0,
        };
    }

    pub fn deinit(self: *StreamingBodyParser) void {
        self.buffer.deinit();
    }

    /// Read chunk of body data
    pub fn readChunk(self: *StreamingBodyParser, chunk: []const u8) !void {
        if (self.current_size + chunk.len > self.max_size) {
            return BodyError.BodyTooLarge;
        }

        try self.buffer.appendSlice(chunk);
        self.current_size += chunk.len;
    }

    /// Get accumulated body data
    pub fn getBody(self: *StreamingBodyParser) []const u8 {
        return self.buffer.items;
    }

    /// Parse accumulated JSON data
    pub fn parseJson(self: *StreamingBodyParser, comptime T: type) !T {
        const body = self.getBody();
        const parsed = std.json.parseFromSlice(T, self.buffer.allocator, body, .{}) catch {
            return BodyError.InvalidJson;
        };
        return parsed.value;
    }
};

// Helper functions

/// Extract boundary from multipart content-type header
fn extractBoundary(content_type: []const u8) ?[]const u8 {
    const boundary_start = std.mem.indexOf(u8, content_type, "boundary=") orelse return null;
    const boundary_value = content_type[boundary_start + 9 ..];

    // Handle quoted boundary
    if (boundary_value.len > 0 and boundary_value[0] == '"') {
        const end_quote = std.mem.indexOf(u8, boundary_value[1..], "\"") orelse return null;
        return boundary_value[1 .. end_quote + 1];
    }

    // Handle unquoted boundary
    const semicolon = std.mem.indexOf(u8, boundary_value, ";");
    return if (semicolon) |pos| boundary_value[0..pos] else boundary_value;
}

/// Parse a single multipart field
fn parseMultipartField(_: std.mem.Allocator, part: []const u8) !FormField {
    // Split headers and body
    const header_end = std.mem.indexOf(u8, part, "\r\n\r\n") orelse return BodyError.InvalidMultipart;
    const headers = part[0..header_end];
    const body = part[header_end + 4 ..];

    // Parse Content-Disposition header
    var name: ?[]const u8 = null;
    var filename: ?[]const u8 = null;
    var content_type: ?[]const u8 = null;

    var header_lines = std.mem.splitSequence(u8, headers, "\r\n");
    while (header_lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "Content-Disposition:")) {
            name = extractDispositionValue(line, "name");
            filename = extractDispositionValue(line, "filename");
        } else if (std.mem.startsWith(u8, line, "Content-Type:")) {
            content_type = std.mem.trim(u8, line[13..], " ");
        }
    }

    return FormField{
        .name = name orelse return BodyError.InvalidMultipart,
        .value = std.mem.trim(u8, body, "\r\n"),
        .filename = filename,
        .content_type = content_type,
    };
}

/// Extract value from Content-Disposition header
fn extractDispositionValue(header: []const u8, param: []const u8) ?[]const u8 {
    const param_start = std.mem.indexOf(u8, header, param) orelse return null;
    const equals_pos = std.mem.indexOf(u8, header[param_start..], "=") orelse return null;
    const value_start = param_start + equals_pos + 1;

    if (value_start >= header.len) return null;

    var value_end = value_start;
    var in_quotes = false;

    if (header[value_start] == '"') {
        in_quotes = true;
        value_end = value_start + 1;
        while (value_end < header.len and header[value_end] != '"') {
            value_end += 1;
        }
        if (value_end < header.len) value_end += 1;
    } else {
        while (value_end < header.len and header[value_end] != ';' and header[value_end] != ' ') {
            value_end += 1;
        }
    }

    const value = header[value_start..value_end];
    return if (in_quotes and value.len >= 2) value[1 .. value.len - 1] else value;
}

/// URL decode a string
fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            const hex = encoded[i + 1 .. i + 3];
            const byte = std.fmt.parseInt(u8, hex, 16) catch {
                try result.append(encoded[i]);
                i += 1;
                continue;
            };
            try result.append(byte);
            i += 3;
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

// Tests
test "ContentType detection" {
    const testing = std.testing;

    try testing.expect(ContentType.fromString("application/json") == .json);
    try testing.expect(ContentType.fromString("application/json; charset=utf-8") == .json);
    try testing.expect(ContentType.fromString("application/x-www-form-urlencoded") == .form_urlencoded);
    try testing.expect(ContentType.fromString("multipart/form-data; boundary=123") == .multipart_form);
    try testing.expect(ContentType.fromString("text/plain") == .text_plain);
    try testing.expect(ContentType.fromString("unknown/type") == .unknown);
}

test "URL decoding" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const decoded = try urlDecode(allocator, "hello%20world%21");
    defer allocator.free(decoded);

    try testing.expectEqualStrings("hello world!", decoded);
}

test "Boundary extraction" {
    const testing = std.testing;

    const content_type1 = "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW";
    const boundary1 = extractBoundary(content_type1);
    try testing.expectEqualStrings("----WebKitFormBoundary7MA4YWxkTrZu0gW", boundary1.?);

    const content_type2 = "multipart/form-data; boundary=\"----WebKitFormBoundary7MA4YWxkTrZu0gW\"";
    const boundary2 = extractBoundary(content_type2);
    try testing.expectEqualStrings("----WebKitFormBoundary7MA4YWxkTrZu0gW", boundary2.?);
}
