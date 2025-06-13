//! MIME type utilities for H3 framework
//! Provides MIME type detection, content type handling, and media type utilities

const std = @import("std");

/// Common MIME types
pub const MimeType = enum {
    // Text types
    text_plain,
    text_html,
    text_css,
    text_javascript,
    text_xml,
    text_csv,
    text_markdown,

    // Application types
    application_json,
    application_xml,
    application_pdf,
    application_zip,
    application_gzip,
    application_tar,
    application_octet_stream,
    application_form_urlencoded,
    application_javascript,

    // Image types
    image_jpeg,
    image_png,
    image_gif,
    image_webp,
    image_svg,
    image_ico,
    image_bmp,
    image_tiff,

    // Audio types
    audio_mpeg,
    audio_wav,
    audio_ogg,
    audio_mp4,
    audio_webm,

    // Video types
    video_mp4,
    video_webm,
    video_ogg,
    video_avi,
    video_mov,

    // Multipart types
    multipart_form_data,
    multipart_mixed,

    // Font types
    font_woff,
    font_woff2,
    font_ttf,
    font_otf,

    // Unknown type
    unknown,

    /// Convert MIME type to string
    pub fn toString(self: MimeType) []const u8 {
        return switch (self) {
            .text_plain => "text/plain",
            .text_html => "text/html",
            .text_css => "text/css",
            .text_javascript => "text/javascript",
            .text_xml => "text/xml",
            .text_csv => "text/csv",
            .text_markdown => "text/markdown",

            .application_json => "application/json",
            .application_xml => "application/xml",
            .application_pdf => "application/pdf",
            .application_zip => "application/zip",
            .application_gzip => "application/gzip",
            .application_tar => "application/tar",
            .application_octet_stream => "application/octet-stream",
            .application_form_urlencoded => "application/x-www-form-urlencoded",
            .application_javascript => "application/javascript",

            .image_jpeg => "image/jpeg",
            .image_png => "image/png",
            .image_gif => "image/gif",
            .image_webp => "image/webp",
            .image_svg => "image/svg+xml",
            .image_ico => "image/x-icon",
            .image_bmp => "image/bmp",
            .image_tiff => "image/tiff",

            .audio_mpeg => "audio/mpeg",
            .audio_wav => "audio/wav",
            .audio_ogg => "audio/ogg",
            .audio_mp4 => "audio/mp4",
            .audio_webm => "audio/webm",

            .video_mp4 => "video/mp4",
            .video_webm => "video/webm",
            .video_ogg => "video/ogg",
            .video_avi => "video/x-msvideo",
            .video_mov => "video/quicktime",

            .multipart_form_data => "multipart/form-data",
            .multipart_mixed => "multipart/mixed",

            .font_woff => "font/woff",
            .font_woff2 => "font/woff2",
            .font_ttf => "font/ttf",
            .font_otf => "font/otf",

            .unknown => "application/octet-stream",
        };
    }

    /// Parse MIME type from string
    pub fn fromString(mime_string: []const u8) MimeType {
        // Remove charset and other parameters
        const semicolon_pos = std.mem.indexOf(u8, mime_string, ";");
        const clean_mime = if (semicolon_pos) |pos|
            std.mem.trim(u8, mime_string[0..pos], " ")
        else
            std.mem.trim(u8, mime_string, " ");

        const mime_map = std.ComptimeStringMap(MimeType, .{
            .{ "text/plain", .text_plain },
            .{ "text/html", .text_html },
            .{ "text/css", .text_css },
            .{ "text/javascript", .text_javascript },
            .{ "text/xml", .text_xml },
            .{ "text/csv", .text_csv },
            .{ "text/markdown", .text_markdown },

            .{ "application/json", .application_json },
            .{ "application/xml", .application_xml },
            .{ "application/pdf", .application_pdf },
            .{ "application/zip", .application_zip },
            .{ "application/gzip", .application_gzip },
            .{ "application/tar", .application_tar },
            .{ "application/octet-stream", .application_octet_stream },
            .{ "application/x-www-form-urlencoded", .application_form_urlencoded },
            .{ "application/javascript", .application_javascript },

            .{ "image/jpeg", .image_jpeg },
            .{ "image/jpg", .image_jpeg },
            .{ "image/png", .image_png },
            .{ "image/gif", .image_gif },
            .{ "image/webp", .image_webp },
            .{ "image/svg+xml", .image_svg },
            .{ "image/x-icon", .image_ico },
            .{ "image/bmp", .image_bmp },
            .{ "image/tiff", .image_tiff },

            .{ "audio/mpeg", .audio_mpeg },
            .{ "audio/wav", .audio_wav },
            .{ "audio/ogg", .audio_ogg },
            .{ "audio/mp4", .audio_mp4 },
            .{ "audio/webm", .audio_webm },

            .{ "video/mp4", .video_mp4 },
            .{ "video/webm", .video_webm },
            .{ "video/ogg", .video_ogg },
            .{ "video/x-msvideo", .video_avi },
            .{ "video/quicktime", .video_mov },

            .{ "multipart/form-data", .multipart_form_data },
            .{ "multipart/mixed", .multipart_mixed },

            .{ "font/woff", .font_woff },
            .{ "font/woff2", .font_woff2 },
            .{ "font/ttf", .font_ttf },
            .{ "font/otf", .font_otf },
        });

        return mime_map.get(clean_mime) orelse .unknown;
    }

    /// Check if MIME type is text-based
    pub fn isText(self: MimeType) bool {
        return switch (self) {
            .text_plain, .text_html, .text_css, .text_javascript, .text_xml, .text_csv, .text_markdown => true,
            .application_json, .application_xml, .application_javascript => true,
            else => false,
        };
    }

    /// Check if MIME type is binary
    pub fn isBinary(self: MimeType) bool {
        return !self.isText();
    }

    /// Check if MIME type is image
    pub fn isImage(self: MimeType) bool {
        return switch (self) {
            .image_jpeg, .image_png, .image_gif, .image_webp, .image_svg, .image_ico, .image_bmp, .image_tiff => true,
            else => false,
        };
    }

    /// Check if MIME type is audio
    pub fn isAudio(self: MimeType) bool {
        return switch (self) {
            .audio_mpeg, .audio_wav, .audio_ogg, .audio_mp4, .audio_webm => true,
            else => false,
        };
    }

    /// Check if MIME type is video
    pub fn isVideo(self: MimeType) bool {
        return switch (self) {
            .video_mp4, .video_webm, .video_ogg, .video_avi, .video_mov => true,
            else => false,
        };
    }

    /// Check if MIME type is compressible
    pub fn isCompressible(self: MimeType) bool {
        return switch (self) {
            .text_plain, .text_html, .text_css, .text_javascript, .text_xml, .text_csv, .text_markdown => true,
            .application_json, .application_xml, .application_javascript => true,
            .image_svg => true,
            else => false,
        };
    }
};

