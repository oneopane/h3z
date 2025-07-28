//! SSE (Server-Sent Events) connection abstraction layer for H3Z
//! Provides a unified interface for SSE streaming across different server adapters
//! Enables real-time server-to-client event streaming

const std = @import("std");

/// SSE connection error set for streaming operations
pub const SSEConnectionError = error{
    ConnectionClosed,
    WriteError,
    BufferFull,
    AllocationError,
    NotStreamingMode,
};

/// Forward declarations for adapter-specific connection types
pub const LibxevConnection = @import("adapters/libxev.zig").LibxevConnection;
pub const StdConnection = @import("adapters/std.zig").StdConnection;

/// Unified SSE connection interface as a tagged union
/// Allows adapter-agnostic SSE streaming operations
pub const SSEConnection = union(enum) {
    libxev: *LibxevConnection,
    std: *StdConnection,

    /// Write a chunk of data without closing the connection
    /// Used for streaming protocols like SSE
    pub fn writeChunk(self: SSEConnection, data: []const u8) SSEConnectionError!void {
        return switch (self) {
            .libxev => |conn| conn.writeChunk(data),
            .std => |conn| conn.writeChunk(data),
        };
    }

    /// Flush any buffered data immediately
    /// Forces transmission of pending data
    pub fn flush(self: SSEConnection) SSEConnectionError!void {
        return switch (self) {
            .libxev => |conn| conn.flush(),
            .std => |conn| conn.flush(),
        };
    }

    /// Close the connection gracefully
    /// Cleans up resources and notifies the remote end
    pub fn close(self: SSEConnection) void {
        switch (self) {
            .libxev => |conn| conn.close(),
            .std => |conn| conn.close(),
        }
    }

    /// Check if the connection is still alive
    /// Returns false if the connection has been closed or errored
    pub fn isAlive(self: SSEConnection) bool {
        return switch (self) {
            .libxev => |conn| conn.isAlive(),
            .std => |conn| conn.isAlive(),
        };
    }

    /// Get the adapter type for this connection
    pub fn getAdapterType(self: SSEConnection) AdapterType {
        return switch (self) {
            .libxev => .libxev,
            .std => .std,
        };
    }
};

/// Adapter type enumeration
pub const AdapterType = enum {
    libxev,
    std,
};

/// SSE connection capabilities and state
pub const SSEConnectionState = enum {
    /// Initial state, ready for first write
    init,
    /// Active streaming mode (e.g., SSE active)
    streaming,
    /// Connection is closing or about to close
    closing,
    /// Connection is closed
    closed,
};

/// SSE connection metrics for monitoring
pub const SSEConnectionMetrics = struct {
    /// Total bytes written
    bytes_written: usize = 0,
    /// Total write operations
    write_count: usize = 0,
    /// Number of flush operations
    flush_count: usize = 0,
    /// Connection duration in milliseconds
    duration_ms: i64 = 0,
    /// Last activity timestamp
    last_activity: i64 = 0,
};

test "SSEConnection interface methods" {
    // This test verifies that the SSEConnection interface is properly defined
    // Actual testing will be done once the adapter implementations are complete
    
    // Verify that our SSEConnectionError set has the expected errors
    try std.testing.expect(@typeInfo(SSEConnectionError).error_set != null);
    
    // Verify specific errors exist
    const error_set = @typeInfo(SSEConnectionError).error_set.?;
    var has_connection_closed = false;
    var has_write_error = false;
    var has_buffer_full = false;
    var has_allocation_error = false;
    var has_not_streaming_mode = false;
    
    for (error_set) |err| {
        if (std.mem.eql(u8, err.name, "ConnectionClosed")) has_connection_closed = true;
        if (std.mem.eql(u8, err.name, "WriteError")) has_write_error = true;
        if (std.mem.eql(u8, err.name, "BufferFull")) has_buffer_full = true;
        if (std.mem.eql(u8, err.name, "AllocationError")) has_allocation_error = true;
        if (std.mem.eql(u8, err.name, "NotStreamingMode")) has_not_streaming_mode = true;
    }
    
    try std.testing.expect(has_connection_closed);
    try std.testing.expect(has_write_error);
    try std.testing.expect(has_buffer_full);
    try std.testing.expect(has_allocation_error);
    try std.testing.expect(has_not_streaming_mode);
}