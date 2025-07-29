# SSE Implementation: libxev vs std Adapters

## Why the Callback Solution is libxev-Specific

### libxev Adapter
- **Has an event loop** that can schedule callbacks
- **Non-blocking I/O** allows long-running operations without blocking other connections
- **Task scheduling** via `xev.Completion` and timers
- **Perfect for SSE** because it can handle multiple concurrent streams

### std Adapter
- **Blocking I/O** - each connection blocks its thread
- **No built-in event loop** - just sequential request handling
- **Thread-per-connection** model (or single-threaded blocking)
- **Challenge for SSE** - would block the entire server during streaming

## Implementation Strategies

### For libxev (Your Focus)
```zig
// Clean callback approach as discussed
fn scheduleSSECallback(self: *Connection, loop: *xev.Loop, callback: SSEStreamCallback, writer: *SSEWriter) !void {
    var c: xev.Completion = .{
        .op = .{ .timer = .{ .ns = 0 } },
        .userdata = task,
        .callback = executeSSECallback,
    };
    loop.add(&c);
}
```

### For std Adapter (If Needed)
Several options:

#### Option 1: Spawn Thread
```zig
// In std adapter after SSE setup
if (event.sse_callback) |callback| {
    const thread = try std.Thread.spawn(.{}, runSSECallback, .{callback, writer});
    thread.detach(); // Let it run independently
}

fn runSSECallback(callback: SSEStreamCallback, writer: *SSEWriter) void {
    callback(writer) catch |err| {
        std.log.err("SSE callback error: {}", .{err});
    };
}
```

#### Option 2: Direct Execution (Blocks)
```zig
// Just call the callback directly (blocks the connection)
if (event.sse_callback) |callback| {
    callback(writer) catch |err| {
        std.log.err("SSE callback error: {}", .{err});
    };
}
```

#### Option 3: Don't Support SSE in std
```zig
// In std adapter
if (event.sse_started) {
    try event.sendText("SSE not supported with std adapter. Use libxev.");
    return;
}
```

## Recommendation

Since you only care about libxev, I recommend:

1. **Implement the callback solution for libxev only**
2. **Document that SSE requires libxev adapter**
3. **Have std adapter return an error for SSE attempts**

This is actually a common pattern - many features require specific adapters:
- WebSockets often require event-loop based servers
- HTTP/2 Server Push needs compatible adapters
- Long polling needs non-blocking I/O

## Code Organization

```zig
// In H3Event
pub fn setStreamCallback(self: *H3Event, callback: SSEStreamCallback) void {
    if (!@import("build_options").libxev_enabled) {
        std.log.warn("SSE callbacks require libxev adapter", .{});
    }
    self.sse_callback = callback;
}
```

## Documentation Example

```zig
/// Start Server-Sent Events streaming
/// 
/// Note: SSE requires the libxev adapter for proper streaming support.
/// The std adapter does not support long-lived connections.
/// 
/// Example:
/// ```zig
/// fn handler(event: *H3Event) !void {
///     try event.startSSE();
///     event.setStreamCallback(myStreamFunction);
/// }
/// ```
pub fn startSSE(self: *H3Event) !void {
    // ... existing implementation
}
```

## Why This is Fine

1. **Performance**: SSE is typically used in production scenarios where you'd want libxev anyway
2. **Simplicity**: No need to complicate std adapter with threading
3. **Clear boundaries**: Features tied to adapter capabilities
4. **Common pattern**: Many web frameworks have adapter-specific features

Your focus on libxev makes sense for SSE - it's the right tool for the job!