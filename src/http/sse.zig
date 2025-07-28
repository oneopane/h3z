//! Server-Sent Events (SSE) support for H3Z
//! Implements W3C SSE specification for server-to-client streaming

const std = @import("std");
const SSEConnection = @import("../server/sse_connection.zig").SSEConnection;
const SSEConnectionError = @import("../server/sse_connection.zig").SSEConnectionError;

/// SSE error set for streaming operations
pub const SSEError = error{
    ResponseAlreadySent,
    SSEAlreadyStarted,
    SSENotStarted,
    ConnectionNotReady,
    WriterClosed,
    ConnectionLost,
    BackpressureDetected,
    WriteError,
    AllocationError,
    NotImplemented,
};

/// SSE event structure following W3C specification
/// Each event can have optional fields: data, event, id, retry
pub const SSEEvent = struct {
    /// The actual payload of the event (required)
    data: []const u8,
    
    /// Event type name (optional)
    event: ?[]const u8 = null,
    
    /// Event ID for client-side tracking (optional)
    id: ?[]const u8 = null,
    
    /// Retry interval in milliseconds (optional)
    retry: ?u32 = null,
    
    /// Format the SSE event according to W3C specification
    /// Returns a formatted string ready to be sent over the wire
    pub fn formatEvent(self: SSEEvent, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();
        
        // Write event type if specified
        if (self.event) |event_name| {
            try buffer.appendSlice("event: ");
            try buffer.appendSlice(event_name);
            try buffer.append('\n');
        }
        
        // Write ID if specified
        if (self.id) |event_id| {
            try buffer.appendSlice("id: ");
            try buffer.appendSlice(event_id);
            try buffer.append('\n');
        }
        
        // Write retry if specified
        if (self.retry) |retry_ms| {
            try buffer.appendSlice("retry: ");
            try std.fmt.format(buffer.writer(), "{d}", .{retry_ms});
            try buffer.append('\n');
        }
        
        // Write data field - handle multi-line data properly
        // Each line of data must be prefixed with "data: "
        var lines = std.mem.splitScalar(u8, self.data, '\n');
        while (lines.next()) |line| {
            try buffer.appendSlice("data: ");
            try buffer.appendSlice(line);
            try buffer.append('\n');
        }
        
        // SSE events are terminated by double newline
        try buffer.append('\n');
        
        return buffer.toOwnedSlice();
    }
    
    /// Create a simple data-only event
    pub fn dataEvent(data: []const u8) SSEEvent {
        return .{ .data = data };
    }
    
    /// Create an event with a type
    pub fn typedEvent(event_type: []const u8, data: []const u8) SSEEvent {
        return .{
            .data = data,
            .event = event_type,
        };
    }
};

/// Builder pattern for convenient SSE event creation
pub const SSEEventBuilder = struct {
    data: ?[]const u8 = null,
    event: ?[]const u8 = null,
    id: ?[]const u8 = null,
    retry: ?u32 = null,
    
    pub fn init() SSEEventBuilder {
        return .{};
    }
    
    pub fn setData(self: *SSEEventBuilder, data: []const u8) *SSEEventBuilder {
        self.data = data;
        return self;
    }
    
    pub fn setEvent(self: *SSEEventBuilder, event: []const u8) *SSEEventBuilder {
        self.event = event;
        return self;
    }
    
    pub fn setId(self: *SSEEventBuilder, id: []const u8) *SSEEventBuilder {
        self.id = id;
        return self;
    }
    
    pub fn setRetry(self: *SSEEventBuilder, retry_ms: u32) *SSEEventBuilder {
        self.retry = retry_ms;
        return self;
    }
    
    pub fn build(self: SSEEventBuilder) !SSEEvent {
        if (self.data == null) {
            return error.MissingData;
        }
        
        return SSEEvent{
            .data = self.data.?,
            .event = self.event,
            .id = self.id,
            .retry = self.retry,
        };
    }
};

/// Create a keep-alive comment event
/// Used to maintain connection when no data is being sent
pub fn keepAliveEvent() SSEEvent {
    return .{ .data = ": keep-alive" };
}

