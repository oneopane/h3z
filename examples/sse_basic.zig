//! Basic SSE (Server-Sent Events) example
//! Demonstrates streaming server-to-client events

const std = @import("std");
const h3z = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create app using legacy API for now
    var app = try h3z.H3.init(allocator);
    defer app.deinit();

    // SSE endpoint that streams characters from a string
    _ = app.get("/stream", streamHandler);
    
    // HTML page to test SSE
    _ = app.get("/", htmlHandler);

    // Start server
    std.log.info("SSE example server starting on http://localhost:3000", .{});
    std.log.info("Visit http://localhost:3000 to see SSE in action", .{});
    
    try h3z.serve(&app, h3z.ServeOptions{
        .port = 3000,
        .host = "127.0.0.1",
    });
}

/// Handler that streams characters from a fixed string
fn streamHandler(event: *h3z.Event) !void {
    // The fixed string to stream
    const message = "Hello, World! This is a Server-Sent Events demo streaming one character at a time.";
    
    // Start SSE mode
    try event.startSSE();
    
    // Get the SSE writer
    const writer = event.getSSEWriter() catch {
        std.log.info("SSE started but writer not yet available", .{});
        return;
    };
    defer writer.close();
    
    // Stream each character
    for (message, 0..) |char, index| {
        const char_data = try std.fmt.allocPrint(event.allocator, "{c}", .{char});
        defer event.allocator.free(char_data);
        
        const id = try std.fmt.allocPrint(event.allocator, "{d}", .{index});
        defer event.allocator.free(id);
        
        try writer.sendEvent(h3z.SSEEvent{
            .data = char_data,
            .event = "char",
            .id = id,
        });
        
        // Small delay between characters for visual effect
        std.time.sleep(50 * std.time.ns_per_ms);
    }
    
    // Send completion event
    try writer.sendEvent(h3z.SSEEvent{
        .data = "Stream complete!",
        .event = "done",
    });
}

/// Serve HTML page with JavaScript SSE client
fn htmlHandler(event: *h3z.Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>H3Z SSE Example</title>
        \\    <style>
        \\        body { font-family: Arial, sans-serif; margin: 40px; }
        \\        #events { 
        \\            border: 1px solid #ccc; 
        \\            padding: 20px; 
        \\            height: 300px; 
        \\            overflow-y: scroll;
        \\            background: #f5f5f5;
        \\        }
        \\        .event { 
        \\            margin: 10px 0; 
        \\            padding: 10px;
        \\            background: white;
        \\            border-radius: 4px;
        \\        }
        \\        .counter { color: #007bff; }
        \\        .done { color: #28a745; font-weight: bold; }
        \\        .error { color: #dc3545; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <h1>H3Z Server-Sent Events Example</h1>
        \\    <p>This example demonstrates real-time server-to-client streaming using SSE.</p>
        \\    
        \\    <button id="start">Start Events</button>
        \\    <button id="stop" disabled>Stop Events</button>
        \\    
        \\    <h2>Events:</h2>
        \\    <div id="events"></div>
        \\    
        \\    <script>
        \\        let eventSource = null;
        \\        const eventsDiv = document.getElementById('events');
        \\        const startBtn = document.getElementById('start');
        \\        const stopBtn = document.getElementById('stop');
        \\        
        \\        function addEvent(message, type = '') {
        \\            const eventDiv = document.createElement('div');
        \\            eventDiv.className = 'event ' + type;
        \\            eventDiv.textContent = message;
        \\            eventsDiv.appendChild(eventDiv);
        \\            eventsDiv.scrollTop = eventsDiv.scrollHeight;
        \\        }
        \\        
        \\        startBtn.addEventListener('click', () => {
        \\            eventsDiv.innerHTML = '';
        \\            addEvent('Connecting to SSE endpoint...');
        \\            
        \\            eventSource = new EventSource('/events');
        \\            
        \\            eventSource.addEventListener('counter', (e) => {
        \\                addEvent(`Counter: ${e.data}`, 'counter');
        \\            });
        \\            
        \\            eventSource.addEventListener('done', (e) => {
        \\                addEvent('Stream complete!', 'done');
        \\                eventSource.close();
        \\                startBtn.disabled = false;
        \\                stopBtn.disabled = true;
        \\            });
        \\            
        \\            eventSource.onerror = (e) => {
        \\                addEvent('Connection error!', 'error');
        \\                eventSource.close();
        \\                startBtn.disabled = false;
        \\                stopBtn.disabled = true;
        \\            };
        \\            
        \\            startBtn.disabled = true;
        \\            stopBtn.disabled = false;
        \\        });
        \\        
        \\        stopBtn.addEventListener('click', () => {
        \\            if (eventSource) {
        \\                eventSource.close();
        \\                addEvent('Connection closed by user');
        \\            }
        \\            startBtn.disabled = false;
        \\            stopBtn.disabled = true;
        \\        });
        \\    </script>
        \\</body>
        \\</html>
    ;
    
    try event.sendHtml(html);
}