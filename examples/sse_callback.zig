//! SSE Callback Example
//! Demonstrates a potential callback-based approach for SSE

const std = @import("std");
const h3z = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create app using legacy API
    var app = try h3z.H3.init(allocator);
    defer app.deinit();

    // SSE endpoint
    _ = app.get("/events", sseHandler);
    
    // HTML page
    _ = app.get("/", htmlHandler);

    // Start server
    std.log.info("SSE Callback example starting on http://localhost:3000", .{});
    std.log.info("This example demonstrates the timing issue with SSE", .{});
    
    try h3z.serve(&app, h3z.ServeOptions{
        .port = 3000,
        .host = "127.0.0.1",
    });
}

/// SSE handler that demonstrates the timing issue
fn sseHandler(event: *h3z.Event) !void {
    std.log.info("SSE handler called", .{});
    
    // Start SSE mode
    try event.startSSE();
    std.log.info("SSE mode started", .{});
    
    // Try to get writer immediately (this will fail)
    const writer = event.getSSEWriter() catch |err| {
        std.log.info("Expected error: {s}", .{@errorName(err)});
        std.log.info("The adapter hasn't set up the connection yet", .{});
        
        // In a real implementation, we would need either:
        // 1. A callback mechanism where the adapter calls us back
        // 2. An async handler that can yield until the writer is ready
        // 3. A different architecture where startSSE() blocks until ready
        
        return;
    };
    
    // This code is unreachable with the current architecture
    defer writer.close();
    
    try writer.sendEvent(h3z.SSEEvent{
        .data = "This message will never be sent",
        .event = "test",
    });
}

/// Serve HTML page
fn htmlHandler(event: *h3z.Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>H3Z SSE Timing Issue Demo</title>
        \\    <style>
        \\        body { 
        \\            font-family: Arial, sans-serif; 
        \\            margin: 40px;
        \\            max-width: 800px;
        \\            margin: 0 auto;
        \\            padding: 40px;
        \\        }
        \\        .info {
        \\            background: #f0f8ff;
        \\            border: 2px solid #4169e1;
        \\            padding: 20px;
        \\            border-radius: 8px;
        \\            margin: 20px 0;
        \\        }
        \\        .log {
        \\            background: #f5f5f5;
        \\            border: 1px solid #ddd;
        \\            padding: 10px;
        \\            margin: 10px 0;
        \\            font-family: monospace;
        \\            white-space: pre-wrap;
        \\        }
        \\        button {
        \\            font-size: 18px;
        \\            padding: 10px 20px;
        \\            margin: 10px;
        \\            cursor: pointer;
        \\        }
        \\    </style>
        \\</head>
        \\<body>
        \\    <h1>H3Z SSE Timing Issue Demonstration</h1>
        \\    
        \\    <div class="info">
        \\        <h2>Current Architecture Issue</h2>
        \\        <p>The SSE implementation has a timing issue:</p>
        \\        <ol>
        \\            <li>Handler calls <code>startSSE()</code></li>
        \\            <li>Handler tries to get SSE writer (fails - not ready yet)</li>
        \\            <li>Handler returns</li>
        \\            <li>Adapter sets up SSE connection (too late!)</li>
        \\        </ol>
        \\        <p>Click the button below to see this in action. Check the server logs.</p>
        \\    </div>
        \\    
        \\    <button id="test">Test SSE Connection</button>
        \\    
        \\    <div id="logs"></div>
        \\    
        \\    <div class="info">
        \\        <h2>Proposed Solutions</h2>
        \\        <ol>
        \\            <li><strong>Async Handlers</strong>: Allow handlers to suspend/resume</li>
        \\            <li><strong>Callback API</strong>: Add event.setSSECallback(fn)</li>
        \\            <li><strong>Blocking Setup</strong>: Make startSSE() block until ready</li>
        \\        </ol>
        \\    </div>
        \\    
        \\    <script>
        \\        const logsDiv = document.getElementById('logs');
        \\        
        \\        function addLog(message) {
        \\            const log = document.createElement('div');
        \\            log.className = 'log';
        \\            log.textContent = new Date().toISOString() + ' - ' + message;
        \\            logsDiv.appendChild(log);
        \\        }
        \\        
        \\        document.getElementById('test').addEventListener('click', () => {
        \\            addLog('Attempting SSE connection...');
        \\            
        \\            const eventSource = new EventSource('/events');
        \\            
        \\            eventSource.onopen = () => {
        \\                addLog('SSE connection opened (headers received)');
        \\            };
        \\            
        \\            eventSource.onmessage = (e) => {
        \\                addLog('Received message: ' + e.data);
        \\            };
        \\            
        \\            eventSource.onerror = (e) => {
        \\                addLog('SSE error - connection will hang because no data is sent');
        \\                eventSource.close();
        \\            };
        \\            
        \\            // Close after 5 seconds
        \\            setTimeout(() => {
        \\                eventSource.close();
        \\                addLog('Closed connection after timeout');
        \\            }, 5000);
        \\        });
        \\    </script>
        \\</body>
        \\</html>
    ;
    
    try event.sendHtml(html);
}