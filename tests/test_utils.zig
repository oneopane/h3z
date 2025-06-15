//! Test utilities for H3 framework
//! Provides common testing helpers and assertions

const std = @import("std");
const h3 = @import("h3");

// Use H3 module types to avoid conflicts
const HttpMethod = h3.HttpMethod;
const H3Event = h3.Event;

/// Test allocator wrapper with leak detection
pub const TestAllocator = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    allocator: std.mem.Allocator,

    pub fn init() TestAllocator {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        return TestAllocator{
            .gpa = gpa,
            .allocator = gpa.allocator(),
        };
    }

    pub fn deinit(self: *TestAllocator) void {
        const leaked = self.gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in test!", .{});
        }
    }
};

/// Assertion helpers
pub const assert = struct {
    /// Assert response body contains text
    pub fn expectBodyContains(body: ?[]const u8, expected: []const u8) !void {
        const actual_body = body orelse return error.NoBody;
        if (std.mem.indexOf(u8, actual_body, expected) == null) {
            std.log.err("Expected body to contain '{s}', but got '{s}'", .{ expected, actual_body });
            return error.BodyDoesNotContain;
        }
    }

    /// Assert JSON response structure
    pub fn expectJsonField(json_str: []const u8, field: []const u8, expected: []const u8) !void {
        // Simple JSON field extraction for testing purposes
        const field_pattern = try std.fmt.allocPrint(std.testing.allocator, "\"{s}\":", .{field});
        defer std.testing.allocator.free(field_pattern);

        if (std.mem.indexOf(u8, json_str, field_pattern)) |start| {
            const value_start = start + field_pattern.len;
            if (std.mem.indexOf(u8, json_str[value_start..], expected)) |_| {
                return; // Found the expected value
            }
        }

        std.log.err("Expected JSON field '{s}' to contain '{s}' in: {s}", .{ field, expected, json_str });
        return error.JsonFieldMismatch;
    }
};

/// Performance testing utilities
pub const perf = struct {
    /// Measure execution time of a function
    pub fn measureTime(comptime func: anytype, args: anytype) !struct { result: @TypeOf(@call(.auto, func, args)), duration_ns: u64 } {
        const start = std.time.nanoTimestamp();
        const result = @call(.auto, func, args);
        const end = std.time.nanoTimestamp();

        return .{
            .result = result,
            .duration_ns = @intCast(end - start),
        };
    }

    /// Run a function multiple times and get average duration
    pub fn benchmark(comptime func: anytype, args: anytype, iterations: u32) !struct { avg_duration_ns: u64, min_ns: u64, max_ns: u64 } {
        var total_duration: u64 = 0;
        var min_duration: u64 = std.math.maxInt(u64);
        var max_duration: u64 = 0;

        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            const measurement = try measureTime(func, args);
            total_duration += measurement.duration_ns;
            min_duration = @min(min_duration, measurement.duration_ns);
            max_duration = @max(max_duration, measurement.duration_ns);
        }

        return .{
            .avg_duration_ns = total_duration / iterations,
            .min_ns = min_duration,
            .max_ns = max_duration,
        };
    }
};

/// Mock request builder for testing
pub const MockRequest = struct {
    event: H3Event,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MockRequest {
        return MockRequest{
            .event = H3Event.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MockRequest) void {
        self.event.deinit();
    }

    /// Set HTTP method
    pub fn method(self: *MockRequest, http_method: HttpMethod) *MockRequest {
        self.event.request.method = http_method;
        return self;
    }

    /// Set request path
    pub fn path(self: *MockRequest, request_path: []const u8) *MockRequest {
        self.event.request.path = request_path;
        return self;
    }

    /// Set request URL (includes path and query)
    pub fn url(self: *MockRequest, request_url: []const u8) *MockRequest {
        self.event.request.parseUrl(request_url) catch |err| {
            std.log.err("Failed to parse URL: {}", .{err});
        };
        return self;
    }

    /// Set request body
    pub fn body(self: *MockRequest, request_body: []const u8) *MockRequest {
        self.event.request.body = request_body;
        return self;
    }

    /// Set request header
    pub fn header(self: *MockRequest, name: []const u8, value: []const u8) *MockRequest {
        self.event.request.setHeader(name, value) catch |err| {
            std.log.err("Failed to set header: {}", .{err});
        };
        return self;
    }

    /// Set query parameter
    pub fn query(self: *MockRequest, name: []const u8, value: []const u8) *MockRequest {
        self.event.query.put(name, value) catch |err| {
            std.log.err("Failed to set query parameter: {}", .{err});
        };
        return self;
    }

    /// Set route parameter
    pub fn param(self: *MockRequest, name: []const u8, value: []const u8) *MockRequest {
        self.event.setParam(name, value) catch |err| {
            std.log.err("Failed to set route parameter: {}", .{err});
        };
        return self;
    }

    /// Build the event
    pub fn build(self: *MockRequest) *H3Event {
        return &self.event;
    }

    /// Convenience method to create a GET request
    pub fn get(allocator: std.mem.Allocator, request_path: []const u8) MockRequest {
        var mock = MockRequest.init(allocator);
        _ = mock.method(.GET).path(request_path);
        return mock;
    }

    /// Convenience method to create a POST request
    pub fn post(allocator: std.mem.Allocator, request_path: []const u8, request_body: []const u8) MockRequest {
        var mock = MockRequest.init(allocator);
        _ = mock.method(.POST).path(request_path).body(request_body);
        return mock;
    }

    /// Convenience method to create a JSON POST request
    pub fn postJson(allocator: std.mem.Allocator, request_path: []const u8, json_body: []const u8) MockRequest {
        var mock = MockRequest.init(allocator);
        _ = mock.method(.POST).path(request_path).body(json_body).header("Content-Type", "application/json");
        return mock;
    }
};