/// MIME type detection utilities
pub const MimeDetector = struct {
    /// Detect MIME type from file extension
    pub fn fromExtension(extension: []const u8) MimeType {
        const ext_map = std.ComptimeStringMap(MimeType, .{
            // Text files
            .{ "txt", .text_plain },
            .{ "html", .text_html },
            .{ "htm", .text_html },
            .{ "css", .text_css },
            .{ "js", .text_javascript },
            .{ "mjs", .text_javascript },
            .{ "xml", .text_xml },
            .{ "csv", .text_csv },
            .{ "md", .text_markdown },
            .{ "markdown", .text_markdown },

            // Application files
            .{ "json", .application_json },
            .{ "pdf", .application_pdf },
            .{ "zip", .application_zip },
            .{ "gz", .application_gzip },
            .{ "tar", .application_tar },

            // Image files
            .{ "jpg", .image_jpeg },
            .{ "jpeg", .image_jpeg },
            .{ "png", .image_png },
            .{ "gif", .image_gif },
            .{ "webp", .image_webp },
            .{ "svg", .image_svg },
            .{ "ico", .image_ico },
            .{ "bmp", .image_bmp },
            .{ "tiff", .image_tiff },
            .{ "tif", .image_tiff },

            // Audio files
            .{ "mp3", .audio_mpeg },
            .{ "wav", .audio_wav },
            .{ "ogg", .audio_ogg },
            .{ "m4a", .audio_mp4 },
            .{ "webm", .audio_webm },

            // Video files
            .{ "mp4", .video_mp4 },
            .{ "webm", .video_webm },
            .{ "ogv", .video_ogg },
            .{ "avi", .video_avi },
            .{ "mov", .video_mov },

            // Font files
            .{ "woff", .font_woff },
            .{ "woff2", .font_woff2 },
            .{ "ttf", .font_ttf },
            .{ "otf", .font_otf },
        });

        const lower_ext = std.ascii.lowerString(std.heap.page_allocator, extension) catch return .unknown;
        defer std.heap.page_allocator.free(lower_ext);

        return ext_map.get(lower_ext) orelse .unknown;
    }

    /// Detect MIME type from file path
    pub fn fromPath(path: []const u8) MimeType {
        const extension = std.fs.path.extension(path);
        if (extension.len > 1) {
            return fromExtension(extension[1..]); // Skip the dot
        }
        return .unknown;
    }

    /// Detect MIME type from file content (magic bytes)
    pub fn fromContent(content: []const u8) MimeType {
        if (content.len == 0) return .unknown;

        // Check for common file signatures
        if (content.len >= 4) {
            // PNG
            if (std.mem.eql(u8, content[0..4], "\x89PNG")) {
                return .image_png;
            }
            // JPEG
            if (std.mem.eql(u8, content[0..2], "\xFF\xD8")) {
                return .image_jpeg;
            }
            // GIF
            if (std.mem.eql(u8, content[0..4], "GIF8")) {
                return .image_gif;
            }
            // PDF
            if (std.mem.eql(u8, content[0..4], "%PDF")) {
                return .application_pdf;
            }
            // ZIP
            if (std.mem.eql(u8, content[0..4], "PK\x03\x04")) {
                return .application_zip;
            }
        }

        if (content.len >= 8) {
            // WebP
            if (std.mem.eql(u8, content[0..4], "RIFF") and std.mem.eql(u8, content[8..12], "WEBP")) {
                return .image_webp;
            }
        }

        // Check for text content
        if (isTextContent(content)) {
            // Try to detect specific text types
            if (std.mem.indexOf(u8, content, "<!DOCTYPE html") != null or
                std.mem.indexOf(u8, content, "<html") != null)
            {
                return .text_html;
            }
            if (std.mem.indexOf(u8, content, "{") != null and
                std.mem.indexOf(u8, content, "}") != null)
            {
                // Might be JSON
                return .application_json;
            }
            return .text_plain;
        }

        return .application_octet_stream;
    }

    /// Check if content appears to be text
    fn isTextContent(content: []const u8) bool {
        var text_chars: usize = 0;
        var total_chars: usize = 0;

        for (content[0..@min(content.len, 1024)]) |byte| {
            total_chars += 1;
            if ((byte >= 32 and byte <= 126) or byte == '\t' or byte == '\n' or byte == '\r') {
                text_chars += 1;
            }
        }

        return total_chars > 0 and (text_chars * 100 / total_chars) >= 80;
    }
};