/// SSE writer for managing server-sent event streams
pub const SSEWriter = struct {
    allocator: std.mem.Allocator,
    connection: *SSEConnection,
    closed: bool = false,
    event_count: usize = 0,
    
    /// Initialize a new SSE writer
    pub fn init(allocator: std.mem.Allocator, connection: *SSEConnection) SSEWriter {
        return .{
            .allocator = allocator,
            .connection = connection,
            .closed = false,
            .event_count = 0,
        };
    }
    
    /// Send an SSE event to the client
    pub fn sendEvent(self: *SSEWriter, event: SSEEvent) SSEError!void {
        if (self.closed) return error.WriterClosed;
        
        // Format event
        const formatted = try event.formatEvent(self.allocator);
        defer self.allocator.free(formatted);
        
        // Write to connection
        self.connection.writeChunk(formatted) catch |err| {
            return switch (err) {
                error.ConnectionClosed => error.ConnectionLost,
                error.BufferFull => error.BackpressureDetected,
                else => error.WriteError,
            };
        };
        
        // Flush for real-time delivery
        self.connection.flush() catch |err| {
            return switch (err) {
                error.ConnectionClosed => error.ConnectionLost,
                else => error.WriteError,
            };
        };
        
        self.event_count += 1;
    }
    
    /// Send a keep-alive comment to maintain the connection
    pub fn sendKeepAlive(self: *SSEWriter) SSEError!void {
        if (self.closed) return error.WriterClosed;
        
        const keepalive = ":heartbeat\n\n";
        
        self.connection.writeChunk(keepalive) catch |err| {
            return switch (err) {
                error.ConnectionClosed => error.ConnectionLost,
                error.BufferFull => error.BackpressureDetected,
                else => error.WriteError,
            };
        };
        
        self.connection.flush() catch {
            return error.WriteError;
        };
    }
    
    /// Close the SSE writer and underlying connection
    pub fn close(self: *SSEWriter) void {
        if (!self.closed) {
            self.connection.close();
            self.closed = true;
        }
    }
    
    /// Check if the writer is still active
    pub fn isActive(self: *const SSEWriter) bool {
        return !self.closed and self.connection.isAlive();
    }
    
    /// Get the number of events sent
    pub fn getEventCount(self: *const SSEWriter) usize {
        return self.event_count;
    }
};

test "SSEEvent simple data formatting" {
    const allocator = std.testing.allocator;
    
    const event = SSEEvent.dataEvent("Hello, World!");
    const formatted = try event.formatEvent(allocator);
    defer allocator.free(formatted);
    
    try std.testing.expectEqualStrings("data: Hello, World!\n\n", formatted);
}

test "SSEEvent with all fields" {
    const allocator = std.testing.allocator;
    
    const event = SSEEvent{
        .data = "Test message",
        .event = "message",
        .id = "123",
        .retry = 5000,
    };
    
    const formatted = try event.formatEvent(allocator);
    defer allocator.free(formatted);
    
    const expected = "event: message\nid: 123\nretry: 5000\ndata: Test message\n\n";
    try std.testing.expectEqualStrings(expected, formatted);
}

test "SSEEvent multi-line data" {
    const allocator = std.testing.allocator;
    
    const event = SSEEvent{
        .data = "Line 1\nLine 2\nLine 3",
        .event = "multi",
    };
    
    const formatted = try event.formatEvent(allocator);
    defer allocator.free(formatted);
    
    const expected = "event: multi\ndata: Line 1\ndata: Line 2\ndata: Line 3\n\n";
    try std.testing.expectEqualStrings(expected, formatted);
}

test "SSEEventBuilder" {
    var builder = SSEEventBuilder.init();
    const event = try builder
        .setData("Builder test")
        .setEvent("test")
        .setId("456")
        .build();
    
    try std.testing.expectEqualStrings("Builder test", event.data);
    try std.testing.expectEqualStrings("test", event.event.?);
    try std.testing.expectEqualStrings("456", event.id.?);
    try std.testing.expectEqual(@as(?u32, null), event.retry);
}

test "SSEEventBuilder missing data error" {
    var builder = SSEEventBuilder.init();
    const result = builder.setEvent("test").build();
    
    try std.testing.expectError(error.MissingData, result);
}

test "SSE special characters in data" {
    const allocator = std.testing.allocator;
    
    const event = SSEEvent{
        .data = "Special chars: \r\n\t\"'<>&",
    };
    
    const formatted = try event.formatEvent(allocator);
    defer allocator.free(formatted);
    
    // SSE doesn't require escaping, just proper line handling
    const expected = "data: Special chars: \r\ndata: \t\"'<>&\n\n";
    try std.testing.expectEqualStrings(expected, formatted);
}