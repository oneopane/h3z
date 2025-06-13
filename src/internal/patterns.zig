//! Path pattern matching utilities for H3 framework
//! Provides route pattern matching, parameter extraction, and wildcard support

const std = @import("std");

/// Pattern matching errors
pub const PatternError = error{
    InvalidPattern,
    InvalidParameter,
    TooManyParameters,
    PatternTooLong,
};

/// Route parameter
pub const RouteParam = struct {
    name: []const u8,
    value: []const u8,
};

/// Pattern matching result
pub const MatchResult = struct {
    matched: bool,
    params: []RouteParam,
    wildcard: ?[]const u8 = null,

    pub fn deinit(self: MatchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.params);
    }
};

/// Route pattern types
pub const PatternType = enum {
    exact, // /users/123
    param, // /users/:id
    wildcard, // /files/*
    regex, // /users/[0-9]+
};

/// Compiled route pattern
pub const CompiledPattern = struct {
    pattern: []const u8,
    pattern_type: PatternType,
    segments: []PatternSegment,
    param_names: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CompiledPattern) void {
        self.allocator.free(self.segments);
        self.allocator.free(self.param_names);
    }

    /// Match path against this pattern
    pub fn match(self: CompiledPattern, allocator: std.mem.Allocator, path: []const u8) !MatchResult {
        return PatternMatcher.matchPattern(allocator, self, path);
    }
};

/// Pattern segment types
pub const SegmentType = enum {
    literal, // exact string match
    param, // :param
    wildcard, // *
    optional, // :param?
    regex, // [pattern]
};

/// Pattern segment
pub const PatternSegment = struct {
    segment_type: SegmentType,
    value: []const u8,
    param_name: ?[]const u8 = null,
    optional: bool = false,
};

