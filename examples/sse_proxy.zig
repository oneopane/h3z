//! SSE Event Proxy/Relay Example
//! This example demonstrates:
//! - Proxying events from an upstream source
//! - Transforming event data (e.g., temperature conversion)
//! - Filtering events based on criteria
//! - Adding metadata to events
//! - Rate limiting and backpressure handling

const std = @import("std");
const h3 = @import("h3");

const H3 = h3.H3;
const serve = h3.serve;
const ServeOptions = h3.ServeOptions;
const SSEWriter = h3.SSEWriter;
const SSEEvent = h3.SSEEvent;

/// Event source types we can proxy
const EventSourceType = enum {
    temperature_sensor,
    stock_ticker,
    system_metrics,
    weather_api,
};

/// Temperature event data
const TemperatureEvent = struct {
    sensor_id: []const u8,
    celsius: f32,
    timestamp: i64,
};

/// Stock ticker event data
const StockEvent = struct {
    symbol: []const u8,
    price: f32,
    change: f32,
    volume: u64,
    timestamp: i64,
};

/// System metrics event data
const SystemMetricsEvent = struct {
    cpu_usage: f32,
    memory_usage: f32,
    disk_usage: f32,
    network_rx: u64,
    network_tx: u64,
    timestamp: i64,
};

/// Weather event data
const WeatherEvent = struct {
    location: []const u8,
    temperature: f32,
    humidity: f32,
    conditions: []const u8,
    timestamp: i64,
};

/// Transformation options
const TransformOptions = struct {
    /// Convert temperature from Celsius to Fahrenheit
    celsius_to_fahrenheit: bool = false,
    /// Convert stock prices to different currency
    currency_conversion: ?f32 = null,
    /// Add server timestamp to events
    add_server_timestamp: bool = true,
    /// Filter out events below threshold
    min_threshold: ?f32 = null,
    /// Filter out events above threshold
    max_threshold: ?f32 = null,
    /// Rate limit events per second
    rate_limit: ?u32 = null,
};