/// Content type utilities
pub const ContentType = struct {
    mime_type: MimeType,
    charset: ?[]const u8 = null,
    boundary: ?[]const u8 = null,
    parameters: ?std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage) = null,

    /// Parse content type header
    pub fn parse(allocator: std.mem.Allocator, content_type_header: []const u8) !ContentType {
        var result = ContentType{
            .mime_type = .unknown,
        };

        var parts = std.mem.split(u8, content_type_header, ";");

        // First part is the MIME type
        if (parts.next()) |mime_part| {
            const mime_string = std.mem.trim(u8, mime_part, " ");
            result.mime_type = MimeType.fromString(mime_string);
        }

        // Parse parameters
        var params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);

        while (parts.next()) |param_part| {
            const param = std.mem.trim(u8, param_part, " ");
            if (std.mem.indexOf(u8, param, "=")) |eq_pos| {
                const key = std.mem.trim(u8, param[0..eq_pos], " ");
                var value = std.mem.trim(u8, param[eq_pos + 1 ..], " ");

                // Remove quotes if present
                if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                    value = value[1 .. value.len - 1];
                }

                try params.put(key, value);

                // Set common parameters
                if (std.mem.eql(u8, key, "charset")) {
                    result.charset = value;
                } else if (std.mem.eql(u8, key, "boundary")) {
                    result.boundary = value;
                }
            }
        }

        if (params.count() > 0) {
            result.parameters = params;
        }

        return result;
    }

    /// Convert to string
    pub fn toString(self: ContentType, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        try result.appendSlice(self.mime_type.toString());

        if (self.charset) |charset| {
            try result.writer().print("; charset={s}", .{charset});
        }

        if (self.boundary) |boundary| {
            try result.writer().print("; boundary={s}", .{boundary});
        }

        if (self.parameters) |params| {
            var iterator = params.iterator();
            while (iterator.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;

                // Skip already handled parameters
                if (std.mem.eql(u8, key, "charset") or std.mem.eql(u8, key, "boundary")) {
                    continue;
                }

                try result.writer().print("; {s}={s}", .{ key, value });
            }
        }

        return result.toOwnedSlice();
    }

    /// Create content type with charset
    pub fn withCharset(mime_type: MimeType, charset: []const u8) ContentType {
        return ContentType{
            .mime_type = mime_type,
            .charset = charset,
        };
    }

    /// Create multipart content type with boundary
    pub fn multipartWithBoundary(boundary: []const u8) ContentType {
        return ContentType{
            .mime_type = .multipart_form_data,
            .boundary = boundary,
        };
    }
};