/// Pattern compiler
pub const PatternCompiler = struct {
    /// Compile a route pattern
    pub fn compile(allocator: std.mem.Allocator, pattern: []const u8) !CompiledPattern {
        if (pattern.len == 0) return PatternError.InvalidPattern;

        var segments = std.ArrayList(PatternSegment).init(allocator);
        defer segments.deinit();

        var param_names = std.ArrayList([]const u8).init(allocator);
        defer param_names.deinit();

        var pattern_type = PatternType.exact;

        // Split pattern into segments
        var path_segments = std.mem.split(u8, pattern, "/");
        while (path_segments.next()) |segment| {
            if (segment.len == 0) continue;

            const compiled_segment = try compileSegment(segment);
            try segments.append(compiled_segment);

            // Determine overall pattern type
            switch (compiled_segment.segment_type) {
                .param, .optional => {
                    pattern_type = .param;
                    if (compiled_segment.param_name) |name| {
                        try param_names.append(name);
                    }
                },
                .wildcard => pattern_type = .wildcard,
                .regex => pattern_type = .regex,
                .literal => {},
            }
        }

        return CompiledPattern{
            .pattern = pattern,
            .pattern_type = pattern_type,
            .segments = try segments.toOwnedSlice(),
            .param_names = try param_names.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    /// Compile a single segment
    fn compileSegment(segment: []const u8) !PatternSegment {
        if (segment.len == 0) return PatternError.InvalidPattern;

        // Wildcard
        if (std.mem.eql(u8, segment, "*")) {
            return PatternSegment{
                .segment_type = .wildcard,
                .value = segment,
            };
        }

        // Parameter
        if (segment[0] == ':') {
            if (segment.len == 1) return PatternError.InvalidParameter;

            const param_name = segment[1..];
            const optional = std.mem.endsWith(u8, param_name, "?");
            const clean_name = if (optional) param_name[0 .. param_name.len - 1] else param_name;

            return PatternSegment{
                .segment_type = if (optional) .optional else .param,
                .value = segment,
                .param_name = clean_name,
                .optional = optional,
            };
        }

        // Regex pattern
        if (segment[0] == '[' and segment[segment.len - 1] == ']') {
            return PatternSegment{
                .segment_type = .regex,
                .value = segment[1 .. segment.len - 1],
            };
        }

        // Literal
        return PatternSegment{
            .segment_type = .literal,
            .value = segment,
        };
    }
};

/// Pattern matcher
pub const PatternMatcher = struct {
    /// Match a path against a compiled pattern
    pub fn matchPattern(allocator: std.mem.Allocator, pattern: CompiledPattern, path: []const u8) !MatchResult {
        var params = std.ArrayList(RouteParam).init(allocator);
        defer params.deinit();

        // Split path into segments
        var path_segments = std.ArrayList([]const u8).init(allocator);
        defer path_segments.deinit();

        var segments_iter = std.mem.split(u8, path, "/");
        while (segments_iter.next()) |segment| {
            if (segment.len > 0) {
                try path_segments.append(segment);
            }
        }

        // Match segments
        var pattern_index: usize = 0;
        var path_index: usize = 0;

        while (pattern_index < pattern.segments.len and path_index < path_segments.items.len) {
            const pattern_segment = pattern.segments[pattern_index];
            const path_segment = path_segments.items[path_index];

            switch (pattern_segment.segment_type) {
                .literal => {
                    if (!std.mem.eql(u8, pattern_segment.value, path_segment)) {
                        return MatchResult{ .matched = false, .params = &.{} };
                    }
                },
                .param => {
                    if (pattern_segment.param_name) |name| {
                        try params.append(RouteParam{
                            .name = name,
                            .value = path_segment,
                        });
                    }
                },
                .optional => {
                    if (pattern_segment.param_name) |name| {
                        try params.append(RouteParam{
                            .name = name,
                            .value = path_segment,
                        });
                    }
                },
                .wildcard => {
                    // Wildcard matches remaining path
                    var remaining_path = std.ArrayList(u8).init(allocator);
                    defer remaining_path.deinit();

                    for (path_segments.items[path_index..], 0..) |segment, i| {
                        if (i > 0) try remaining_path.append('/');
                        try remaining_path.appendSlice(segment);
                    }

                    return MatchResult{
                        .matched = true,
                        .params = try params.toOwnedSlice(),
                        .wildcard = try remaining_path.toOwnedSlice(),
                    };
                },
                .regex => {
                    // Simple regex matching (basic implementation)
                    if (!matchRegexPattern(pattern_segment.value, path_segment)) {
                        return MatchResult{ .matched = false, .params = &.{} };
                    }
                },
            }

            pattern_index += 1;
            path_index += 1;
        }

        // Handle optional parameters at the end
        while (pattern_index < pattern.segments.len) {
            const pattern_segment = pattern.segments[pattern_index];
            if (pattern_segment.segment_type != .optional) {
                return MatchResult{ .matched = false, .params = &.{} };
            }
            pattern_index += 1;
        }

        // Check if all path segments were consumed
        const matched = path_index == path_segments.items.len;

        return MatchResult{
            .matched = matched,
            .params = try params.toOwnedSlice(),
        };
    }

    /// Simple regex pattern matching
    fn matchRegexPattern(pattern: []const u8, text: []const u8) bool {
        // Very basic regex implementation
        // In a real implementation, you'd use a proper regex library

        if (std.mem.eql(u8, pattern, "[0-9]+")) {
            // Match one or more digits
            if (text.len == 0) return false;
            for (text) |char| {
                if (char < '0' or char > '9') return false;
            }
            return true;
        }

        if (std.mem.eql(u8, pattern, "[a-zA-Z]+")) {
            // Match one or more letters
            if (text.len == 0) return false;
            for (text) |char| {
                if (!std.ascii.isAlphabetic(char)) return false;
            }
            return true;
        }

        if (std.mem.eql(u8, pattern, "[a-zA-Z0-9]+")) {
            // Match one or more alphanumeric characters
            if (text.len == 0) return false;
            for (text) |char| {
                if (!std.ascii.isAlphanumeric(char)) return false;
            }
            return true;
        }

        // Default: exact match
        return std.mem.eql(u8, pattern, text);
    }

    /// Match multiple patterns against a path
    pub fn matchAny(allocator: std.mem.Allocator, patterns: []CompiledPattern, path: []const u8) !?struct { pattern: *const CompiledPattern, result: MatchResult } {
        for (patterns) |*pattern| {
            const result = try pattern.match(allocator, path);
            if (result.matched) {
                return .{ .pattern = pattern, .result = result };
            }
        }
        return null;
    }
};

/// Pattern utilities
pub const PatternUtils = struct {
    /// Check if pattern contains parameters
    pub fn hasParameters(pattern: []const u8) bool {
        return std.mem.indexOf(u8, pattern, ":") != null;
    }

    /// Check if pattern contains wildcards
    pub fn hasWildcards(pattern: []const u8) bool {
        return std.mem.indexOf(u8, pattern, "*") != null;
    }

    /// Extract parameter names from pattern
    pub fn extractParameterNames(allocator: std.mem.Allocator, pattern: []const u8) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        defer names.deinit();

        var segments = std.mem.split(u8, pattern, "/");
        while (segments.next()) |segment| {
            if (segment.len > 1 and segment[0] == ':') {
                const param_name = segment[1..];
                const clean_name = if (std.mem.endsWith(u8, param_name, "?"))
                    param_name[0 .. param_name.len - 1]
                else
                    param_name;
                try names.append(clean_name);
            }
        }

        return names.toOwnedSlice();
    }

    /// Build path from pattern and parameters
    pub fn buildPath(allocator: std.mem.Allocator, pattern: []const u8, params: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage)) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var segments = std.mem.split(u8, pattern, "/");
        var first = true;
        while (segments.next()) |segment| {
            if (segment.len == 0) continue;

            if (!first) try result.append('/');
            first = false;

            if (segment.len > 1 and segment[0] == ':') {
                const param_name = segment[1..];
                const clean_name = if (std.mem.endsWith(u8, param_name, "?"))
                    param_name[0 .. param_name.len - 1]
                else
                    param_name;

                if (params.get(clean_name)) |value| {
                    try result.appendSlice(value);
                } else if (!std.mem.endsWith(u8, param_name, "?")) {
                    return PatternError.InvalidParameter;
                }
            } else {
                try result.appendSlice(segment);
            }
        }

        return result.toOwnedSlice();
    }

    /// Normalize pattern (remove double slashes, etc.)
    pub fn normalize(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var prev_was_slash = false;
        for (pattern) |char| {
            if (char == '/') {
                if (!prev_was_slash) {
                    try result.append(char);
                }
                prev_was_slash = true;
            } else {
                try result.append(char);
                prev_was_slash = false;
            }
        }

        // Ensure pattern starts with /
        if (result.items.len == 0 or result.items[0] != '/') {
            try result.insert(0, '/');
        }

        return result.toOwnedSlice();
    }
};