/// Event generator for simulating upstream sources
const EventGenerator = struct {
    allocator: std.mem.Allocator,
    source_type: EventSourceType,
    running: std.atomic.Value(bool),
    
    pub fn init(allocator: std.mem.Allocator, source_type: EventSourceType) EventGenerator {
        return .{
            .allocator = allocator,
            .source_type = source_type,
            .running = std.atomic.Value(bool).init(true),
        };
    }
    
    pub fn stop(self: *EventGenerator) void {
        self.running.store(false, .seq_cst);
    }
    
    /// Generate temperature sensor events
    fn generateTemperatureEvent(self: *EventGenerator) ![]u8 {
        const sensors = [_][]const u8{ "sensor-1", "sensor-2", "sensor-3", "sensor-4" };
        const sensor = sensors[@intCast(@mod(std.crypto.random.int(u32), sensors.len))];
        
        // Generate realistic temperature between 15-35°C with some noise
        const base_temp: f32 = 25.0;
        const variation: f32 = @as(f32, @floatFromInt(std.crypto.random.int(i8))) / 10.0;
        const celsius = base_temp + variation;
        
        return try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "sensor_id": "{s}",
            \\  "celsius": {d:.1},
            \\  "timestamp": {d}
            \\}}
        , .{ sensor, celsius, std.time.timestamp() });
    }
    
    /// Generate stock ticker events
    fn generateStockEvent(self: *EventGenerator) ![]u8 {
        const symbols = [_][]const u8{ "AAPL", "GOOGL", "MSFT", "AMZN", "TSLA" };
        const symbol = symbols[@intCast(@mod(std.crypto.random.int(u32), symbols.len))];
        
        // Generate realistic stock price movements
        const base_prices = [_]f32{ 150.0, 2800.0, 300.0, 3200.0, 800.0 };
        const base_price = base_prices[@intCast(@mod(std.crypto.random.int(u32), base_prices.len))];
        const change_percent = (@as(f32, @floatFromInt(std.crypto.random.int(i8))) / 100.0);
        const price = base_price * (1.0 + change_percent);
        const change = price - base_price;
        const volume = std.crypto.random.int(u32) % 1000000 + 100000;
        
        return try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "symbol": "{s}",
            \\  "price": {d:.2},
            \\  "change": {d:.2},
            \\  "volume": {d},
            \\  "timestamp": {d}
            \\}}
        , .{ symbol, price, change, volume, std.time.timestamp() });
    }
    
    /// Generate system metrics events
    fn generateSystemMetricsEvent(self: *EventGenerator) ![]u8 {
        // Simulate realistic system metrics
        const cpu_base = 30.0 + @as(f32, @floatFromInt(@mod(std.time.timestamp(), 60))) / 2.0;
        const cpu_usage = cpu_base + @as(f32, @floatFromInt(std.crypto.random.int(u8))) / 10.0;
        const memory_usage = 45.0 + @as(f32, @floatFromInt(std.crypto.random.int(u8))) / 5.0;
        const disk_usage = 60.0 + @as(f32, @floatFromInt(std.crypto.random.int(u8))) / 20.0;
        const network_rx = std.crypto.random.int(u32) % 1000000;
        const network_tx = std.crypto.random.int(u32) % 500000;
        
        return try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "cpu_usage": {d:.1},
            \\  "memory_usage": {d:.1},
            \\  "disk_usage": {d:.1},
            \\  "network_rx": {d},
            \\  "network_tx": {d},
            \\  "timestamp": {d}
            \\}}
        , .{ cpu_usage, memory_usage, disk_usage, network_rx, network_tx, std.time.timestamp() });
    }
    
    /// Generate weather events
    fn generateWeatherEvent(self: *EventGenerator) ![]u8 {
        const locations = [_][]const u8{ "New York", "London", "Tokyo", "Sydney", "Paris" };
        const conditions = [_][]const u8{ "Sunny", "Cloudy", "Rainy", "Partly Cloudy", "Clear" };
        
        const location = locations[@intCast(@mod(std.crypto.random.int(u32), locations.len))];
        const condition = conditions[@intCast(@mod(std.crypto.random.int(u32), conditions.len))];
        
        const base_temp: f32 = switch (std.crypto.random.int(u8) % 4) {
            0 => 5.0,  // Winter
            1 => 15.0, // Spring/Fall
            2 => 25.0, // Summer
            else => 20.0, // Mild
        };
        const temperature = base_temp + @as(f32, @floatFromInt(std.crypto.random.int(i8))) / 5.0;
        const humidity = 30.0 + @as(f32, @floatFromInt(std.crypto.random.int(u8))) / 2.0;
        
        return try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "location": "{s}",
            \\  "temperature": {d:.1},
            \\  "humidity": {d:.1},
            \\  "conditions": "{s}",
            \\  "timestamp": {d}
            \\}}
        , .{ location, temperature, humidity, condition, std.time.timestamp() });
    }
    
    /// Generate the next event based on source type
    pub fn generateEvent(self: *EventGenerator) ![]u8 {
        return switch (self.source_type) {
            .temperature_sensor => try self.generateTemperatureEvent(),
            .stock_ticker => try self.generateStockEvent(),
            .system_metrics => try self.generateSystemMetricsEvent(),
            .weather_api => try self.generateWeatherEvent(),
        };
    }
};

