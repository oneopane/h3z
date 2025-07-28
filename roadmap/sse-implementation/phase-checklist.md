# SSE Implementation Phase Checklist

## Phase 1: Core SSE Types and Formatting ✅

### Implementation Tasks
- [x] Create `src/http/sse.zig`
  - [x] Define `SSEEvent` struct
  - [x] Implement `format()` method for event serialization (renamed to `formatEvent()`)
  - [x] Handle multi-line data properly
  - [x] Add builder pattern for convenient event creation

### Code Structure
- [x] SSEEvent with fields: data, event, id, retry
- [x] Formatting follows W3C SSE specification
- [x] Proper handling of newlines in data field
- [x] Memory-efficient string building

### Verification
- [x] Unit tests for SSEEvent formatting
- [x] Test multi-line data handling
- [x] Test optional fields (event, id, retry)
- [x] Verify output matches SSE spec exactly

---

## Phase 2: Connection Abstraction Layer ✅

### Implementation Tasks
- [x] Create `src/server/connection.zig`
  - [x] Define `Connection` interface as tagged union:
    ```zig
    pub const Connection = union(enum) {
        libxev: *LibxevConnection,
        std: *StdConnection,
    };
    ```
  - [x] Add `writeChunk` method:
    ```zig
    pub fn writeChunk(self: Connection, data: []const u8) ConnectionError!void
    ```
  - [x] Add `flush` method for immediate transmission:
    ```zig
    pub fn flush(self: Connection) ConnectionError!void
    ```
  - [x] Add `close` method:
    ```zig
    pub fn close(self: Connection) void
    ```
  - [x] Add `isAlive` method for connection status:
    ```zig
    pub fn isAlive(self: Connection) bool
    ```

### Error Set Definition
```zig
pub const ConnectionError = error{
    ConnectionClosed,
    WriteError,
    BufferFull,
    AllocationError,
    NotStreamingMode,
};
```

### Connection Capabilities
- [x] Track streaming mode state (SSE vs regular HTTP)
- [x] Implement write buffering with configurable size (8KB default)
- [x] Support partial write handling
- [x] Backpressure detection via `BufferFull` error
- [x] Connection lifecycle: init → streaming → closing → closed

### Verification
- [x] Interface compiles without errors
- [x] Both adapters can implement the interface
- [x] Error handling covers all failure modes
- [x] Documentation includes usage examples
- [x] Memory safety validated with test allocator

---

## Phase 3: Adapter Modifications ⏳

### LibXev Adapter Tasks
- [ ] Modify `src/server/adapters/libxev.zig`
  - [ ] Add `LibxevConnection` struct:
    ```zig
    pub const LibxevConnection = struct {
        tcp: xev.TCP,
        write_queue: std.ArrayList([]const u8),
        write_completion: xev.Completion,
        streaming_mode: bool = false,
        closed: bool = false,
    };
    ```
  - [ ] Implement `writeChunk`:
    - Queue data if write in progress
    - Initiate async write via `tcp.write()`
    - Handle `EAGAIN`/`EWOULDBLOCK`
  - [ ] Implement `flush` to force immediate transmission
  - [ ] Modify `onWriteCallback` to:
    - Check for queued writes
    - Keep connection alive if `streaming_mode = true`
    - Skip normal connection close logic
  - [ ] Add backpressure: limit queue to 64KB

### Std Adapter Tasks
- [ ] Modify `src/server/adapters/std.zig`
  - [ ] Add `StdConnection` struct:
    ```zig
    pub const StdConnection = struct {
        stream: std.net.Stream,
        write_buffer: [8192]u8,
        buffer_len: usize = 0,
        streaming_mode: bool = false,
        closed: bool = false,
    };
    ```
  - [ ] Implement `writeChunk`:
    - Buffer small writes
    - Direct write for large chunks
    - Handle partial writes with retry loop
  - [ ] Implement `flush` using `stream.writeAll()`
  - [ ] Keep connection alive:
    - Skip `stream.close()` when streaming
    - Only close on explicit `close()` call
  - [ ] Simple backpressure: block on full buffer

### Connection Factory Methods
- [ ] LibxevAdapter adds `createConnection() !*Connection`
- [ ] StdAdapter adds `createConnection() !*Connection`
- [ ] Both return Connection union with proper variant

### Memory Management
- [ ] Write queues use connection's allocator
- [ ] Proper cleanup in connection `deinit()`
- [ ] No allocations during normal write operations
- [ ] Queue items freed after successful transmission

### Verification
- [ ] Both adapters compile with new interface
- [ ] Write operations handle all sizes correctly
- [ ] Connections stay alive during streaming
- [ ] Memory leak tests pass with TestAllocator
- [ ] Error propagation works correctly
- [ ] Concurrent connections supported

---

## Phase 4: H3Event SSE Integration ⏳