// Tests
test "MIME type detection from extension" {
    const testing = std.testing;

    try testing.expect(MimeDetector.fromExtension("html") == .text_html);
    try testing.expect(MimeDetector.fromExtension("json") == .application_json);
    try testing.expect(MimeDetector.fromExtension("png") == .image_png);
    try testing.expect(MimeDetector.fromExtension("mp4") == .video_mp4);
    try testing.expect(MimeDetector.fromExtension("unknown") == .unknown);
}

test "MIME type from string" {
    const testing = std.testing;

    try testing.expect(MimeType.fromString("text/html") == .text_html);
    try testing.expect(MimeType.fromString("application/json; charset=utf-8") == .application_json);
    try testing.expect(MimeType.fromString("image/png") == .image_png);
    try testing.expect(MimeType.fromString("unknown/type") == .unknown);
}

test "MIME type properties" {
    const testing = std.testing;

    try testing.expect(MimeType.text_html.isText());
    try testing.expect(!MimeType.image_png.isText());
    try testing.expect(MimeType.image_png.isImage());
    try testing.expect(MimeType.video_mp4.isVideo());
    try testing.expect(MimeType.text_html.isCompressible());
    try testing.expect(!MimeType.image_jpeg.isCompressible());
}

test "Content type parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ct = try ContentType.parse(allocator, "text/html; charset=utf-8");
    defer if (ct.parameters) |*params| params.deinit();

    try testing.expect(ct.mime_type == .text_html);
    try testing.expectEqualStrings("utf-8", ct.charset.?);
}