/// Proxy connection manager
const ProxyConnection = struct {
    allocator: std.mem.Allocator,
    writer: *SSEWriter,
    source_type: EventSourceType,
    transform_options: TransformOptions,
    event_count: usize = 0,
    last_event_time: i64 = 0,
    
    /// Transform temperature event data
    fn transformTemperature(self: *ProxyConnection, data: []const u8) ![]u8 {
        // Parse temperature from JSON (simplified parsing)
        var celsius: f32 = 0;
        if (std.mem.indexOf(u8, data, "\"celsius\":")) |pos| {
            const start = pos + 10;
            var end = start;
            while (end < data.len and (data[end] == '.' or (data[end] >= '0' and data[end] <= '9') or data[end] == '-')) : (end += 1) {}
            celsius = try std.fmt.parseFloat(f32, data[start..end]);
        }
        
        // Apply threshold filters
        if (self.transform_options.min_threshold) |min| {
            if (celsius < min) return error.BelowThreshold;
        }
        if (self.transform_options.max_threshold) |max| {
            if (celsius > max) return error.AboveThreshold;
        }
        
        // Transform to Fahrenheit if requested
        if (self.transform_options.celsius_to_fahrenheit) {
            const fahrenheit = (celsius * 9.0 / 5.0) + 32.0;
            
            // Create transformed event
            return try std.fmt.allocPrint(self.allocator,
                \\{{
                \\  "type": "temperature",
                \\  "original_celsius": {d:.1},
                \\  "fahrenheit": {d:.1},
                \\  "server_timestamp": {d},
                \\  "proxy_event_count": {d}
                \\}}
            , .{ celsius, fahrenheit, std.time.timestamp(), self.event_count });
        }
        
        return try self.allocator.dupe(u8, data);
    }
    
    /// Transform stock event data
    fn transformStock(self: *ProxyConnection, data: []const u8) ![]u8 {
        // Parse price from JSON (simplified)
        var price: f32 = 0;
        if (std.mem.indexOf(u8, data, "\"price\":")) |pos| {
            const start = pos + 8;
            var end = start;
            while (end < data.len and (data[end] == '.' or (data[end] >= '0' and data[end] <= '9'))) : (end += 1) {}
            price = try std.fmt.parseFloat(f32, data[start..end]);
        }
        
        // Apply currency conversion if specified
        if (self.transform_options.currency_conversion) |rate| {
            const converted_price = price * rate;
            
            return try std.fmt.allocPrint(self.allocator,
                \\{{
                \\  "type": "stock",
                \\  "original_usd": {d:.2},
                \\  "converted_price": {d:.2},
                \\  "conversion_rate": {d:.4},
                \\  "server_timestamp": {d}
                \\}}
            , .{ price, converted_price, rate, std.time.timestamp() });
        }
        
        return try self.allocator.dupe(u8, data);
    }
    
    /// Apply rate limiting
    fn checkRateLimit(self: *ProxyConnection) bool {
        if (self.transform_options.rate_limit) |limit| {
            const now = std.time.timestamp();
            if (self.last_event_time == now) {
                // Simple rate limiting: one event per second per limit
                return self.event_count % limit != 0;
            }
            self.last_event_time = now;
        }
        return false;
    }
    
    /// Process and transform an event
    pub fn processEvent(self: *ProxyConnection, event_data: []const u8, event_type: []const u8) !void {
        // Check rate limit
        if (self.checkRateLimit()) {
            return;
        }
        
        self.event_count += 1;
        
        // Transform based on source type
        const transformed_data = switch (self.source_type) {
            .temperature_sensor => try self.transformTemperature(event_data),
            .stock_ticker => try self.transformStock(event_data),
            else => try self.allocator.dupe(u8, event_data),
        };
        defer self.allocator.free(transformed_data);
        
        // Send transformed event
        try self.writer.sendEvent(SSEEvent{
            .data = transformed_data,
            .event = event_type,
            .id = try std.fmt.allocPrint(self.allocator, "{d}", .{self.event_count}),
        });
    }
};

/// Active proxy connections
var proxy_connections: std.ArrayList(*ProxyConnection) = undefined;
var connections_mutex: std.Thread.Mutex = .{};

