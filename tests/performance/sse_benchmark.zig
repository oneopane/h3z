//! Performance benchmarks for SSE (Server-Sent Events) functionality
//! Tests throughput, latency, memory usage, and scalability

const std = @import("std");
const testing = std.testing;

const h3 = @import("h3z");
const H3App = h3.H3App;
const H3Event = h3.Event;
const SSEEvent = h3.sse.SSEEvent;
const SSEWriter = h3.sse.SSEWriter;

// Benchmark configuration
const BenchmarkConfig = struct {
    events_per_connection: u32 = 10_000,
    event_sizes: []const usize = &[_]usize{ 1024, 4096, 16384 }, // 1KB, 4KB, 16KB
    concurrent_connections: u32 = 1000,
    benchmark_duration_s: u32 = 60,
};

// Performance metrics
const PerformanceMetrics = struct {
    events_sent: u64 = 0,
    bytes_sent: u64 = 0,
    duration_ns: u64 = 0,
    memory_used: usize = 0,
    p50_latency_ns: u64 = 0,
    p99_latency_ns: u64 = 0,
    errors: u64 = 0,
    
    pub fn throughputEventsPerSec(self: PerformanceMetrics) f64 {
        const duration_s = @as(f64, @floatFromInt(self.duration_ns)) / std.time.ns_per_s;
        return @as(f64, @floatFromInt(self.events_sent)) / duration_s;
    }
    
    pub fn throughputMBPerSec(self: PerformanceMetrics) f64 {
        const duration_s = @as(f64, @floatFromInt(self.duration_ns)) / std.time.ns_per_s;
        const mb_sent = @as(f64, @floatFromInt(self.bytes_sent)) / (1024 * 1024);
        return mb_sent / duration_s;
    }
    
    pub fn avgLatencyMs(self: PerformanceMetrics) f64 {
        return @as(f64, @floatFromInt(self.p50_latency_ns)) / std.time.ns_per_ms;
    }
    
    pub fn p99LatencyMs(self: PerformanceMetrics) f64 {
        return @as(f64, @floatFromInt(self.p99_latency_ns)) / std.time.ns_per_ms;
    }
    
    pub fn print(self: PerformanceMetrics) void {
        std.debug.print("\n=== SSE Performance Metrics ===\n", .{});
        std.debug.print("Events sent: {d}\n", .{self.events_sent});
        std.debug.print("Throughput: {d:.0} events/sec\n", .{self.throughputEventsPerSec()});
        std.debug.print("Throughput: {d:.2} MB/sec\n", .{self.throughputMBPerSec()});
        std.debug.print("P50 Latency: {d:.2} ms\n", .{self.avgLatencyMs()});
        std.debug.print("P99 Latency: {d:.2} ms\n", .{self.p99LatencyMs()});
        std.debug.print("Memory used: {d:.2} MB\n", .{@as(f64, @floatFromInt(self.memory_used)) / (1024 * 1024)});
        std.debug.print("Errors: {d}\n", .{self.errors});
        std.debug.print("================================\n", .{});
    }
};

// Latency tracker
const LatencyTracker = struct {
    samples: std.ArrayList(u64),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) LatencyTracker {
        return .{
            .samples = std.ArrayList(u64).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *LatencyTracker) void {
        self.samples.deinit();
    }
    
    pub fn addSample(self: *LatencyTracker, latency_ns: u64) !void {
        try self.samples.append(latency_ns);
    }
    
    pub fn getPercentile(self: *LatencyTracker, percentile: f64) u64 {
        if (self.samples.items.len == 0) return 0;
        
        std.mem.sort(u64, self.samples.items, {}, std.sort.asc(u64));
        const index = @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.samples.items.len - 1)) * percentile / 100.0));
        return self.samples.items[index];
    }
};

// Mock high-performance connection for benchmarking
const BenchmarkConnection = struct {
    bytes_written: u64 = 0,
    write_count: u64 = 0,
    is_alive: bool = true,
    
    pub fn writeChunk(self: *BenchmarkConnection, data: []const u8) !void {
        if (!self.is_alive) return error.ConnectionClosed;
        self.bytes_written += data.len;
        self.write_count += 1;
    }
    
    pub fn flush(self: *BenchmarkConnection) !void {
        if (!self.is_alive) return error.ConnectionClosed;
        // No-op for benchmark
    }
    
    pub fn close(self: *BenchmarkConnection) void {
        self.is_alive = false;
    }
    
    pub fn isAlive(self: *const BenchmarkConnection) bool {
        return self.is_alive;
    }
};

