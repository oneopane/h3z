# SSE Callback Mechanism Explained

## Type Definition

```zig
pub const SSEStreamCallback = *const fn (writer: *SSEWriter) anyerror!void;
```

Breaking this down:
- `*const fn` - A pointer to a function
- `(writer: *SSEWriter)` - Takes one argument: a pointer to an SSEWriter
- `anyerror!void` - Can return any error or void

## The Flow

### Step 1: Handler Registration
```zig
fn counterHandler(event: *H3Event) !void {
    try event.startSSE();
    event.setStreamCallback(streamCounter);  // Store function pointer
    // Handler returns immediately
}
```

Here, `streamCounter` is a function pointer that gets stored in the H3Event struct.

### Step 2: Adapter Checks for Callback
```zig
// In libxev adapter, after setting up SSE connection:
if (event.sse_callback) |callback| {
    // We have a callback! Create the writer and schedule it
    const writer = try SSEWriter.init(self.allocator, sse_conn);
    try self.scheduleSSECallback(loop, callback, writer);
}
```

### Step 3: Schedule with Event Loop
```zig
fn scheduleSSECallback(self: *Connection, loop: *xev.Loop, callback: SSEStreamCallback, writer: *SSEWriter) !void {
    // Package the callback and writer together
    const task = try self.allocator.create(SSECallbackTask);
    task.* = .{
        .callback = callback,      // The function pointer
        .writer = writer,          // The ready SSE writer
        .connection = self,
    };
    
    // Tell libxev to run this on the next tick
    var c: xev.Completion = .{
        .op = .{ .timer = .{ .ns = 0 } },  // Run immediately (0 nanoseconds)
        .userdata = task,                   // Our packaged data
        .callback = executeSSECallback,     // libxev will call this
    };
    loop.add(&c);
}
```

### Step 4: Event Loop Executes
```zig
fn executeSSECallback(userdata: ?*anyopaque, loop: *xev.Loop, c: *xev.Completion, result: xev.Timer.RunError!void) xev.CallbackAction {
    const task = @as(*SSECallbackTask, @ptrCast(@alignCast(userdata.?)));
    
    // Now call the user's streaming function with the ready writer!
    task.callback(task.writer) catch |err| {
        std.log.err("SSE callback error: {}", .{err});
        task.writer.close();
    };
    
    return .disarm;  // Tell libxev we're done
}
```

### Step 5: User's Function Runs
```zig
fn streamCounter(writer: *SSEWriter) !void {
    // This runs in the libxev event loop context
    // The writer is ready and connected!
    defer writer.close();
    
    var counter: u32 = 0;
    while (counter < 30) {
        try writer.sendEvent(.{ .data = "..." });
        std.time.sleep(1 * std.time.ns_per_s);
        counter += 1;
    }
}
```

## Key Points

1. **Function Pointer Storage**: The callback is just a function pointer stored in H3Event
2. **Deferred Execution**: libxev runs it after the connection is ready
3. **Event Loop Context**: The callback runs inside libxev's event loop
4. **Non-blocking**: The original handler has already returned
5. **Error Isolation**: Errors in the callback don't affect the request handling

## Why Use the Event Loop?

We use libxev's timer with 0 nanoseconds to:
- Ensure the callback runs after the current operation completes
- Keep the execution in the proper event loop context
- Allow libxev to manage the execution timing
- Maintain non-blocking behavior

## Memory Management

The task structure is:
1. Allocated before scheduling
2. Passed to libxev as userdata
3. Freed after the callback executes
4. The writer is managed by the callback (hence the `defer writer.close()`)

This approach integrates cleanly with libxev's existing event-driven architecture!