/// Event generation thread
fn eventGeneratorThread(generator: *EventGenerator) void {
    while (generator.running.load(.seq_cst)) {
        // Generate event
        const event_data = generator.generateEvent() catch |err| {
            std.log.err("Failed to generate event: {}", .{err});
            continue;
        };
        defer generator.allocator.free(event_data);
        
        // Send to all proxy connections
        connections_mutex.lock();
        defer connections_mutex.unlock();
        
        var i: usize = 0;
        while (i < proxy_connections.items.len) {
            const conn = proxy_connections.items[i];
            conn.processEvent(event_data, @tagName(generator.source_type)) catch |err| {
                if (err == error.BelowThreshold or err == error.AboveThreshold) {
                    // Skip filtered events
                    i += 1;
                    continue;
                }
                
                std.log.warn("Failed to send event to proxy connection: {}", .{err});
                // Remove failed connection
                conn.writer.close();
                generator.allocator.destroy(conn);
                _ = proxy_connections.swapRemove(i);
                continue;
            };
            i += 1;
        }
        
        // Sleep based on event type
        const sleep_duration: u64 = switch (generator.source_type) {
            .temperature_sensor => 2 * std.time.ns_per_s,    // Every 2 seconds
            .stock_ticker => 500 * std.time.ns_per_ms,       // Every 500ms
            .system_metrics => 5 * std.time.ns_per_s,        // Every 5 seconds
            .weather_api => 10 * std.time.ns_per_s,          // Every 10 seconds
        };
        
        std.time.sleep(sleep_duration);
    }
}

/// SSE proxy endpoint
pub fn handleProxyStream(event: *h3.Event) !void {
    // Parse query parameters
    const source = event.getQuery("source") orelse "temperature_sensor";
    const celsius_to_f = event.getQuery("celsius_to_f") != null;
    const min_threshold_str = event.getQuery("min_threshold");
    const max_threshold_str = event.getQuery("max_threshold");
    const rate_limit_str = event.getQuery("rate_limit");
    
    // Parse source type
    const source_type = std.meta.stringToEnum(EventSourceType, source) orelse .temperature_sensor;
    
    // Parse transform options
    var transform_options = TransformOptions{
        .celsius_to_fahrenheit = celsius_to_f,
    };
    
    if (min_threshold_str) |str| {
        transform_options.min_threshold = try std.fmt.parseFloat(f32, str);
    }
    if (max_threshold_str) |str| {
        transform_options.max_threshold = try std.fmt.parseFloat(f32, str);
    }
    if (rate_limit_str) |str| {
        transform_options.rate_limit = try std.fmt.parseInt(u32, str, 10);
    }
    
    // Start SSE
    try event.startSSE();
    
    // Get SSE writer
    const writer = try event.getSSEWriter();
    
    // Create proxy connection
    const conn = try event.allocator.create(ProxyConnection);
    conn.* = .{
        .allocator = event.allocator,
        .writer = writer,
        .source_type = source_type,
        .transform_options = transform_options,
    };
    
    // Add to active connections
    connections_mutex.lock();
    defer connections_mutex.unlock();
    try proxy_connections.append(conn);
    
    // Send initial info event
    const info = try std.fmt.allocPrint(event.allocator,
        \\{{
        \\  "type": "proxy-info",
        \\  "source": "{s}",
        \\  "transforms": {{
        \\    "celsius_to_fahrenheit": {},
        \\    "min_threshold": {},
        \\    "max_threshold": {},
        \\    "rate_limit": {}
        \\  }}
        \\}}
    , .{ 
        @tagName(source_type), 
        celsius_to_f,
        transform_options.min_threshold != null,
        transform_options.max_threshold != null,
        transform_options.rate_limit != null,
    });
    defer event.allocator.free(info);
    
    try writer.sendEvent(SSEEvent.typedEvent("info", info));
}

