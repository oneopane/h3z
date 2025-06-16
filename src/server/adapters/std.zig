//! Standard library HTTP server adapter for H3 framework
//! Provides synchronous I/O using Zig's standard library

const std = @import("std");
const H3App = @import("../../core/app.zig").H3;
const H3Event = @import("../../core/event.zig").H3Event;
const HttpMethod = @import("../../http/method.zig").HttpMethod;
const ServeOptions = @import("../config.zig").ServeOptions;
const AdapterInfo = @import("../adapter.zig").AdapterInfo;
const AdapterFeatures = @import("../adapter.zig").AdapterFeatures;
const IOModel = @import("../adapter.zig").IOModel;
const ConnectionContext = @import("../adapter.zig").ConnectionContext;
const ProcessResult = @import("../adapter.zig").ProcessResult;

/// Standard library HTTP server adapter
pub const StdAdapter = struct {
    allocator: std.mem.Allocator,
    app: *H3App,
    listener: ?std.net.Server = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread_pool: ?*std.Thread.Pool = null,

    const Self = @This();

    /// Initialize the adapter
    pub fn init(allocator: std.mem.Allocator, app: *H3App) Self {
        return Self{
            .allocator = allocator,
            .app = app,
        };
    }

    /// Start listening for connections
    pub fn listen(self: *Self, options: ServeOptions) !void {
        try options.validate();

        const address = try std.net.Address.parseIp(options.host, options.port);
        self.listener = try address.listen(.{
            .reuse_address = options.adapter.std.reuse_address,
            .reuse_port = options.adapter.std.reuse_port,
        });

        // Initialize thread pool if requested
        if (options.adapter.std.use_thread_pool and options.getWorkerCount() > 1) {
            var pool = try self.allocator.create(std.Thread.Pool);
            try pool.init(.{
                .allocator = self.allocator,
                .n_jobs = options.getWorkerCount(),
            });
            self.thread_pool = pool;
        }

        self.running.store(true, .monotonic);

        const url = try options.getUrl(self.allocator);
        defer self.allocator.free(url);
        std.log.info("H3 server listening on {s} (std adapter)", .{url});

        // Main accept loop
        while (self.running.load(.monotonic)) {
            const connection = self.listener.?.accept() catch |err| switch (err) {
                error.SocketNotListening => break,
                else => {
                    std.log.err("Failed to accept connection: {}", .{err});
                    continue;
                },
            };

            if (self.thread_pool) |pool| {
                // Handle connection in thread pool
                const job = ConnectionJob{
                    .adapter = self,
                    .connection = connection,
                    .options = options,
                };
                try pool.spawn(ConnectionJob.run, .{job});
            } else {
                // Handle connection synchronously
                self.handleConnection(connection, options) catch |err| {
                    std.log.err("Failed to handle connection: {}", .{err});
                };
            }
        }

        std.log.info("H3 server stopped", .{});
    }

    /// Stop the server gracefully
    pub fn stop(self: *Self) void {
        self.running.store(false, .monotonic);

        if (self.listener) |*listener| {
            listener.deinit();
            self.listener = null;
        }

        if (self.thread_pool) |pool| {
            pool.deinit();
            self.allocator.destroy(pool);
            self.thread_pool = null;
        }
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        self.stop();
    }

    /// Get adapter information
    pub fn info(self: *Self) AdapterInfo {
        _ = self;
        return AdapterInfo{
            .name = "std",
            .version = "1.0.0",
            .features = AdapterFeatures{
                .ssl = false, // TODO: Add SSL support
                .http2 = false,
                .websocket = false,
                .keep_alive = true,
                .compression = false, // TODO: Add compression support
                .streaming = true,
            },
            .io_model = .sync,
        };
    }

    /// Handle a single connection
    fn handleConnection(self: *Self, connection: std.net.Server.Connection, options: ServeOptions) !void {
        defer connection.stream.close();

        const ctx = ConnectionContext{
            .allocator = self.allocator,
            .remote_address = connection.address,
            .local_address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 3000), // Placeholder
            .start_time = std.time.timestamp(),
        };

        var request_count: u32 = 0;
        const max_requests = options.keep_alive.max_requests;
        const keep_alive_enabled = options.keep_alive.enabled;

        while (request_count < max_requests) {
            const result = self.processRequest(connection.stream, ctx, options) catch |err| {
                std.log.err("Error processing request: {}", .{err});
                break;
            };

            request_count += 1;

            switch (result) {
                .ok, .keep_alive => {
                    if (!keep_alive_enabled) break;
                    // Continue to next request
                },
                .close_connection, .error_occurred => break,
            }
        }
    }

    /// Process a single HTTP request
    fn processRequest(self: *Self, stream: std.net.Stream, ctx: ConnectionContext, options: ServeOptions) !ProcessResult {
        // Read request with timeout
        var buffer: [8192]u8 = undefined;
        var total_read: usize = 0;

        // Read until we have a complete HTTP request
        while (total_read < buffer.len - 1) {
            const bytes_read = stream.read(buffer[total_read..]) catch |err| {
                std.log.err("Failed to read request: {}", .{err});
                return ProcessResult.error_occurred;
            };

            if (bytes_read == 0) break; // Connection closed

            total_read += bytes_read;

            // Check for complete request (headers end with \r\n\r\n)
            if (total_read >= 4) {
                const data = buffer[0..total_read];
                if (std.mem.indexOf(u8, data, "\r\n\r\n") != null) {
                    break;
                }
            }
        }

        if (total_read == 0) {
            return ProcessResult.close_connection;
        }

        const request_data = buffer[0..total_read];

        // Create H3Event for this request
        var event = H3Event.init(ctx.allocator);
        defer event.deinit();

        // Parse HTTP request
        self.parseHttpRequest(&event, request_data) catch |err| {
            std.log.err("Failed to parse request: {}", .{err});
            event.setStatus(.bad_request);
            try event.sendText("Bad Request");
            try self.sendHttpResponse(stream, &event, options);
            return ProcessResult.close_connection;
        };

        // Handle the request through H3 app
        self.app.handle(&event) catch |err| {
            std.log.err("Error handling request: {}", .{err});
            event.setStatus(.internal_server_error);
            try event.sendText("Internal Server Error");
        };

        // Send response
        try self.sendHttpResponse(stream, &event, options);

        // Check if connection should be kept alive
        const connection_header = event.getHeader("connection");
        if (connection_header) |header| {
            if (std.ascii.eqlIgnoreCase(header, "close")) {
                return ProcessResult.close_connection;
            }
        }

        return if (options.keep_alive.enabled) ProcessResult.keep_alive else ProcessResult.close_connection;
    }

    /// Parse HTTP request from raw data
    fn parseHttpRequest(self: *Self, event: *H3Event, data: []const u8) !void {
        _ = self;

        var lines = std.mem.splitSequence(u8, data, "\r\n");

        // Parse request line
        if (lines.next()) |request_line| {
            var parts = std.mem.splitSequence(u8, request_line, " ");

            // Method
            if (parts.next()) |method_str| {
                event.request.method = HttpMethod.fromString(method_str) orelse .GET;
            }

            // URL
            if (parts.next()) |url| {
                try event.request.parseUrl(url);
            }

            // Version
            if (parts.next()) |version| {
                event.request.version = version;
            } else {
                event.request.version = "HTTP/1.1";
            }
        } else {
            return error.InvalidRequestLine;
        }

        // Parse headers
        while (lines.next()) |line| {
            if (line.len == 0) break; // End of headers

            if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
                const name = std.mem.trim(u8, line[0..colon_pos], " \t");
                const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
                try event.request.setHeader(name, value);
            }
        }

        // Parse body
        const remaining = lines.rest();
        if (remaining.len > 0) {
            event.request.setBody(remaining) catch {};
        }

        // Parse query parameters
        try event.parseQuery();
    }

    /// Send HTTP response
    fn sendHttpResponse(self: *Self, stream: std.net.Stream, event: *H3Event, options: ServeOptions) !void {
        _ = self;

        const body = event.response.body orelse "";

        // Set Content-Length if not already set
        if (event.response.getHeader("content-length") == null) {
            try event.response.setContentLength(body.len);
        }

        // Set Connection header based on keep-alive settings
        if (event.response.getHeader("connection") == null) {
            const connection_value = if (options.keep_alive.enabled) "keep-alive" else "close";
            try event.response.setHeader("Connection", connection_value);
        }

        var response_buffer: [8192]u8 = undefined;
        var fbs = std.io.fixedBufferStream(response_buffer[0..]);
        const writer = fbs.writer();

        // Status line
        try writer.print("HTTP/{s} {} {s}\r\n", .{
            event.response.version,
            event.response.status.code(),
            event.response.status.phrase(),
        });

        // Headers
        var header_iter = event.response.headers.iterator();
        while (header_iter.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // Empty line
        try writer.writeAll("\r\n");

        // Body
        if (body.len > 0) {
            try writer.writeAll(body);
        }

        // Send response
        const response_data = fbs.getWritten();
        try stream.writeAll(response_data);
    }
};

