# SSE Callback Implementation Plan

## Overview
This document details the implementation of a callback-based streaming API for Server-Sent Events in H3Z.

## Architecture Changes

### 1. H3Event Modifications

Add a callback field to H3Event:

```zig
// In src/core/event.zig

pub const SSEStreamCallback = *const fn (writer: *SSEWriter) anyerror!void;

pub const H3Event = struct {
    // ... existing fields ...
    
    /// SSE streaming callback (set by handler, called by adapter)
    sse_callback: ?SSEStreamCallback = null,
    
    // ... rest of struct ...
    
    /// Set the SSE streaming callback
    pub fn setStreamCallback(self: *H3Event, callback: SSEStreamCallback) void {
        self.sse_callback = callback;
    }
};
```

### 2. Adapter Modifications

Update the libxev adapter to call the callback after setup:

```zig
// In src/server/adapters/libxev.zig

// In the handleRequest function, after SSE setup:
if (event.sse_started) {
    logger.logDefault(.debug, .connection, "SSE mode detected, setting up streaming connection", .{});
    
    // Create streaming connection
    const stream_conn = try self.createStreamingConnection(loop);
    
    // Convert to SSEConnection and link to event
    const sse_conn = try self.allocator.create(@import("../sse_connection.zig").SSEConnection);
    sse_conn.* = stream_conn.toSSEConnection();
    event.sse_connection = sse_conn;
    
    // Send SSE headers immediately
    try self.sendSSEHeaders(loop, event);
    
    // NEW: Check for streaming callback
    if (event.sse_callback) |callback| {
        // Create SSE writer
        const writer = try SSEWriter.init(self.allocator, sse_conn);
        
        // Schedule callback execution
        try self.scheduleSSECallback(loop, callback, writer);
    }
    
    return; // Skip normal response flow
}

// New method to schedule the callback
fn scheduleSSECallback(self: *Connection, loop: *xev.Loop, callback: SSEStreamCallback, writer: *SSEWriter) !void {
    // Create a task for the event loop
    const task = try self.allocator.create(SSECallbackTask);
    task.* = .{
        .callback = callback,
        .writer = writer,
        .connection = self,
    };
    
    // Schedule for next tick
    var c: xev.Completion = .{
        .op = .{ .timer = .{ .ns = 0 } }, // Execute immediately
        .userdata = task,
        .callback = executeSSECallback,
    };
    loop.add(&c);
}

const SSECallbackTask = struct {
    callback: SSEStreamCallback,
    writer: *SSEWriter,
    connection: *Connection,
};

fn executeSSECallback(userdata: ?*anyopaque, loop: *xev.Loop, c: *xev.Completion, result: xev.Timer.RunError!void) xev.CallbackAction {
    _ = result catch |err| {
        logger.logDefault(.err, .connection, "Timer error: {}", .{err});
        return .disarm;
    };
    
    const task = @as(*SSECallbackTask, @ptrCast(@alignCast(userdata.?)));
    defer task.connection.allocator.destroy(task);
    
    // Execute the user's streaming callback
    task.callback(task.writer) catch |err| {
        logger.logDefault(.err, .connection, "SSE callback error: {}", .{err});
        task.writer.close();
    };
    
    return .disarm;
}
```

### 3. Updated Example Usage

Here's how the examples would look with the callback approach:

```zig
// examples/sse_counter_callback.zig

const std = @import("std");
const h3z = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try h3z.H3.init(allocator);
    defer app.deinit();

    _ = app.get("/events", counterHandler);
    _ = app.get("/", htmlHandler);

    try h3z.serve(&app, h3z.ServeOptions{
        .port = 3000,
        .host = "127.0.0.1",
    });
}

fn counterHandler(event: *h3z.Event) !void {
    // Start SSE and register callback
    try event.startSSE();
    event.setStreamCallback(streamCounter);
    // Handler returns immediately
}

fn streamCounter(writer: *h3z.SSEWriter) !void {
    defer writer.close();
    
    var counter: u32 = 0;
    var buffer: [64]u8 = undefined;
    
    // Send initial value
    const count_str = try std.fmt.bufPrint(&buffer, "{d}", .{counter});
    try writer.sendEvent(h3z.SSEEvent{
        .data = count_str,
        .event = "counter",
        .id = count_str,
    });
    
    // Stream for 30 seconds
    const start_time = std.time.milliTimestamp();
    while (std.time.milliTimestamp() - start_time < 30000) {
        std.time.sleep(1 * std.time.ns_per_s);
        
        counter += 1;
        const new_count_str = try std.fmt.bufPrint(&buffer, "{d}", .{counter});
        
        try writer.sendEvent(h3z.SSEEvent{
            .data = new_count_str,
            .event = "counter",
            .id = new_count_str,
        });
    }
    
    try writer.sendEvent(h3z.SSEEvent{
        .data = "Counter complete!",
        .event = "done",
    });
}
```

## Implementation Steps

1. **Update H3Event** (src/core/event.zig)
   - Add `sse_callback` field
   - Add `setStreamCallback` method
   - Add `SSEStreamCallback` type definition

2. **Update Adapters** (src/server/adapters/libxev.zig & std.zig)
   - Add callback scheduling after SSE setup
   - Implement callback execution in event loop
   - Handle callback errors gracefully

3. **Update Examples**
   - Convert existing examples to use callbacks
   - Add error handling examples
   - Add complex streaming examples

4. **Testing**
   - Add unit tests for callback mechanism
   - Add integration tests for streaming lifecycle
   - Add performance tests for callback overhead

## Benefits of This Approach

1. **Clean Separation**: Handler logic is separate from streaming logic
2. **Framework Compatible**: Works with the existing request/response model
3. **Error Handling**: Errors in streaming don't affect the handler
4. **Flexibility**: Callbacks can be reused across multiple endpoints
5. **Testing**: Callbacks can be tested independently

## Alternative Considerations

### Context Passing
If the callback needs access to request data:

```zig
pub const SSEStreamContext = struct {
    writer: *SSEWriter,
    request: *const Request,
    allocator: std.mem.Allocator,
    user_data: ?*anyopaque = null,
};

pub const SSEStreamCallback = *const fn (ctx: *SSEStreamContext) anyerror!void;
```

### Async/Await (Future Enhancement)
Once Zig's async story is more stable:

```zig
fn handler(event: *H3Event) !void {
    try event.startSSE();
    const writer = try event.awaitSSEWriter(); // Suspends
    defer writer.close();
    // ... streaming code
}
```

## Timeline

1. **Phase 1**: Implement basic callback support (2-3 hours)
2. **Phase 2**: Update all adapters (1-2 hours)
3. **Phase 3**: Convert examples (1 hour)
4. **Phase 4**: Add comprehensive tests (2-3 hours)
5. **Phase 5**: Documentation (1 hour)

Total estimated time: 7-10 hours of implementation work