### H3Event Modifications
- [ ] Modify `src/core/event.zig`
  - [ ] Add SSE state tracking:
    ```zig
    sse_started: bool = false,
    response_sent: bool = false,
    ```
  - [ ] Add `startSSE()` method:
    ```zig
    pub fn startSSE(self: *H3Event) SSEError!*SSEWriter {
        if (self.response_sent) return error.ResponseAlreadySent;
        if (self.sse_started) return error.SSEAlreadyStarted;
        
        // Set SSE headers
        try self.response.headers.put("Content-Type", "text/event-stream");
        try self.response.headers.put("Cache-Control", "no-cache");
        try self.response.headers.put("Connection", "keep-alive");
        try self.response.headers.put("X-Accel-Buffering", "no");
        
        // Send headers immediately
        try self.sendHeaders();
        self.sse_started = true;
        
        return SSEWriter.init(self.allocator, self.connection);
    }
    ```

### SSEWriter Implementation
- [ ] Add to `src/http/sse.zig`:
  ```zig
  pub const SSEWriter = struct {
      allocator: std.mem.Allocator,
      connection: *Connection,
      closed: bool = false,
      event_count: usize = 0,
      
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
          try self.connection.flush();
          self.event_count += 1;
      }
      
      pub fn close(self: *SSEWriter) void {
          if (!self.closed) {
              self.connection.close();
              self.closed = true;
          }
      }
  };
  ```

### SSE Error Set
```zig
pub const SSEError = error{
    ResponseAlreadySent,
    SSEAlreadyStarted,
    WriterClosed,
    ConnectionLost,
    BackpressureDetected,
    WriteError,
    AllocationError,
};
```

### Integration Requirements
- [ ] Prevent `sendResponse()` after `startSSE()`
- [ ] Middleware can detect SSE mode via `event.sse_started`
- [ ] Connection automatically enters streaming mode
- [ ] Proper cleanup on early client disconnect

### Verification
- [ ] Cannot send regular response after SSE start
- [ ] Headers sent immediately on startSSE()
- [ ] Events transmitted with low latency
- [ ] Connection stays open between events
- [ ] Memory usage stable over time
- [ ] Graceful handling of client disconnect

---

## Phase 5: Testing and Examples ⏳

### Unit Tests
- [ ] Create `tests/unit/sse_test.zig`
  - [ ] Test SSEEvent formatting:
    ```zig
    test "SSEEvent formats single-line data correctly" {}
    test "SSEEvent handles multi-line data with proper escaping" {}
    test "SSEEvent includes optional fields when present" {}
    test "SSEEvent handles empty data field" {}
    ```
  - [ ] Test SSEWriter functionality:
    ```zig
    test "SSEWriter sends events to connection" {}
    test "SSEWriter handles connection errors gracefully" {}
    test "SSEWriter prevents writes after close" {}
    test "SSEWriter tracks event count correctly" {}
    ```
  - [ ] Test error conditions:
    ```zig
    test "startSSE fails if response already sent" {}
    test "sendEvent returns error on closed connection" {}
    test "sendEvent handles backpressure correctly" {}
    test "close is idempotent" {}
    ```
  - [ ] Test memory management:
    ```zig
    test "No memory leaks in event formatting" {}
    test "SSEWriter cleanup releases all memory" {}
    test "Connection buffers properly freed" {}
    ```

### Integration Tests
- [ ] Create `tests/integration/sse_test.zig`
  - [ ] Test full SSE flow with server:
    ```zig
    test "Client receives SSE events correctly" {}
    test "Headers prevent proxy buffering" {}
    test "Connection stays alive between events" {}
    ```
  - [ ] Test long-running connections:
    ```zig
    test "Stream remains stable for 1 hour" {}
    test "Memory usage constant over 100K events" {}
    test "No connection timeout with heartbeat" {}
    ```
  - [ ] Test concurrent SSE connections:
    ```zig
    test "Handle 1000 concurrent SSE streams" {}
    test "Fair bandwidth distribution" {}
    test "Independent connection lifecycle" {}
    ```
  - [ ] Test error recovery:
    ```zig
    test "Client disconnect detected promptly" {}
    test "Write errors don't crash server" {}
    test "Graceful shutdown closes all streams" {}
    test "Network interruption handling" {}
    ```
  - [ ] Test both adapters:
    ```zig
    test "LibxevAdapter SSE functionality" {}
    test "StdAdapter SSE functionality" {}
    test "Consistent behavior across adapters" {}
    ```

### Examples
- [ ] Create `examples/sse_basic.zig`
  - [ ] Simple counter that streams numbers:
    ```zig
    // Send incrementing number every second
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try sse.sendEvent(.{
            .data = try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .event = "counter",
        });
        std.time.sleep(std.time.ns_per_s);
    }
    ```
  
- [ ] Create `examples/sse_chat.zig`
  - [ ] Simulated LLM token streaming:
    ```zig
    const tokens = [_][]const u8{"Hello", " world", "!", " How", " can", " I", " help?"};
    for (tokens) |token| {
        try sse.sendEvent(.{
            .data = try std.json.stringify(.{ .token = token }, .{}, writer),
            .event = "token",
            .id = try std.fmt.allocPrint(allocator, "{d}", .{index}),
        });
        std.time.sleep(100 * std.time.ns_per_ms); // 100ms delay
    }
    try sse.sendEvent(.{ .data = "{\"finished\": true}", .event = "done" });
    ```
  
