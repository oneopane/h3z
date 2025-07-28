//! Server-Sent Events (SSE) support for H3Z
//! Implements W3C SSE specification for server-to-client streaming

const std = @import("std");

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