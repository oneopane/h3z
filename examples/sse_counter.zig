//! SSE Counter Example with Timer-Based Intervals
//! Demonstrates a counter that increments every second via Server-Sent Events using libxev timers

const std = @import("std");
const h3z = @import("h3");
const xev = h3z.xev;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create app using modern component-based API for typed handlers
    var app = try h3z.H3App.init(allocator);
    defer app.deinit();

    // SSE endpoint that streams counter updates with timer-based intervals
    _ = try app.get("/events", timerCounterHandler);
    
    // HTML page to display the counter
    _ = try app.get("/", htmlHandler);

    // Start server
    std.log.info("SSE Counter example with timer-based intervals starting on http://localhost:3000", .{});
    std.log.info("Visit http://localhost:3000 to see the counter with 1-second intervals", .{});
    
    try h3z.serve(&app, h3z.ServeOptions{
        .port = 3000,
        .host = "127.0.0.1",
    });
}

/// Counter state for timer-based streaming  
const CounterState = struct {
    writer: *h3z.SSEWriter,
    loop: *xev.Loop,
    counter: u32 = 0,
    max_count: u32 = 10,
    timer: xev.Timer = undefined,
    completion: xev.Completion = undefined,  
    allocator: std.mem.Allocator,
    
    fn init(allocator: std.mem.Allocator, writer: *h3z.SSEWriter, loop: *xev.Loop) !*CounterState {
        const state = try allocator.create(CounterState);
        state.* = CounterState{
            .writer = writer,
            .loop = loop,
            .allocator = allocator,
            .timer = try xev.Timer.init(),
        };
        return state;
    }
    
    fn deinit(self: *CounterState) void {
        self.timer.deinit();
        self.allocator.destroy(self);
    }
    
    fn startTiming(self: *CounterState) !void {
        // Start the timer for 1 second intervals
        self.timer.run(
            self.loop,
            &self.completion,
            1000, // 1000ms = 1 second
            CounterState,
            self,
            onTimerTick
        );
    }
    
    fn onTimerTick(
        userdata: ?*CounterState,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        _ = loop;
        _ = result catch |err| {
            std.log.err("Timer error: {}", .{err});
            return .disarm;
        };
        
        const state = userdata.?;
        defer {
            if (state.counter >= state.max_count) {
                state.writer.close();
                state.deinit();
            }
        }
        
        // Send current counter value
        var buffer: [64]u8 = undefined;
        const count_str = std.fmt.bufPrint(&buffer, "{d}", .{state.counter}) catch {
            std.log.err("Failed to format counter value", .{});
            return .disarm;
        };
        
        const sse_event = h3z.SSEEvent{
            .data = count_str,
            .event = "counter",
            .id = count_str,
        };
        
        state.writer.sendEvent(sse_event) catch |err| {
            std.log.err("Failed to send SSE event: {}", .{err});
            return .disarm;
        };
        
        std.log.info("Sent counter event: {}", .{state.counter});
        state.counter += 1;
        
        // Continue or stop based on counter
        if (state.counter < state.max_count) {
            // Reschedule for next second
            state.timer.run(
                state.loop,
                completion,
                1000, // 1000ms = 1 second
                CounterState,
                state,
                onTimerTick
            );
            return .rearm;
        } else {
            // Send final "done" event
            const done_event = h3z.SSEEvent{
                .data = "Counter completed",
                .event = "done",
                .id = "final",
            };
            state.writer.sendEvent(done_event) catch {};
            std.log.info("Counter completed, closing SSE stream", .{});
            return .disarm;
        }
    }
};

/// Timer-based SSE streaming handler with loop access
fn timerCounterHandler(writer: *h3z.SSEWriter, loop: *xev.Loop) !void {
    std.log.info("SSE counter streaming started with timer-based intervals", .{});
    
    // Get allocator from writer  
    const allocator = writer.allocator;
    
    // Create counter state with loop access
    const state = try CounterState.init(allocator, writer, loop);
    
    // Start the timer-based counter
    try state.startTiming();
    
    std.log.info("Timer-based SSE counter initialized and started", .{});
}

/// Serve HTML page with curl command (regular handler)
fn htmlHandler(event: *h3z.H3Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>H3Z SSE Counter Example</title>
        \\    <style>
        \\        body { 
        \\            font-family: Arial, sans-serif; 
        \\            margin: 40px;
        \\        }
        \\        .command-box {
        \\            background: #f4f4f4;
        \\            border: 1px solid #ddd;
        \\            border-radius: 4px;
        \\            padding: 20px;
        \\            margin: 20px 0;
        \\            font-family: monospace;
        \\            font-size: 16px;
        \\        }
        \\        .info {
        \\            background: #e3f2fd;
        \\            border: 1px solid #90caf9;
        \\            border-radius: 4px;
        \\            padding: 15px;
        \\            margin: 20px 0;
        \\        }
        \\        h1 {
        \\            color: #333;
        \\        }
        \\        code {
        \\            background: #f5f5f5;
        \\            padding: 2px 4px;
        \\            border-radius: 3px;
        \\        }
        \\    </style>
        \\</head>
        \\<body>
        \\    <h1>H3Z SSE Counter Example</h1>
        \\    <p>This example demonstrates Server-Sent Events (SSE) streaming with H3Z.</p>
        \\    
        \\    <div class="info">
        \\        <h3>How to Test SSE Streaming</h3>
        \\        <p>Run the following curl command in your terminal to see the counter stream:</p>
        \\    </div>
        \\    
        \\    <div class="command-box">
        \\        curl -N http://localhost:3000/events
        \\    </div>
        \\    
        \\    <div class="info">
        \\        <h3>What to Expect</h3>
        \\        <ul>
        \\            <li>The server will send counter values from 0 to 9 with 1-second intervals</li>
        \\            <li>Each event includes an event type (<code>counter</code>) and the current count</li>
        \\            <li>Events are spaced exactly 1 second apart using libxev timers</li>
        \\            <li>The stream will complete with a <code>done</code> event after 10 seconds</li>
        \\        </ul>
        \\    </div>
        \\    
        \\    <div class="info">
        \\        <h3>Alternative Commands</h3>
        \\        <p>To see the raw SSE format with headers:</p>
        \\        <div class="command-box">
        \\            curl -N -v http://localhost:3000/events
        \\        </div>
        \\        
        \\        <p>To save the stream to a file:</p>
        \\        <div class="command-box">
        \\            curl -N http://localhost:3000/events > sse-output.txt
        \\        </div>
        \\    </div>
        \\</body>
        \\</html>
    ;
    
    try event.sendHtml(html);
}