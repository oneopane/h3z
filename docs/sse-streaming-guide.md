# Server-Sent Events (SSE) Streaming Guide

## Overview

This guide covers the implementation of Server-Sent Events (SSE) in H3Z, enabling real-time streaming capabilities for applications like LLM chat interfaces, live data feeds, and progress notifications.

## What is SSE?

Server-Sent Events is a standard that enables servers to push data to web clients over HTTP. Unlike WebSockets, SSE is:
- **Unidirectional**: Server-to-client only
- **Simple**: Uses regular HTTP, no special protocol
- **Auto-reconnecting**: Built-in reconnection handling
- **Text-based**: UTF-8 encoded messages

## Architecture Design

### Core Components

1. **SSEEvent Structure**: Represents a single SSE message
2. **SSEWriter**: Manages the streaming connection and event formatting
3. **Connection Abstraction**: Unified interface for different server adapters
4. **H3Event Extension**: New `startSSE()` method to initiate streaming

### Component Interaction

```
Client Request → H3Event → startSSE() → SSEWriter
                                            ↓
                                     Connection Interface
                                            ↓
                                    Server Adapter (libxev/std)
                                            ↓
                                        TCP Socket
```

## SSE Message Format

Each SSE message consists of:
- `data:` - The message payload (required)
- `event:` - Event type name (optional)
- `id:` - Event ID for reconnection (optional)
- `retry:` - Reconnection delay in ms (optional)

Example:
```
event: token
id: 123
data: {"content": "Hello"}

event: done
data: {"finished": true}

```

## API Design

### Starting SSE Stream

```zig
pub fn handleSSE(event: *H3Event) !void {
    const sse = try event.startSSE();
    defer sse.close();
    
    // Send events
    try sse.sendEvent(.{
        .data = "Hello, world!",
        .event = "greeting",
    });
}
```

### Sending Different Event Types

```zig
// Simple text message
try sse.sendEvent(.{ .data = "Simple message" });

// JSON data with event type
const json_data = try std.json.stringifyAlloc(allocator, .{
    .temperature = 23.5,
    .humidity = 65,
}, .{});
defer allocator.free(json_data);

try sse.sendEvent(.{
    .data = json_data,
    .event = "sensor-update",
    .id = "12345",
});

// Multi-line data
try sse.sendEvent(.{
    .data = "Line 1\nLine 2\nLine 3",
    .event = "multiline",
});
```

## Implementation Details

### Memory Management

- SSEWriter uses the event's allocator for all allocations
- Event formatting uses temporary buffers that are freed after sending
- Connection keeps write queues for chunked transmission
- Proper cleanup on connection close

### Error Handling

Common errors and their handling:
- `ConnectionClosed`: Attempting to write after close
- `ResponseAlreadySent`: Starting SSE after regular response
- `WriteError`: Network transmission failures
- `AllocationError`: Memory allocation failures

### Performance Considerations

1. **Zero-Copy Where Possible**: Direct writes to connection when feasible
2. **Buffering**: Intelligent buffering for small events
3. **Backpressure**: Write queue management in adapters
4. **Connection Pooling**: Reuse connections for multiple SSE sessions

## Use Cases

### LLM Chat Streaming

```zig
pub fn handleChatStream(event: *H3Event) !void {
    const request = try event.readJson(ChatRequest);
    const sse = try event.startSSE();
    defer sse.close();
    
    var llm = LLMClient.init(allocator);
    defer llm.deinit();
    
    const stream = try llm.chat(request.messages);
    while (try stream.next()) |token| {
        try sse.sendEvent(.{
            .data = try std.json.stringifyAlloc(allocator, .{
                .token = token,
                .finished = false,
            }, .{}),
            .event = "token",
        });
    }
    
    try sse.sendEvent(.{
        .data = "{\"finished\": true}",
        .event = "done",
    });
}
```

### Live Progress Updates

```zig
pub fn handleLongTask(event: *H3Event) !void {
    const sse = try event.startSSE();
    defer sse.close();
    
    const task = LongRunningTask.init();
    
    while (task.step()) |progress| {
        try sse.sendEvent(.{
            .data = try std.fmt.allocPrint(allocator, 
                "{{\"progress\": {d}, \"status\": \"{s}\"}}",
                .{ progress.percent, progress.status }
            ),
            .event = "progress",
        });
    }
    
    try sse.sendEvent(.{
        .data = "{\"complete\": true}",
        .event = "complete",
    });
}
```

### Proxy/Relay Pattern

```zig
pub fn handleSSEProxy(event: *H3Event) !void {
    const sse = try event.startSSE();
    defer sse.close();
    
    // Connect to upstream SSE source
    var upstream = try SSEClient.connect(UPSTREAM_URL);
    defer upstream.close();
    
    // Relay events with optional transformation
    while (try upstream.readEvent()) |upstream_event| {
        // Transform/filter as needed
        const transformed_data = try transformData(upstream_event.data);
        
        try sse.sendEvent(.{
            .data = transformed_data,
            .event = upstream_event.event,
            .id = upstream_event.id,
        });
    }
}
```

## Client-Side JavaScript

```javascript
const eventSource = new EventSource('/api/stream');

eventSource.addEventListener('token', (event) => {
    const data = JSON.parse(event.data);
    console.log('Received token:', data.token);
});

eventSource.addEventListener('done', (event) => {
    console.log('Stream complete');
    eventSource.close();
});

eventSource.onerror = (error) => {
    console.error('SSE error:', error);
    eventSource.close();
};
```

## Testing SSE Endpoints

```bash
# Using curl
curl -N -H "Accept: text/event-stream" http://localhost:3000/api/stream

# Expected output:
# event: token
# data: {"token": "Hello"}
# 
# event: token
# data: {"token": " world"}
# 
# event: done
# data: {"finished": true}
```

## Security Considerations

1. **Authentication**: Validate auth tokens before starting SSE
2. **Rate Limiting**: Limit concurrent SSE connections per client
3. **Timeouts**: Implement idle connection timeouts
4. **Resource Limits**: Cap memory usage for write queues
5. **CORS**: Configure appropriate CORS headers for SSE endpoints

## Troubleshooting

### Common Issues

1. **Events not received**: Check for proxy buffering (X-Accel-Buffering header)
2. **Connection drops**: Verify keep-alive settings
3. **Memory growth**: Ensure proper cleanup of completed streams
4. **Client reconnection storms**: Implement exponential backoff

### Debug Logging

Enable SSE debug logging:
```zig
const log = std.log.scoped(.sse);
log.debug("Sending event: {s}", .{event.data});
```

## Migration Guide

For existing H3Z applications, adding SSE support:

1. Update to latest H3Z version with SSE support
2. No changes needed to existing endpoints
3. New SSE endpoints use `event.startSSE()`
4. Existing middleware continues to work
5. Performance impact is minimal for non-SSE routes

## Best Practices

1. **Set appropriate timeouts** for long-running streams
2. **Use event types** to distinguish different message types
3. **Include event IDs** for reconnection support
4. **Send heartbeat events** to detect stale connections
5. **Compress large payloads** when possible
6. **Implement graceful shutdown** for active streams
7. **Monitor connection count** and resource usage

## References

- [W3C SSE Specification](https://www.w3.org/TR/eventsource/)
- [MDN EventSource API](https://developer.mozilla.org/en-US/docs/Web/API/EventSource)
- [H3Z Documentation](../README.md)