// Benchmark: Event throughput
test "SSE event throughput benchmark" {
    const allocator = testing.allocator;
    const config = BenchmarkConfig{};
    
    var metrics = PerformanceMetrics{};
    var latency_tracker = LatencyTracker.init(allocator);
    defer latency_tracker.deinit();
    
    // Create benchmark connection
    var conn = BenchmarkConnection{};
    var writer = SSEWriter.init(allocator, @ptrCast(&conn));
    defer writer.close();
    
    // Generate test data
    const test_data = try allocator.alloc(u8, config.event_sizes[1]); // 4KB
    defer allocator.free(test_data);
    @memset(test_data, 'X');
    
    // Start benchmark
    const start_time = std.time.nanoTimestamp();
    
    for (0..config.events_per_connection) |i| {
        const event_start = std.time.nanoTimestamp();
        
        const event = SSEEvent{
            .data = test_data,
            .event = "benchmark",
            .id = try std.fmt.allocPrint(allocator, "{d}", .{i}),
        };
        defer if (event.id) |id| allocator.free(id);
        
        writer.sendEvent(event) catch |err| {
            metrics.errors += 1;
            std.debug.print("Error sending event: {}\n", .{err});
            continue;
        };
        
        const event_end = std.time.nanoTimestamp();
        try latency_tracker.addSample(@intCast(event_end - event_start));
        
        metrics.events_sent += 1;
        metrics.bytes_sent = conn.bytes_written;
    }
    
    const end_time = std.time.nanoTimestamp();
    metrics.duration_ns = @intCast(end_time - start_time);
    
    // Calculate percentiles
    metrics.p50_latency_ns = latency_tracker.getPercentile(50);
    metrics.p99_latency_ns = latency_tracker.getPercentile(99);
    
    // Print results
    metrics.print();
    
    // Verify performance targets
    try testing.expect(metrics.throughputEventsPerSec() > 10_000); // Target: 10K events/sec
    try testing.expect(metrics.p99LatencyMs() < 10); // Target: <10ms p99 latency
}

// Benchmark: Memory usage over time
test "SSE memory usage benchmark" {
    const allocator = testing.allocator;
    const config = BenchmarkConfig{};
    
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    defer _ = gpa.deinit();
    const tracked_allocator = gpa.allocator();
    
    // Track initial memory
    const initial_memory = gpa.total_requested_bytes;
    
    // Create multiple connections
    var connections = std.ArrayList(BenchmarkConnection).init(allocator);
    defer connections.deinit();
    
    var writers = std.ArrayList(SSEWriter).init(allocator);
    defer writers.deinit();
    
    // Create connections
    for (0..100) |_| {
        try connections.append(BenchmarkConnection{});
        const conn = &connections.items[connections.items.len - 1];
        try writers.append(SSEWriter.init(tracked_allocator, @ptrCast(conn)));
    }
    
    // Send events on all connections
    const test_data = try tracked_allocator.alloc(u8, 1024); // 1KB
    defer tracked_allocator.free(test_data);
    @memset(test_data, 'M');
    
    for (0..1000) |i| {
        for (writers.items) |*writer| {
            const event = SSEEvent{
                .data = test_data,
                .id = try std.fmt.allocPrint(tracked_allocator, "{d}", .{i}),
            };
            defer if (event.id) |id| tracked_allocator.free(id);
            
            writer.sendEvent(event) catch continue;
        }
    }
    
    // Check memory usage
    const final_memory = gpa.total_requested_bytes;
    const memory_per_connection = (final_memory - initial_memory) / connections.items.len;
    
    std.debug.print("\n=== Memory Usage ===\n", .{});
    std.debug.print("Connections: {d}\n", .{connections.items.len});
    std.debug.print("Total memory: {d:.2} MB\n", .{@as(f64, @floatFromInt(final_memory)) / (1024 * 1024)});
    std.debug.print("Memory per connection: {d:.2} KB\n", .{@as(f64, @floatFromInt(memory_per_connection)) / 1024});
    
    // Verify memory target
    try testing.expect(memory_per_connection < 16 * 1024); // Target: <16KB per connection
    
    // Clean up
    for (writers.items) |*writer| {
        writer.close();
    }
}