// Tests
test "Pattern compilation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var pattern = try PatternCompiler.compile(allocator, "/users/:id/posts/:postId");
    defer pattern.deinit();

    try testing.expect(pattern.pattern_type == .param);
    try testing.expect(pattern.segments.len == 4);
    try testing.expect(pattern.param_names.len == 2);
    try testing.expectEqualStrings("id", pattern.param_names[0]);
    try testing.expectEqualStrings("postId", pattern.param_names[1]);
}

test "Pattern matching" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var pattern = try PatternCompiler.compile(allocator, "/users/:id");
    defer pattern.deinit();

    const result = try pattern.match(allocator, "/users/123");
    defer result.deinit(allocator);

    try testing.expect(result.matched);
    try testing.expect(result.params.len == 1);
    try testing.expectEqualStrings("id", result.params[0].name);
    try testing.expectEqualStrings("123", result.params[0].value);
}

test "Wildcard matching" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var pattern = try PatternCompiler.compile(allocator, "/files/*");
    defer pattern.deinit();

    const result = try pattern.match(allocator, "/files/documents/readme.txt");
    defer result.deinit(allocator);
    defer if (result.wildcard) |wc| allocator.free(wc);

    try testing.expect(result.matched);
    try testing.expectEqualStrings("documents/readme.txt", result.wildcard.?);
}

test "Parameter extraction" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const names = try PatternUtils.extractParameterNames(allocator, "/users/:id/posts/:postId?");
    defer allocator.free(names);

    try testing.expect(names.len == 2);
    try testing.expectEqualStrings("id", names[0]);
    try testing.expectEqualStrings("postId", names[1]);
}