/// HTML client page
pub fn handleProxyPage(event: *h3.Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>H3Z SSE Proxy Example</title>
        \\    <style>
        \\        body { font-family: Arial, sans-serif; max-width: 1000px; margin: 0 auto; padding: 20px; }
        \\        .controls { margin-bottom: 20px; padding: 15px; background: #f0f0f0; border-radius: 5px; }
        \\        .control-group { margin: 10px 0; }
        \\        label { display: inline-block; width: 150px; }
        \\        input[type="number"] { width: 80px; }
        \\        #events { height: 400px; overflow-y: auto; border: 1px solid #ccc; padding: 10px; font-family: monospace; }
        \\        .event { margin: 5px 0; padding: 5px; background: #f9f9f9; border-left: 3px solid #4CAF50; }
        \\        .info { border-left-color: #2196F3; }
        \\        .error { border-left-color: #f44336; }
        \\        #stats { margin-top: 10px; font-size: 14px; color: #666; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <h1>H3Z SSE Proxy Example</h1>
        \\    <p>This example demonstrates proxying and transforming Server-Sent Events.</p>
        \\    
        \\    <div class="controls">
        \\        <div class="control-group">
        \\            <label>Event Source:</label>
        \\            <select id="source">
        \\                <option value="temperature_sensor">Temperature Sensor</option>
        \\                <option value="stock_ticker">Stock Ticker</option>
        \\                <option value="system_metrics">System Metrics</option>
        \\                <option value="weather_api">Weather API</option>
        \\            </select>
        \\        </div>
        \\        
        \\        <div class="control-group" id="temp-options">
        \\            <label>Convert to Fahrenheit:</label>
        \\            <input type="checkbox" id="celsius_to_f" />
        \\        </div>
        \\        
        \\        <div class="control-group">
        \\            <label>Min Threshold:</label>
        \\            <input type="number" id="min_threshold" step="0.1" />
        \\        </div>
        \\        
        \\        <div class="control-group">
        \\            <label>Max Threshold:</label>
        \\            <input type="number" id="max_threshold" step="0.1" />
        \\        </div>
        \\        
        \\        <div class="control-group">
        \\            <label>Rate Limit (events/sec):</label>
        \\            <input type="number" id="rate_limit" min="1" max="10" />
        \\        </div>
        \\        
        \\        <button onclick="connect()">Connect to Proxy</button>
        \\        <button onclick="disconnect()">Disconnect</button>
        \\    </div>
        \\    
        \\    <div id="events"></div>
        \\    <div id="stats">Events received: <span id="event-count">0</span></div>
        \\    
        \\    <script>
        \\        let eventSource = null;
        \\        let eventCount = 0;
        \\        
        \\        function updateSourceOptions() {
        \\            const source = document.getElementById('source').value;
        \\            document.getElementById('temp-options').style.display = 
        \\                source === 'temperature_sensor' ? 'block' : 'none';
        \\        }
        \\        
        \\        function connect() {
        \\            if (eventSource) {
        \\                eventSource.close();
        \\            }
        \\            
        \\            const params = new URLSearchParams();
        \\            params.set('source', document.getElementById('source').value);
        \\            
        \\            if (document.getElementById('celsius_to_f').checked) {
        \\                params.set('celsius_to_f', 'true');
        \\            }
        \\            
        \\            const minThreshold = document.getElementById('min_threshold').value;
        \\            if (minThreshold) params.set('min_threshold', minThreshold);
        \\            
        \\            const maxThreshold = document.getElementById('max_threshold').value;
        \\            if (maxThreshold) params.set('max_threshold', maxThreshold);
        \\            
        \\            const rateLimit = document.getElementById('rate_limit').value;
        \\            if (rateLimit) params.set('rate_limit', rateLimit);
        \\            
        \\            eventSource = new EventSource('/proxy/stream?' + params.toString());
        \\            document.getElementById('events').innerHTML = '';
        \\            eventCount = 0;
        \\            
        \\            eventSource.addEventListener('info', (e) => {
        \\                addEvent(e.data, 'info');
        \\            });
        \\            
        \\            eventSource.addEventListener('temperature_sensor', (e) => {
        \\                addEvent(e.data, 'event');
        \\            });
        \\            
        \\            eventSource.addEventListener('stock_ticker', (e) => {
        \\                addEvent(e.data, 'event');
        \\            });
        \\            
        \\            eventSource.addEventListener('system_metrics', (e) => {
        \\                addEvent(e.data, 'event');
        \\            });
        \\            
        \\            eventSource.addEventListener('weather_api', (e) => {
        \\                addEvent(e.data, 'event');
        \\            });
        \\            
        \\            eventSource.onerror = (e) => {
        \\                console.error('SSE error:', e);
        \\                addEvent('Connection error', 'error');
        \\                eventSource.close();
        \\            };
        \\        }
        \\        
        \\        function disconnect() {
        \\            if (eventSource) {
        \\                eventSource.close();
        \\                eventSource = null;
        \\                addEvent('Disconnected', 'info');
        \\            }
        \\        }
        \\        
        \\        function addEvent(data, className) {
        \\            const eventsDiv = document.getElementById('events');
        \\            const eventDiv = document.createElement('div');
        \\            eventDiv.className = 'event ' + className;
        \\            
        \\            try {
        \\                const parsed = JSON.parse(data);
        \\                eventDiv.textContent = JSON.stringify(parsed, null, 2);
        \\            } catch {
        \\                eventDiv.textContent = data;
        \\            }
        \\            
        \\            eventsDiv.appendChild(eventDiv);
        \\            eventsDiv.scrollTop = eventsDiv.scrollHeight;
        \\            
        \\            eventCount++;
        \\            document.getElementById('event-count').textContent = eventCount;
        \\            
        \\            // Keep only last 100 events
        \\            while (eventsDiv.children.length > 100) {
        \\                eventsDiv.removeChild(eventsDiv.firstChild);
        \\            }
        \\        }
        \\        
        \\        document.getElementById('source').addEventListener('change', updateSourceOptions);
        \\        updateSourceOptions();
        \\    </script>
        \\</body>
        \\</html>
    ;
    
    try event.sendHtml(html);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize proxy connections list
    proxy_connections = std.ArrayList(*ProxyConnection).init(allocator);
    defer proxy_connections.deinit();
    
    // Create event generators for different sources
    var temp_generator = EventGenerator.init(allocator, .temperature_sensor);
    var stock_generator = EventGenerator.init(allocator, .stock_ticker);
    var metrics_generator = EventGenerator.init(allocator, .system_metrics);
    var weather_generator = EventGenerator.init(allocator, .weather_api);
    
    defer {
        temp_generator.stop();
        stock_generator.stop();
        metrics_generator.stop();
        weather_generator.stop();
    }
    
    // Start generator threads
    const temp_thread = try std.Thread.spawn(.{}, eventGeneratorThread, .{&temp_generator});
    const stock_thread = try std.Thread.spawn(.{}, eventGeneratorThread, .{&stock_generator});
    const metrics_thread = try std.Thread.spawn(.{}, eventGeneratorThread, .{&metrics_generator});
    const weather_thread = try std.Thread.spawn(.{}, eventGeneratorThread, .{&weather_generator});
    
    temp_thread.detach();
    stock_thread.detach();
    metrics_thread.detach();
    weather_thread.detach();
    
    // Create app using legacy API
    var app = try H3.init(allocator);
    defer app.deinit();
    
    // Register routes
    _ = app.get("/", handleProxyPage);
    _ = app.get("/proxy/stream", handleProxyStream);
    
    // Start server
    const port: u16 = 3002;
    std.log.info("SSE Proxy server starting on http://localhost:{d}", .{port});
    std.log.info("Configure proxy settings and connect to see transformed events", .{});
    
    try serve(&app, ServeOptions{ .port = port });
}