// Benchmark: Concurrent connections
test "SSE concurrent connections benchmark" {
    const allocator = testing.allocator;
    const config = BenchmarkConfig{ .concurrent_connections = 100 }; // Reduced for testing
    
    var connections = std.ArrayList(BenchmarkConnection).init(allocator);
    defer connections.deinit();
    
    var writers = std.ArrayList(SSEWriter).init(allocator);
    defer writers.deinit();
    
    // Create concurrent connections
    const start_time = std.time.nanoTimestamp();
    
    for (0..config.concurrent_connections) |_| {
        try connections.append(BenchmarkConnection{});
        const conn = &connections.items[connections.items.len - 1];
        try writers.append(SSEWriter.init(allocator, @ptrCast(conn)));
    }
    
    const setup_time = std.time.nanoTimestamp() - start_time;
    
    // Send events concurrently
    const test_data = "Concurrent test event";
    var total_events_sent: u64 = 0;
    
    for (0..100) |i| {
        for (writers.items) |*writer| {
            const event = SSEEvent{
                .data = test_data,
                .id = try std.fmt.allocPrint(allocator, "{d}", .{i}),
            };
            defer if (event.id) |id| allocator.free(id);
            
            writer.sendEvent(event) catch continue;
            total_events_sent += 1;
        }
    }
    
    const total_time = std.time.nanoTimestamp() - start_time;
    
    std.debug.print("\n=== Concurrent Connections ===\n", .{});
    std.debug.print("Connections: {d}\n", .{config.concurrent_connections});
    std.debug.print("Setup time: {d:.2} ms\n", .{@as(f64, @floatFromInt(setup_time)) / std.time.ns_per_ms});
    std.debug.print("Total events sent: {d}\n", .{total_events_sent});
    std.debug.print("Events per connection: {d}\n", .{total_events_sent / config.concurrent_connections});
    std.debug.print("Total time: {d:.2} ms\n", .{@as(f64, @floatFromInt(total_time)) / std.time.ns_per_ms});
    
    // Clean up
    for (writers.items) |*writer| {
        writer.close();
    }
}

// Benchmark: Large event handling
test "SSE large event benchmark" {
    const allocator = testing.allocator;
    
    var conn = BenchmarkConnection{};
    var writer = SSEWriter.init(allocator, @ptrCast(&conn));
    defer writer.close();
    
    // Test different event sizes
    const sizes = [_]usize{ 1024, 10 * 1024, 100 * 1024, 1024 * 1024 }; // 1KB, 10KB, 100KB, 1MB
    
    std.debug.print("\n=== Large Event Performance ===\n", .{});
    
    for (sizes) |size| {
        const data = try allocator.alloc(u8, size);
        defer allocator.free(data);
        @memset(data, 'L');
        
        const start_time = std.time.nanoTimestamp();
        
        const event = SSEEvent{
            .data = data,
            .event = "large",
        };
        
        try writer.sendEvent(event);
        
        const duration = std.time.nanoTimestamp() - start_time;
        const duration_ms = @as(f64, @floatFromInt(duration)) / std.time.ns_per_ms;
        const throughput_mb = @as(f64, @floatFromInt(size)) / (1024 * 1024) / (duration_ms / 1000);
        
        std.debug.print("Size: {d} KB, Time: {d:.2} ms, Throughput: {d:.2} MB/s\n", .{
            size / 1024,
            duration_ms,
            throughput_mb,
        });
    }
}

// Benchmark: Event formatting performance
test "SSE event formatting benchmark" {
    const allocator = testing.allocator;
    
    const iterations = 100_000;
    var total_bytes: u64 = 0;
    
    // Test different event configurations
    const test_cases = [_]SSEEvent{
        SSEEvent{ .data = "Simple data" },
        SSEEvent{ .data = "Multi\nline\ndata\nwith\nmany\nlines" },
        SSEEvent{ .data = "Complete event", .event = "test", .id = "123", .retry = 5000 },
    };
    
    std.debug.print("\n=== Event Formatting Performance ===\n", .{});
    
    for (test_cases, 0..) |event, i| {
        const start_time = std.time.nanoTimestamp();
        
        for (0..iterations) |_| {
            const formatted = try event.formatEvent(allocator);
            defer allocator.free(formatted);
            total_bytes += formatted.len;
        }
        
        const duration = std.time.nanoTimestamp() - start_time;
        const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(duration)) / std.time.ns_per_s);
        
        std.debug.print("Test case {d}: {d:.0} formats/sec\n", .{ i + 1, ops_per_sec });
    }
}