/// Connection job for thread pool
const ConnectionJob = struct {
    adapter: *StdAdapter,
    connection: std.net.Server.Connection,
    options: ServeOptions,

    fn run(self: ConnectionJob) void {
        self.adapter.handleConnection(self.connection, self.options) catch |err| {
            std.log.err("Failed to handle connection in thread pool: {}", .{err});
        };
    }
};

// Tests
test "StdAdapter.init" {
    var app = try H3App.init(std.testing.allocator);
    defer app.deinit();

    var adapter = StdAdapter.init(std.testing.allocator, &app);
    defer adapter.deinit();

    const adapter_info = adapter.info();
    try std.testing.expectEqualStrings("std", adapter_info.name);
    try std.testing.expect(adapter_info.io_model == .sync);
}

test "StdAdapter.parseHttpRequest" {
    var app = try H3App.init(std.testing.allocator);
    defer app.deinit();

    var adapter = StdAdapter.init(std.testing.allocator, &app);
    defer adapter.deinit();

    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    const request_data = "GET /api/users?page=1 HTTP/1.1\r\nHost: localhost:3000\r\nContent-Type: application/json\r\n\r\n";

    try adapter.parseHttpRequest(&event, request_data);

    try std.testing.expectEqual(HttpMethod.GET, event.request.method);
    try std.testing.expectEqualStrings("/api/users", event.request.path);
    try std.testing.expectEqualStrings("page=1", event.request.query.?);
    try std.testing.expectEqualStrings("localhost:3000", event.getHeader("host").?);
}