- [ ] Create `examples/sse_proxy.zig`
  - [ ] Demonstrates event transformation:
    ```zig
    // Transform temperature from Celsius to Fahrenheit
    const celsius = try parseTemperature(upstream_event.data);
    const fahrenheit = (celsius * 9.0 / 5.0) + 32.0;
    try sse.sendEvent(.{
        .data = try std.fmt.allocPrint(allocator, "{d:.1}F", .{fahrenheit}),
        .event = upstream_event.event,
    });
    ```

### Performance Testing
- [ ] Benchmark event throughput:
  - Target: 10,000+ events/second per connection
  - Test with 1KB, 4KB, and 16KB event sizes
  - Measure latency: p50 < 1ms, p99 < 10ms
- [ ] Test memory usage over time:
  - Baseline memory per connection: < 16KB
  - No growth over 1 million events
  - Write queue memory capped at 64KB
- [ ] Verify no memory leaks:
  - Run with GeneralPurposeAllocator in debug mode
  - Test connection lifecycle 10,000 times
  - Monitor for unreleased allocations
- [ ] Test with many concurrent connections:
  - 1,000 concurrent SSE connections
  - 10,000 total connections (SSE + regular)
  - CPU usage < 80% on 4-core system
  - Network throughput > 1 Gbps

### Documentation Updates
- [ ] Update main README with SSE section
- [ ] Add SSE examples to documentation
- [ ] Update API reference
- [ ] Add troubleshooting guide

### Verification
- [ ] All tests pass
- [ ] Examples run without errors
- [ ] Performance meets targets
- [ ] Documentation is complete
- [ ] No memory leaks detected

---

## Edge Cases and Error Handling ⏳

### Client Disconnection Scenarios
- [ ] **Abrupt disconnect**: TCP RST packet handling
  - Detect via write error (EPIPE/ECONNRESET)
  - Clean up SSEWriter immediately
  - Free all queued writes
- [ ] **Graceful disconnect**: Client closes EventSource
  - Detect via zero-byte read or FIN packet
  - Allow pending writes to complete
  - Clean shutdown of connection
- [ ] **Network timeout**: No ACKs for sent data
  - Implement keep-alive mechanism
  - Send comment lines (`:heartbeat\n\n`) every 30s
  - Close after 3 missed heartbeats

### Backpressure Handling
- [ ] **Write queue full** (>64KB queued):
  - Return `error.BackpressureDetected`
  - Application can choose to:
    - Drop events (lossy stream)
    - Block until space available
    - Close connection
- [ ] **Slow client detection**:
  - Track write completion times
  - Warn if consistently >100ms
  - Implement fair queuing for multiple streams

### Resource Exhaustion
- [ ] **Too many connections**:
  - Limit total SSE connections (configurable)
  - Return 503 Service Unavailable
  - Suggest retry-after header
- [ ] **Memory pressure**:
  - Monitor total write queue memory
  - Implement global memory limit
  - Gracefully degrade under pressure

### Protocol Edge Cases
- [ ] **Large events** (>1MB):
  - Split into multiple chunks
  - Maintain event atomicity
  - Test with 10MB events
- [ ] **Binary data**:
  - Base64 encode if needed
  - Document encoding overhead
  - Provide examples
- [ ] **Unicode handling**:
  - Properly handle UTF-8 sequences
  - Don't split multi-byte characters
  - Test with emoji and CJK text

---

## Final Validation Checklist ✅

### Functionality
- [ ] SSE streams work with curl
- [ ] Browser EventSource connects properly
- [ ] Events are received by clients
- [ ] Long-running streams stay stable
- [ ] Graceful shutdown works

### Performance
- [ ] 10K+ events/second per connection verified
- [ ] Memory usage stays constant (<16KB per connection)
- [ ] CPU usage <20% for 1K connections at 100 events/sec
- [ ] Network efficiency >90% (minimal protocol overhead)
- [ ] Zero-copy path for large events (>4KB)
- [ ] Latency: p99 < 10ms from send to receive

### Compatibility
- [ ] Works with libxev adapter
- [ ] Works with std adapter
- [ ] Existing endpoints unaffected
- [ ] Middleware still functions
- [ ] No breaking changes

### Code Quality
- [ ] All code follows Zig conventions
- [ ] Proper error handling throughout
- [ ] Memory safety guaranteed
- [ ] Documentation is comprehensive
- [ ] Examples are clear and useful

---

## Progress Tracking

Use this section to track overall progress:

- Phase 1: ✅ Complete
- Phase 2: ✅ Complete  
- Phase 3: ⏳ Not Started
- Phase 4: ⏳ Not Started
- Phase 5: ⏳ Not Started

Legend:
- ⏳ Not Started
- 🚧 In Progress
- ✅ Complete
- ❌ Blocked

Last Updated: 2025-07-28 (Enhanced with concrete implementation details)