// Benchmark: Write queue performance under backpressure
test "SSE backpressure handling benchmark" {
    const allocator = testing.allocator;
    
    // Simulate connection with varying write speeds
    const SlowConnection = struct {
        write_delay_ns: u64 = 1_000_000, // 1ms delay per write
        bytes_written: u64 = 0,
        is_alive: bool = true,
        
        pub fn writeChunk(self: *@This(), data: []const u8) !void {
            if (!self.is_alive) return error.ConnectionClosed;
            std.time.sleep(self.write_delay_ns);
            self.bytes_written += data.len;
        }
        
        pub fn flush(self: *@This()) !void {
            if (!self.is_alive) return error.ConnectionClosed;
        }
        
        pub fn close(self: *@This()) void {
            self.is_alive = false;
        }
        
        pub fn isAlive(self: *const @This()) bool {
            return self.is_alive;
        }
    };
    
    var slow_conn = SlowConnection{};
    var writer = SSEWriter.init(allocator, @ptrCast(&slow_conn));
    defer writer.close();
    
    const start_time = std.time.nanoTimestamp();
    var backpressure_events: u32 = 0;
    
    // Send events rapidly to trigger backpressure
    for (0..100) |i| {
        const event = SSEEvent{
            .data = "Backpressure test",
            .id = try std.fmt.allocPrint(allocator, "{d}", .{i}),
        };
        defer if (event.id) |id| allocator.free(id);
        
        writer.sendEvent(event) catch |err| {
            if (err == error.BackpressureDetected) {
                backpressure_events += 1;
            }
        };
    }
    
    const duration = std.time.nanoTimestamp() - start_time;
    
    std.debug.print("\n=== Backpressure Handling ===\n", .{});
    std.debug.print("Total time: {d:.2} ms\n", .{@as(f64, @floatFromInt(duration)) / std.time.ns_per_ms});
    std.debug.print("Backpressure events: {d}\n", .{backpressure_events});
    std.debug.print("Bytes written: {d}\n", .{slow_conn.bytes_written});
}

// Helper function to generate realistic SSE data
fn generateRealisticEvent(allocator: std.mem.Allocator, index: u32) !SSEEvent {
    // Simulate JSON payload like LLM streaming
    const json_data = try std.fmt.allocPrint(allocator, 
        \\{{
        \\  "index": {d},
        \\  "token": "word{d}",
        \\  "confidence": 0.{d},
        \\  "timestamp": {d}
        \\}}
    , .{ index, index % 100, 95 + (index % 5), std.time.timestamp() });
    
    return SSEEvent{
        .data = json_data,
        .event = if (index % 10 == 0) "checkpoint" else "token",
        .id = try std.fmt.allocPrint(allocator, "msg-{d}", .{index}),
    };
}

// Benchmark: Realistic LLM streaming scenario
test "SSE LLM streaming benchmark" {
    const allocator = testing.allocator;
    
    var conn = BenchmarkConnection{};
    var writer = SSEWriter.init(allocator, @ptrCast(&conn));
    defer writer.close();
    
    const total_tokens = 1000;
    const start_time = std.time.nanoTimestamp();
    
    std.debug.print("\n=== LLM Streaming Simulation ===\n", .{});
    
    for (0..total_tokens) |i| {
        const event = try generateRealisticEvent(allocator, @intCast(i));
        defer {
            allocator.free(event.data);
            if (event.id) |id| allocator.free(id);
        }
        
        try writer.sendEvent(event);
        
        // Simulate LLM generation delay (10-50ms per token)
        std.time.sleep((10 + (i % 40)) * std.time.ns_per_ms);
    }
    
    const duration = std.time.nanoTimestamp() - start_time;
    const duration_s = @as(f64, @floatFromInt(duration)) / std.time.ns_per_s;
    const tokens_per_sec = @as(f64, @floatFromInt(total_tokens)) / duration_s;
    
    std.debug.print("Total tokens: {d}\n", .{total_tokens});
    std.debug.print("Total time: {d:.2} s\n", .{duration_s});
    std.debug.print("Tokens/sec: {d:.2}\n", .{tokens_per_sec});
    std.debug.print("Bytes sent: {d:.2} KB\n", .{@as(f64, @floatFromInt(conn.bytes_written)) / 1024});
}