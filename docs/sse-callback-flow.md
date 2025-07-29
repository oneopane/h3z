# SSE Callback Flow Diagram

## Current (Broken) Flow

```
Client                  Handler                 Adapter                 Connection
  |                       |                       |                       |
  |---- GET /events ----->|                       |                       |
  |                       |                       |                       |
  |                       |-- startSSE() -------->|                       |
  |                       |   (sets flags)        |                       |
  |                       |                       |                       |
  |                       |-- getSSEWriter() -X   |                       |
  |                       |   (FAILS - not ready) |                       |
  |                       |                       |                       |
  |                       |-- returns ----------->|                       |
  |                       |                       |                       |
  |                       |                       |-- checks sse_started |
  |                       |                       |-- creates connection ->|
  |                       |                       |-- sends headers ----->|
  |<----------------------------------------------------- Headers -------|
  |                       |                       |                       |
  |                    (handler                   |-- connection ready -->|
  |                     already                   |                       |
  |                     exited!)                  |   (too late!)         |
  |                       |                       |                       |
  |                    [No events sent - connection hangs]               |
```

## Proposed Callback Flow

```
Client                  Handler                 Adapter                 Connection
  |                       |                       |                       |
  |---- GET /events ----->|                       |                       |
  |                       |                       |                       |
  |                       |-- startSSE() -------->|                       |
  |                       |   (sets flags)        |                       |
  |                       |                       |                       |
  |                       |-- setStreamCallback ->|                       |
  |                       |   (registers callback)|                       |
  |                       |                       |                       |
  |                       |-- returns ----------->|                       |
  |                       |                       |                       |
  |                       |                       |-- checks sse_started |
  |                       |                       |-- creates connection ->|
  |                       |                       |-- sends headers ----->|
  |<----------------------------------------------------- Headers -------|
  |                       |                       |                       |
  |                       |                       |-- connection ready -->|
  |                       |                       |                       |
  |                       |                       |-- schedules callback  |
  |                       |                       |                       |
  |                     Callback                  |                       |
  |                       |<-- calls callback ----|                       |
  |                       |    with writer        |                       |
  |                       |                       |                       |
  |                       |-- sendEvent() ------->|------- data -------->|
  |<----------------------------------------------------- Event 1 -------|
  |                       |                       |                       |
  |                       |-- sendEvent() ------->|------- data -------->|
  |<----------------------------------------------------- Event 2 -------|
  |                       |                       |                       |
  |                       |-- close() ----------->|------- close ------->|
  |<----------------------------------------------------- Connection closed
```

## Key Differences

### Current Approach
1. Handler tries to stream immediately
2. Writer not available (race condition)
3. Handler exits without sending data
4. Connection setup happens too late

### Callback Approach
1. Handler registers callback and exits
2. Adapter sets up connection properly
3. Adapter calls callback with ready writer
4. Callback streams data successfully

## Code Example Side-by-Side

### Current (Broken)
```zig
fn handler(event: *H3Event) !void {
    try event.startSSE();
    
    // This always fails because adapter hasn't set up connection yet
    const writer = event.getSSEWriter() catch {
        std.log.err("Writer not ready!", .{});
        return; // Exit without streaming
    };
    
    // This code never runs
    try writer.sendEvent(...);
}
```

### Proposed (Working)
```zig
fn handler(event: *H3Event) !void {
    try event.startSSE();
    event.setStreamCallback(doStreaming);
    // Handler exits cleanly
}

fn doStreaming(writer: *SSEWriter) !void {
    // This runs after connection is ready
    defer writer.close();
    
    // Now we can stream successfully
    try writer.sendEvent(...);
    
    // Long-running streaming loop
    while (condition) {
        try writer.sendEvent(...);
        std.time.sleep(...);
    }
}
```

## Implementation Complexity

### Minimal Changes Required:
1. **H3Event**: Add 2 fields, 1 method (~10 lines)
2. **Adapter**: Add callback scheduling (~50 lines)
3. **Examples**: Update to use callbacks (~same LOC, different structure)

### No Breaking Changes:
- Existing non-SSE endpoints work unchanged
- SSE infrastructure remains the same
- Only the handler pattern changes for SSE endpoints

## Error Handling

The callback approach also improves error handling:

```zig
fn streamCallback(writer: *SSEWriter) !void {
    defer writer.close();
    
    // Errors here don't crash the server
    errdefer std.log.err("SSE streaming failed", .{});
    
    // Can implement retry logic
    var retries: u32 = 0;
    while (retries < 3) {
        sendData(writer) catch |err| {
            std.log.warn("Send failed: {}, retry {}/3", .{err, retries + 1});
            retries += 1;
            std.time.sleep(100 * std.time.ns_per_ms);
            continue;
        };
        break;
    }
}
```