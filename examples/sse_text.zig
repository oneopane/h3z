//! SSE Text Streaming Example
//! Demonstrates streaming text one character at a time via Server-Sent Events

const std = @import("std");
const h3z = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create app using legacy API
    var app = try h3z.H3.init(allocator);
    defer app.deinit();

    // SSE endpoint that streams text
    _ = app.get("/stream", textStreamHandler);
    
    // HTML page to display the streamed text
    _ = app.get("/", htmlHandler);

    // Start server
    std.log.info("SSE Text Streaming example starting on http://localhost:3000", .{});
    std.log.info("Visit http://localhost:3000 to see text streaming", .{});
    
    try h3z.serve(&app, h3z.ServeOptions{
        .port = 3000,
        .host = "127.0.0.1",
    });
}

/// Handler that streams text character by character
fn textStreamHandler(event: *h3z.Event) !void {
    // The text to stream
    const message = "Hello, World! This is a Server-Sent Events demo streaming one character at a time. Watch as each character appears with a slight delay for dramatic effect!";
    
    // Start SSE mode
    try event.startSSE();
    
    // Try to get the writer with a small delay to allow adapter setup
    var attempts: u32 = 0;
    var writer: ?*h3z.SSEWriter = null;
    
    while (attempts < 10) : (attempts += 1) {
        writer = event.getSSEWriter() catch |err| switch (err) {
            error.ConnectionNotReady => {
                // Wait a bit for the adapter to set up the connection
                std.time.sleep(10 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        };
        break;
    }
    
    if (writer == null) {
        std.log.err("Failed to get SSE writer after 10 attempts", .{});
        return;
    }
    
    const sse_writer = writer.?;
    defer sse_writer.close();
    
    // Stream each character
    for (message, 0..) |char, index| {
        var char_buffer: [1]u8 = .{char};
        var id_buffer: [32]u8 = undefined;
        const id_str = try std.fmt.bufPrint(&id_buffer, "{d}", .{index});
        
        try sse_writer.sendEvent(h3z.SSEEvent{
            .data = &char_buffer,
            .event = "char",
            .id = id_str,
        });
        
        // Small delay between characters for visual effect
        std.time.sleep(50 * std.time.ns_per_ms);
    }
    
    // Send completion event
    try sse_writer.sendEvent(h3z.SSEEvent{
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
        \\    <title>H3Z SSE Text Streaming Example</title>
        \\    <style>
        \\        body { 
        \\            font-family: Arial, sans-serif; 
        \\            margin: 40px;
        \\            max-width: 800px;
        \\            margin: 0 auto;
        \\            padding: 40px;
        \\        }
        \\        #text-container { 
        \\            font-size: 24px;
        \\            line-height: 1.6;
        \\            margin: 40px 0;
        \\            padding: 20px;
        \\            border: 2px solid #007bff;
        \\            border-radius: 8px;
        \\            min-height: 150px;
        \\            background: #f8f9fa;
        \\            word-wrap: break-word;
        \\        }
        \\        .cursor {
        \\            display: inline-block;
        \\            width: 3px;
        \\            height: 30px;
        \\            background: #007bff;
        \\            animation: blink 1s infinite;
        \\            vertical-align: text-bottom;
        \\            margin-left: 2px;
        \\        }
        \\        @keyframes blink {
        \\            0%, 50% { opacity: 1; }
        \\            51%, 100% { opacity: 0; }
        \\        }
        \\        #status {
        \\            margin: 20px 0;
        \\            padding: 10px;
        \\            border-radius: 4px;
        \\            text-align: center;
        \\        }
        \\        .ready { 
        \\            background: #d4edda; 
        \\            color: #155724;
        \\        }
        \\        .streaming { 
        \\            background: #cce5ff; 
        \\            color: #004085;
        \\        }
        \\        .complete { 
        \\            background: #d1ecf1; 
        \\            color: #0c5460;
        \\        }
        \\        .error {
        \\            background: #f8d7da;
        \\            color: #721c24;
        \\        }
        \\        button {
        \\            font-size: 18px;
        \\            padding: 10px 20px;
        \\            margin: 10px;
        \\            cursor: pointer;
        \\            border: none;
        \\            border-radius: 4px;
        \\            background: #007bff;
        \\            color: white;
        \\        }
        \\        button:hover {
        \\            background: #0056b3;
        \\        }
        \\        button:disabled {
        \\            background: #6c757d;
        \\            cursor: not-allowed;
        \\        }
        \\    </style>
        \\</head>
        \\<body>
        \\    <h1>H3Z SSE Text Streaming Example</h1>
        \\    <p>Click "Start Streaming" to see text appear one character at a time via Server-Sent Events.</p>
        \\    
        \\    <div id="status" class="ready">Ready to stream</div>
        \\    
        \\    <button id="start">Start Streaming</button>
        \\    <button id="clear">Clear Text</button>
        \\    
        \\    <div id="text-container">
        \\        <span id="text"></span><span class="cursor" id="cursor"></span>
        \\    </div>
        \\    
        \\    <script>
        \\        let eventSource = null;
        \\        const textSpan = document.getElementById('text');
        \\        const statusDiv = document.getElementById('status');
        \\        const startBtn = document.getElementById('start');
        \\        const clearBtn = document.getElementById('clear');
        \\        const cursor = document.getElementById('cursor');
        \\        
        \\        function updateStatus(status, className) {
        \\            statusDiv.textContent = status;
        \\            statusDiv.className = className;
        \\        }
        \\        
        \\        startBtn.addEventListener('click', () => {
        \\            textSpan.textContent = '';
        \\            updateStatus('Connecting...', 'streaming');
        \\            cursor.style.display = 'inline-block';
        \\            
        \\            eventSource = new EventSource('/stream');
        \\            
        \\            eventSource.onopen = () => {
        \\                updateStatus('Streaming text...', 'streaming');
        \\                startBtn.disabled = true;
        \\            };
        \\            
        \\            eventSource.addEventListener('char', (e) => {
        \\                textSpan.textContent += e.data;
        \\            });
        \\            
        \\            eventSource.addEventListener('done', (e) => {
        \\                updateStatus(e.data, 'complete');
        \\                cursor.style.display = 'none';
        \\                eventSource.close();
        \\                startBtn.disabled = false;
        \\            });
        \\            
        \\            eventSource.onerror = (e) => {
        \\                updateStatus('Connection error', 'error');
        \\                cursor.style.display = 'none';
        \\                eventSource.close();
        \\                startBtn.disabled = false;
        \\            };
        \\        });
        \\        
        \\        clearBtn.addEventListener('click', () => {
        \\            textSpan.textContent = '';
        \\            cursor.style.display = 'none';
        \\            updateStatus('Ready to stream', 'ready');
        \\            if (eventSource) {
        \\                eventSource.close();
        \\                startBtn.disabled = false;
        \\            }
        \\        });
        \\    </script>
        \\</body>
        \\</html>
    ;
    
    try event.sendHtml(html);
}