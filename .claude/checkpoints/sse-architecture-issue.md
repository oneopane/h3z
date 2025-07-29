# SSE Architecture Issue Analysis
Generated: 2025-01-29

## Issue Summary
The H3Z SSE implementation is structurally complete but has a fundamental timing issue that prevents it from working properly.

## Root Cause
The current request/response model doesn't support long-lived streaming connections:

1. **Handler Lifecycle**: Handlers must return immediately after processing
2. **Adapter Timing**: The adapter sets up SSE connections AFTER the handler returns
3. **Writer Availability**: `getSSEWriter()` always fails because the connection isn't ready yet

## Current Flow
```
1. Client requests /events
2. Handler called
3. Handler calls startSSE() - sets flags, adds headers
4. Handler tries getSSEWriter() - FAILS (ConnectionNotReady)
5. Handler returns
6. Adapter sees sse_started flag
7. Adapter creates streaming connection
8. Adapter sends SSE headers
9. Connection stays open but no events are sent (handler already exited)
```

## Evidence
From the logs:
```
error: Failed to get SSE writer after 10 attempts
debug: SSE mode detected, setting up streaming connection
debug: SSE headers sent, 124 bytes
```

## Architectural Solutions

### Option 1: Async/Await Handler Support
```zig
fn sseHandler(event: *H3Event) !void {
    try event.startSSE();
    const writer = try event.awaitSSEWriter(); // Suspend until ready
    defer writer.close();
    
    // Now we can stream
    while (streaming) {
        try writer.sendEvent(...);
        try event.yield(); // Let other connections process
    }
}
```

### Option 2: Callback-Based Streaming
```zig
fn sseHandler(event: *H3Event) !void {
    try event.startSSE();
    event.setStreamCallback(streamCallback);
    // Handler returns, adapter calls callback when ready
}

fn streamCallback(writer: *SSEWriter) !void {
    defer writer.close();
    // Stream events here
}
```

### Option 3: Blocking Connection Setup
```zig
fn sseHandler(event: *H3Event) !void {
    const writer = try event.startSSEBlocking(); // Blocks until connection ready
    defer writer.close();
    
    // Stream events
}
```

## Implementation Status
- ✅ Core SSE module (W3C compliant formatting)
- ✅ SSE writer abstraction
- ✅ Adapter SSE support (libxev & std)
- ✅ Tests (unit, integration, performance)
- ✅ Example implementations
- ❌ Handler lifecycle support for streaming

## Files Created
- `examples/sse_counter.zig` - Counter demo (shows timing issue)
- `examples/sse_text.zig` - Text streaming demo (shows timing issue)
- `examples/sse_callback.zig` - Demonstrates the architectural problem

## Next Steps
1. Choose an architectural approach (recommend Option 2 for simplicity)
2. Modify H3Event to support streaming callbacks
3. Update adapters to invoke callbacks after connection setup
4. Update examples to use the new API
5. Add tests for the new streaming lifecycle