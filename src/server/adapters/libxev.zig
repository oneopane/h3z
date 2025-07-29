//! libxev HTTP server adapter for H3 framework
//! Provides high-performance asynchronous I/O using libxev event loop

const std = @import("std");
const xev = @import("xev");

const H3App = @import("../../core/app.zig").H3App;
const H3Event = @import("../../core/event.zig").H3Event;
const HttpMethod = @import("../../http/method.zig").HttpMethod;
const ServeOptions = @import("../config.zig").ServeOptions;
const AdapterInfo = @import("../adapter.zig").AdapterInfo;
const AdapterFeatures = @import("../adapter.zig").AdapterFeatures;
const IOModel = @import("../adapter.zig").IOModel;
const ConnectionContext = @import("../adapter.zig").ConnectionContext;
const ProcessResult = @import("../adapter.zig").ProcessResult;
const logger = @import("../../util/root.zig").logger;

/// libxev HTTP server adapter
pub const LibxevAdapter = struct {
    allocator: std.mem.Allocator,
    app: *H3App,
    loop: ?xev.Loop = null,
    thread_pool: ?xev.ThreadPool = null,
    server_tcp: ?xev.TCP = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    connections: std.ArrayList(*Connection),
    accept_completion: xev.Completion = undefined,
    initialized: bool = false,
    next_conn_id: usize = 0,

    const Self = @This();

    /// Connection state for async handling
    const Connection = struct {
        tcp: xev.TCP,
        adapter: *LibxevAdapter,
        context: ConnectionContext,
        buffer: [8192]u8 = undefined,
        bytes_read: usize = 0,
        response_buffer: [8192]u8 = undefined,
        read_completion: xev.Completion = undefined,
        write_completion: xev.Completion = undefined,
        close_completion: xev.Completion = undefined,
        keep_alive: bool = false,
        keep_alive_timeout: i64 = 5, // Default 5 seconds timeout
        last_activity: i64 = 0,
        allocator: std.mem.Allocator, // Direct reference to allocator, avoiding access through adapter
        id: usize = 0,
        read_active: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        write_active: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        streaming_connection: ?*LibxevConnection = null, // For SSE support

        fn init(adapter: *LibxevAdapter, tcp: xev.TCP, remote_addr: std.net.Address) !*Connection {
            const conn = try adapter.allocator.create(Connection);
            conn.* = Connection{
                .tcp = tcp,
                .adapter = adapter,
                .allocator = adapter.allocator, // Store direct reference to allocator
                .context = ConnectionContext{
                    .allocator = adapter.allocator,
                    .remote_address = remote_addr,
                    .local_address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 3000), // Will be updated
                    .start_time = std.time.timestamp(),
                },
                .read_completion = undefined,
                .write_completion = undefined,
                .close_completion = undefined,
            };
            conn.id = adapter.next_conn_id;
            adapter.next_conn_id += 1;
            const port = remote_addr.getPort();
            logger.logDefault(.debug, .connection, "[Connection Created] Client port: {}, connection created, total connections: {}", .{ port, adapter.connections.items.len + 1 });
            return conn;
        }

        fn deinit(self: *Connection) void {
            // Clean up streaming connection if exists
            if (self.streaming_connection) |conn| {
                conn.deinit();
                self.allocator.destroy(conn);
                self.streaming_connection = null;
            }
            
            // Safely log connection destruction info without accessing any object properties
            logger.logDefault(.debug, .connection, "[Connection Destroy] Connection memory about to be freed", .{});
            // Note: Actual memory deallocation is handled in onCloseCallback
        }

        /// Process HTTP request and send response
        fn processHttpRequest(self: *Connection, loop: *xev.Loop) !void {
            const start_time = std.time.milliTimestamp();
            const request_data = self.buffer[0..self.bytes_read];

            // Try to acquire event from pool, fallback to direct allocation
            var event: *H3Event = undefined;
            var use_pool = false;

            // Try to acquire event from memory manager's event pool
            event = self.adapter.app.memory_manager.acquireEvent() catch blk: {
                // Limit total connections even without pool
                if (self.adapter.connections.items.len > 1000) {
                    logger.logDefault(.warn, .connection, "[Connection Limit] Maximum connection limit reached (1000), rejecting new request", .{});
                    return error.TooManyConnections;
                }
                const new_event = try self.context.allocator.create(H3Event);
                new_event.* = H3Event.init(self.context.allocator);
                break :blk new_event;
            };
            
            // Set use_pool flag based on memory manager's pool availability
            use_pool = self.adapter.app.memory_manager.event_pool != null;

            defer {
                if (use_pool) {
                    self.adapter.app.memory_manager.releaseEvent(event);
                } else {
                    event.deinit();
                    self.context.allocator.destroy(event);
                }
            }

            // Parse HTTP request
            self.parseHttpRequest(event, request_data) catch |err| {
                logger.logDefault(.err, .request, "Failed to parse HTTP request: {}", .{err});
                event.setStatus(.bad_request);
                try event.sendText("Bad Request");
                self.sendHttpResponse(loop, event);
                return;
            };

            // Handle the request through H3 app
            self.adapter.app.handle(event) catch |err| {
                logger.logDefault(.err, .request, "Error handling request: {}", .{err});
                event.setStatus(.internal_server_error);
                try event.sendText("Internal Server Error");
            };

            // Check if this request started SSE mode
            if (event.sse_started) {
                logger.logDefault(.debug, .connection, "SSE mode detected, setting up streaming connection", .{});
                
                // Create streaming connection if not already created
                const stream_conn = try self.createStreamingConnection(loop);
                
                // Convert to SSEConnection and link to event
                const sse_conn = try self.allocator.create(@import("../sse_connection.zig").SSEConnection);
                sse_conn.* = stream_conn.toSSEConnection();
                event.sse_connection = sse_conn;
                
                // Send SSE headers immediately
                try self.sendSSEHeaders(loop, event);
                
                // Check for streaming handlers (new typed system) or legacy callback
                if (event.sse_typed_handler) |typed_handler| {
                    // Create SSE writer
                    const writer = try event.allocator.create(@import("../../http/sse.zig").SSEWriter);
                    writer.* = @import("../../http/sse.zig").SSEWriter.init(event.allocator, sse_conn);
                    
                    // Schedule typed handler execution
                    try self.scheduleTypedSSEHandler(loop, typed_handler, event.sse_handler_type, writer, event.allocator);
                } else if (event.sse_callback) |callback| {
                    // Legacy callback support
                    const writer = try event.allocator.create(@import("../../http/sse.zig").SSEWriter);
                    writer.* = @import("../../http/sse.zig").SSEWriter.init(event.allocator, sse_conn);
                    
                    // Schedule callback execution
                    try self.scheduleSSECallback(loop, callback, writer, event.allocator);
                }
                
                // Skip normal response flow for SSE
                return;
            }

            // Check if Keep-Alive is supported
            const connection_header = event.request.headers.get("Connection") orelse "";
            if (std.mem.eql(u8, connection_header, "keep-alive")) {
                // Set keep-alive response header
                try event.response.headers.put("Connection", "keep-alive");
                try event.response.headers.put("Keep-Alive", "timeout=5, max=100");

                // Mark connection as keep-alive
                self.keep_alive = true;
                self.last_activity = std.time.timestamp();
            } else {
                self.keep_alive = false;
            }

            // Send response
            self.sendHttpResponse(loop, event);

            // Log request processing time
            const end_time = std.time.milliTimestamp();
            const elapsed_ms = end_time - start_time;

            if (elapsed_ms > 100) {
                logger.logDefault(.warn, .performance, "[Slow Request] Request processing took {}ms, method: {s}", .{ elapsed_ms, @tagName(event.request.method) });
            } else {
                logger.logDefault(.debug, .request, "[Request Processing] Request completed, took {}ms, method: {s}", .{ elapsed_ms, @tagName(event.request.method) });
            }

            // Log memory usage (every 100 requests)
            self.context.request_count += 1;
            if (self.context.request_count % 100 == 0) {
                // Here we can only output active connection count as an indirect indicator of memory usage
                logger.logDefault(.info, .performance, "[Resource Usage] Current active connections: {}, processed requests: {}", .{ self.adapter.connections.items.len, self.context.request_count });
            }
        }

        /// Parse HTTP request from raw data
        fn parseHttpRequest(self: *Connection, event: *H3Event, data: []const u8) !void {
            _ = self;

            var lines = std.mem.splitSequence(u8, data, "\r\n");

            // Parse request line
            if (lines.next()) |request_line| {
                var parts = std.mem.splitSequence(u8, request_line, " ");

                if (parts.next()) |method_str| {
                    event.request.method = HttpMethod.fromString(method_str) orelse .GET;
                }

                if (parts.next()) |url| {
                    try event.request.parseUrl(url);
                }

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
                if (line.len == 0) break;

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

            try event.parseQuery();
        }

        /// Send HTTP response
        fn sendHttpResponse(self: *Connection, loop: *xev.Loop, event: *H3Event) void {
            const body = event.response.body orelse "";

            // Set Content-Length if not already set
            if (event.response.getHeader("content-length") == null) {
                event.response.setContentLength(body.len) catch {};
            }

            // Set Connection header
            if (event.response.getHeader("connection") == null) {
                event.response.setHeader("Connection", "close") catch {};
            }

            // Format HTTP response
            var response_buffer: [8192]u8 = undefined;
            var fbs = std.io.fixedBufferStream(response_buffer[0..]);
            const writer = fbs.writer();

            // Status line
            writer.print("HTTP/{s} {} {s}\r\n", .{
                event.response.version,
                event.response.status.code(),
                event.response.status.phrase(),
            }) catch {};

            // Headers
            var header_iter = event.response.headers.iterator();
            while (header_iter.next()) |entry| {
                writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* }) catch {};
            }

            // Empty line
            writer.writeAll("\r\n") catch {};

            // Body
            if (body.len > 0) {
                writer.writeAll(body) catch {};
            }

            // Send response
            const response_data = fbs.getWritten();
            self.sendResponse(loop, response_data);
        }

        /// Start reading from this connection
        fn startRead(self: *Connection, loop: *xev.Loop) void {
            // Use the TCP read method instead of manual completion
            self.read_active.store(true, .seq_cst);
            logger.logDefault(.debug, .general, "[SUBMIT READ] conn_id={}", .{self.id});
            self.tcp.read(loop, &self.read_completion, .{ .slice = &self.buffer }, Connection, self, onReadCallback);
        }

        /// Send HTTP response
        fn sendResponse(self: *Connection, loop: *xev.Loop, response_data: []const u8) void {
            // Copy response to buffer
            const len = @min(response_data.len, self.response_buffer.len);
            @memcpy(self.response_buffer[0..len], response_data[0..len]);

            // Use the TCP write method
            self.write_active.store(true, .seq_cst);
            logger.logDefault(.debug, .general, "[SUBMIT WRITE] conn_id={}, compl_ptr=0x{x}", .{ self.id, @intFromPtr(&self.write_completion) });
            self.tcp.write(loop, &self.write_completion, .{ .slice = self.response_buffer[0..len] }, Connection, self, onWriteCallback);
        }

        /// Close the connection
        fn close(self: *Connection, loop: *xev.Loop) void {
            // Use atomic operation to mark connection state, prevent duplicate close
            const old_value = @atomicRmw(u32, &self.context.request_count, .Xchg, std.math.maxInt(u32), .seq_cst);
            if (old_value == std.math.maxInt(u32)) {
                logger.logDefault(.debug, .connection, "[Connection] Already closing, skipping duplicate close", .{});
                return; // Already closing
            }

            // Remove from connection list before closing to avoid race conditions during callback
            logger.logDefault(.debug, .connection, "[Connection] Removing from connection list", .{});

            // Use a separate scope to ensure thread safety during list modification
            {
                var found = false;
                var i: usize = 0;
                while (i < self.adapter.connections.items.len) : (i += 1) {
                    if (self.adapter.connections.items[i] == self) {
                        _ = self.adapter.connections.swapRemove(i);
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    logger.logDefault(.warn, .connection, "[Connection] Connection not found in list during close", .{});
                } else {
                    logger.logDefault(.debug, .connection, "[Connection] Successfully removed from connection list, remaining: {}", .{self.adapter.connections.items.len});
                }
            }

            // Safely close the TCP connection
            logger.logDefault(.debug, .connection, "[Connection] Closing connection", .{});

            // Use asynchronous close to avoid state conflicts
            self.tcp.close(loop, &self.close_completion, Connection, self, onCloseCallback);
        }

        /// Check if connection has timed out
        fn isTimedOut(self: *Connection) bool {
            const current_time = std.time.timestamp();
            const connection_age = current_time - self.context.start_time;
            return connection_age > 30; // 30 seconds timeout
        }

        /// Create a streaming connection for SSE
        fn createStreamingConnection(self: *Connection, loop: *xev.Loop) !*LibxevConnection {
            if (self.streaming_connection) |conn| {
                return conn;
            }
            
            const conn = try LibxevConnection.init(self.allocator, self.tcp, loop);
            conn.enableStreamingMode();
            self.streaming_connection = conn;
            
            // Mark this connection to stay alive even after response
            self.keep_alive = true;
            
            return conn;
        }

        /// Send SSE headers without body
        fn sendSSEHeaders(self: *Connection, loop: *xev.Loop, event: *H3Event) !void {
            var buffer: [1024]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buffer);
            const writer = fbs.writer();
            
            // Status line
            try writer.print("HTTP/{s} 200 OK\r\n", .{event.response.version});
            
            // Headers
            var header_iter = event.response.headers.iterator();
            while (header_iter.next()) |entry| {
                try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            
            // Empty line to end headers
            try writer.writeAll("\r\n");
            
            // Send immediately
            const response_data = fbs.getWritten();
            
            // Send headers through the streaming connection instead of regular connection
            if (self.streaming_connection) |stream_conn| {
                try stream_conn.writeChunk(response_data);
                logger.logDefault(.debug, .connection, "SSE headers sent through streaming connection, {} bytes", .{response_data.len});
            } else {
                // Fallback to regular send
                self.sendResponse(loop, response_data);
                logger.logDefault(.debug, .connection, "SSE headers sent through regular connection, {} bytes", .{response_data.len});
            }
        }

        /// Schedule SSE callback for execution - updated for typed handler system
        fn scheduleSSECallback(
            self: *Connection,
            loop: *xev.Loop,
            callback: @import("../../core/event.zig").SSEStreamCallback,
            writer: *@import("../../http/sse.zig").SSEWriter,
            allocator: std.mem.Allocator,
        ) !void {
            _ = self; // Unused but kept for consistency
            // Create a task for the legacy callback
            const task = try allocator.create(SSECallbackTask);
            task.* = .{
                .callback = callback,
                .typed_handler = null, // No typed handler for legacy callback
                .handler_type = .stream, // Default to stream for legacy
                .writer = writer,
                .loop = loop,
                .allocator = allocator,
            };
            
            // Create a timer that fires immediately (0 ms)
            const timer = try xev.Timer.init();
            
            // Schedule for immediate execution
            const completion = try allocator.create(xev.Completion);
            timer.run(loop, completion, 0, SSECallbackTask, task, executeSSECallback);
            logger.logDefault(.debug, .connection, "SSE callback scheduled for execution", .{});
        }
        
        /// Schedule typed SSE handler for execution
        fn scheduleTypedSSEHandler(
            self: *Connection,
            loop: *xev.Loop,
            typed_handler: @import("../../core/handler.zig").TypedHandler,
            handler_type: @import("../../core/handler.zig").HandlerType,
            writer: *@import("../../http/sse.zig").SSEWriter,
            allocator: std.mem.Allocator,
        ) !void {
            _ = self; // Unused but kept for consistency
            // Create a task for the typed handler
            const task = try allocator.create(SSECallbackTask);
            
            // Create a dummy callback for compatibility
            const dummy_callback = struct {
                fn callback(w: *@import("../../http/sse.zig").SSEWriter) !void {
                    _ = w;
                    // This should never be called when typed_handler is set
                }
            }.callback;
            
            task.* = .{
                .callback = dummy_callback,
                .typed_handler = typed_handler,
                .handler_type = handler_type,
                .writer = writer,
                .loop = loop,
                .allocator = allocator,
            };
            
            // Create a timer that fires immediately (0 ms)
            const timer = try xev.Timer.init();
            
            // Schedule for immediate execution
            const completion = try allocator.create(xev.Completion);
            timer.run(loop, completion, 0, SSECallbackTask, task, executeSSECallback);
            logger.logDefault(.debug, .connection, "Typed SSE handler scheduled for execution, type: {}", .{handler_type});
        }
    };

    /// Task structure for SSE callbacks - updated for typed handler system
    const SSECallbackTask = struct {
        callback: @import("../../core/event.zig").SSEStreamCallback, // Legacy callback
        typed_handler: ?@import("../../core/handler.zig").TypedHandler = null, // New typed handler
        handler_type: @import("../../core/handler.zig").HandlerType = .stream, // Handler type for dispatch
        writer: *@import("../../http/sse.zig").SSEWriter,
        loop: *xev.Loop, // Add loop reference for stream_with_loop handlers
        allocator: std.mem.Allocator,
    };

    /// Execute the SSE callback - updated for typed handler system
    fn executeSSECallback(
        userdata: ?*SSECallbackTask,
        loop: *xev.Loop,
        c: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        // Handle timer errors
        _ = result catch |err| {
            logger.logDefault(.err, .connection, "Timer error in SSE callback: {}", .{err});
            return .disarm;
        };
        
        const task = userdata.?;
        const allocator = task.allocator;
        defer allocator.destroy(task);
        defer allocator.destroy(c);
        
        // Execute the handler based on type
        logger.logDefault(.debug, .connection, "Executing SSE streaming callback, handler type: {}", .{task.handler_type});
        
        // Use typed handler if available, otherwise fall back to legacy callback
        if (task.typed_handler) |typed_handler| {
            switch (typed_handler) {
                .stream => |handler_fn| {
                    handler_fn(task.writer) catch |err| {
                        logger.logDefault(.err, .connection, "SSE stream handler error: {}", .{err});
                        task.writer.close();
                    };
                },
                .stream_with_loop => |handler_fn| {
                    handler_fn(task.writer, loop) catch |err| {
                        logger.logDefault(.err, .connection, "SSE stream_with_loop handler error: {}", .{err});
                        task.writer.close();
                    };
                },
                .regular => {
                    logger.logDefault(.err, .connection, "Regular handler cannot be used for SSE streaming", .{});
                    task.writer.close();
                },
            }
        } else {
            // Legacy callback support
            task.callback(task.writer) catch |err| {
                logger.logDefault(.err, .connection, "SSE streaming callback error: {}", .{err});
                task.writer.close();
            };
        }
        
        return .disarm;
    }

    /// Initialize the adapter
    pub fn init(allocator: std.mem.Allocator, app: *H3App) Self {
        return Self{
            .allocator = allocator,
            .app = app,
            .connections = std.ArrayList(*Connection).init(allocator),
        };
    }

    /// Initialize libxev components with specific configuration
    fn initLibxev(self: *Self, options: ServeOptions) !void {
        if (self.initialized) return; // Already initialized

        // Get effective worker count from configuration
        const worker_count = options.getWorkerCount();
        const stack_size = options.thread_pool.stack_size;

        logger.logDefault(.info, .general, "Initializing libxev with {} worker threads, {}KB stack size", .{
            worker_count,
            stack_size / 1024,
        });

        // Create thread pool for libxev operations with configured parameters
        self.thread_pool = xev.ThreadPool.init(.{
            .max_threads = worker_count,
            .stack_size = @intCast(stack_size), // Convert usize to u32
        });

        self.loop = xev.Loop.init(.{
            .thread_pool = &self.thread_pool.?,
        }) catch |err| {
            logger.logDefault(.err, .general, "Failed to initialize libxev loop: {}", .{err});
            if (self.thread_pool) |*tp| tp.deinit();
            return err;
        };

        self.initialized = true;
        logger.logDefault(.debug, .general, "libxev components initialized successfully", .{});
    }

    /// Start listening for connections
    pub fn listen(self: *Self, options: ServeOptions) !void {
        try options.validate();

        // Initialize libxev components with configuration
        try self.initLibxev(options);

        const address = try std.net.Address.parseIp(options.host, options.port);

        // Create and bind TCP server
        self.server_tcp = try xev.TCP.init(address);
        try self.server_tcp.?.bind(address);
        try self.server_tcp.?.listen(@intCast(options.backlog));

        self.running.store(true, .monotonic);

        const url = try options.getUrl(self.allocator);
        defer self.allocator.free(url);

        // Log configuration details
        logger.logDefault(.info, .general, "H3 server listening on {s} (libxev adapter)", .{url});
        logger.logDefault(.info, .general, "Configuration: {} workers, max {} connections, {}KB stack", .{
            options.getWorkerCount(),
            options.limits.max_connections,
            options.thread_pool.stack_size / 1024,
        });

        // Start accepting connections
        self.startAccept();

        // Run event loop with configured parameters
        var last_cleanup = std.time.timestamp();
        while (self.running.load(.monotonic)) {
            // Use .until_done to process all available events
            try self.loop.?.run(.until_done);

            // Periodic cleanup of timed out connections
            const current_time = std.time.timestamp();
            if (current_time - last_cleanup > 10) { // Cleanup every 10 seconds
                self.cleanupTimedOutConnections();
                last_cleanup = current_time;
            }

            // Small sleep to prevent busy waiting (configurable via libxev options)
            const sleep_time = if (options.adapter.libxev.timer_resolution > 0)
                options.adapter.libxev.timer_resolution * 1_000_000 // Convert ms to ns
            else
                1_000_000; // Default 1ms
            std.time.sleep(sleep_time);
        }

        logger.logDefault(.info, .general, "H3 server stopped", .{});
    }

    /// Clean up timed out connections
    fn cleanupTimedOutConnections(self: *Self) void {
        var i: usize = 0;
        while (i < self.connections.items.len) {
            const conn = self.connections.items[i];
            if (conn.isTimedOut()) {
                logger.logDefault(.debug, .connection, "Cleaning up timed out connection", .{});
                if (self.loop) |*loop| {
                    conn.close(loop);
                }
                // Connection will be removed from list in onCloseCallback
            }
            i += 1;
        }
    }

    /// Stop the server gracefully
    pub fn stop(self: *Self) void {
        self.running.store(false, .monotonic);

        // Close server socket
        if (self.server_tcp) |*server| {
            // Note: In a real implementation, we'd use async close with completion
            // For now, we'll let the loop cleanup handle it
            _ = server;
        }

        // Close all connections
        for (self.connections.items) |conn| {
            conn.deinit();
        }
        self.connections.clearAndFree();

        // Note: libxev Loop doesn't have a stop() method
        // The event loop will exit when running flag is false
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        self.stop();

        // Cleanup libxev components if initialized
        if (self.loop) |*loop| {
            loop.deinit();
        }
        if (self.thread_pool) |*thread_pool| {
            thread_pool.deinit();
        }

        self.connections.deinit();
        self.initialized = false;
    }

    /// Get adapter information
    pub fn info(self: *Self) AdapterInfo {
        _ = self;

        logger.logDefault(.info, .general, "Using real libxev - High-performance async I/O with configurable thread pool", .{});

        return AdapterInfo{
            .name = "libxev",
            .version = "0.1.0", // Keep consistent with test expectations
            .features = AdapterFeatures{
                .ssl = false, // TODO: Add SSL support
                .http2 = false,
                .websocket = false,
                .keep_alive = true,
                .compression = false, // TODO: Add compression support
                .streaming = true, // Real streaming with libxev
            },
            .io_model = .async_single,
        };
    }

    /// Create a streaming connection for SSE
    pub fn createConnection(self: *Self, tcp: xev.TCP) !*@import("../sse_connection.zig").SSEConnection {
        if (self.loop) |loop| {
            const libxev_conn = try LibxevConnection.init(self.allocator, tcp, loop);
            const conn = try self.allocator.create(@import("../sse_connection.zig").SSEConnection);
            conn.* = .{ .libxev = libxev_conn };
            return conn;
        }
        return error.LoopNotInitialized;
    }

    /// Start accepting new connections
    fn startAccept(self: *Self) void {
        if (self.server_tcp) |*server| {
            if (self.loop) |*loop| {
                // Use the TCP accept method instead of manual completion
                server.accept(loop, &self.accept_completion, Self, self, onAcceptCallback);
            }
        }
    }

    /// Handle new connection acceptance
    fn onAcceptCallback(
        self_opt: ?*Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.AcceptError!xev.TCP,
    ) xev.CallbackAction {
        _ = completion;

        const self = self_opt orelse {
            logger.logDefault(.err, .general, "Accept callback called with null self pointer", .{});
            return .rearm;
        };

        const client_tcp = result catch |err| {
            logger.logDefault(.err, .connection, "Failed to accept connection: {}", .{err});
            return .rearm;
        };

        // Enforce maximum concurrent connection limit
        if (self.connections.items.len >= 1000) {
            logger.logDefault(.warn, .connection, "[Connection Limit] Maximum connection limit reached (1000), rejecting new connection", .{});

            // Allocate a completion object for this close; handle OOM without propagating error
            const comp_ptr = self.allocator.create(xev.Completion) catch {
                logger.logDefault(.err, .connection, "[Reject Connection] Out of memory allocating completion", .{});
                var tmp_comp: xev.Completion = undefined;
                client_tcp.close(loop, &tmp_comp, void, null, struct {
                    fn callback(_: ?*void, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.CloseError!void) xev.CallbackAction {
                        return .disarm;
                    }
                }.callback);
                return .rearm;
            };

            const reject_cb = struct {
                fn callback(alloc_ptr_opt: ?*std.mem.Allocator, _: *xev.Loop, comp: *xev.Completion, _: xev.TCP, close_res: xev.CloseError!void) xev.CallbackAction {
                    close_res catch |err| {
                        logger.logDefault(.err, .connection, "[Reject Connection] Close error: {}", .{err});
                    };
                    const alloc_ptr = alloc_ptr_opt orelse return .disarm;
                    alloc_ptr.destroy(comp);
                    logger.logDefault(.debug, .connection, "[Reject Connection] Successfully closed rejected connection", .{});
                    return .disarm;
                }
            }.callback;

            client_tcp.close(loop, comp_ptr, std.mem.Allocator, &self.allocator, reject_cb);
            return .rearm;
        }

        logger.logDefault(.debug, .connection, "New connection accepted", .{});

        // Create connection for the new client
        const remote_addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 0); // TODO: Get real remote address
        const conn = Connection.init(self, client_tcp, remote_addr) catch |err| {
            logger.logDefault(.err, .connection, "Failed to create connection: {}", .{err});
            return .rearm; // Continue accepting
        };

        // Add to connections list
        self.connections.append(conn) catch |err| {
            logger.logDefault(.err, .connection, "Failed to add connection: {}", .{err});
            conn.deinit();
            return .rearm; // Continue accepting
        };

        // Start reading from the connection
        conn.startRead(loop);

        logger.logDefault(.debug, .connection, "Connection established, total connections: {}", .{self.connections.items.len});

        // Continue accepting new connections
        return .rearm;
    }

    /// Handle data received from connection
    fn onReadCallback(
        conn_opt: ?*Connection,
        loop: *xev.Loop,
        completion: *xev.Completion,
        tcp: xev.TCP,
        buffer: xev.ReadBuffer,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        _ = tcp;
        _ = buffer;

        const conn = conn_opt orelse {
            logger.logDefault(.err, .connection, "Read callback called with null connection pointer", .{});
            return .disarm;
        };
        conn.read_active.store(false, .seq_cst);
        logger.logDefault(.debug, .general, "[CB READ] conn_id={}, compl_ptr=0x{x}", .{ conn.id, @intFromPtr(completion) });
        const bytes_read = result catch |err| {
            switch (err) {
                error.EOF, error.ConnectionResetByPeer, error.BrokenPipe, error.ConnectionTimedOut => {
                    logger.logDefault(.debug, .connection, "Connection closed: {}", .{err});
                },
                else => {
                    logger.logDefault(.err, .connection, "Read failed: {}", .{err});
                },
            }
            conn.close(loop);
            return .disarm;
        };

        // Handle empty read (connection closed gracefully)
        if (bytes_read == 0) {
            logger.logDefault(.debug, .connection, "Connection closed gracefully (empty read)", .{});
            conn.close(loop);
            return .disarm;
        }

        logger.logDefault(.debug, .connection, "Received {} bytes from connection", .{bytes_read});
        conn.bytes_read = bytes_read;

        // Process HTTP request
        conn.processHttpRequest(loop) catch |err| {
            logger.logDefault(.err, .request, "Error processing request: {}", .{err});
            return .disarm;
        };

        return .disarm;
    }

    /// Handle response sent to connection
    fn onWriteCallback(
        conn_opt: ?*Connection,
        loop: *xev.Loop,
        completion: *xev.Completion,
        tcp: xev.TCP,
        buffer: xev.WriteBuffer,
        result: xev.WriteError!usize,
    ) xev.CallbackAction {
        _ = tcp;
        _ = buffer;
        const conn = conn_opt orelse return .disarm;
        conn.write_active.store(false, .seq_cst);
        logger.logDefault(.debug, .general, "[CB WRITE] conn_id={}, compl_ptr=0x{x}", .{ conn.id, @intFromPtr(completion) });

        // Check for write errors
        const bytes_written = result catch |err| {
            logger.logDefault(.err, .connection, "Write failed: {}", .{err});
            conn.close(loop);
            return .disarm;
        };

        logger.logDefault(.debug, .connection, "Sent {} bytes to connection", .{bytes_written});

        // Check if this connection has an associated LibxevConnection in streaming mode
        // In that case, we should keep the connection alive regardless of keep-alive header
        if (conn.streaming_connection) |stream_conn| {
            if (stream_conn.streaming_mode and !stream_conn.closed) {
                logger.logDefault(.debug, .connection, "Keeping connection alive (SSE streaming)", .{});
                // Don't start reading again for SSE connections
                return .disarm;
            }
        }

        // If it's a keep-alive connection, continue reading the next request
        if (conn.keep_alive) {
            logger.logDefault(.debug, .connection, "Keeping connection alive (Keep-Alive)", .{});
            conn.bytes_read = 0; // Reset buffer
            conn.startRead(loop); // startRead returns void, no error handling needed
            return .disarm;
        }

        // Non keep-alive connection, close it
        conn.close(loop);

        return .disarm;
    }

    /// Handle connection close
    fn onCloseCallback(
        conn_opt: ?*Connection,
        loop: *xev.Loop,
        completion: *xev.Completion,
        tcp: xev.TCP,
        result: xev.CloseError!void,
    ) xev.CallbackAction {
        _ = loop;
        _ = tcp;
        _ = completion;

        // Safely handle close errors
        result catch |err| {
            logger.logDefault(.err, .connection, "[Connection Close] Operation failed: {}", .{err});
        };

        // Safely check connection object
        if (conn_opt == null) {
            logger.logDefault(.err, .connection, "[Connection Close] Callback received null connection pointer", .{});
            return .disarm;
        }

        const conn = conn_opt.?;

        // Log connection close information
        logger.logDefault(.debug, .connection, "[Connection Close] Connection closing, port: {}", .{conn.context.remote_address.getPort()});

        // Note: Connection has already been removed from the connection list in close() function
        // No need to remove it again here, avoiding race conditions

        // Safely call deinit method
        conn.deinit();

        // Free connection memory
        conn.adapter.allocator.destroy(conn);
        logger.logDefault(.debug, .connection, "[Connection Close] Connection memory freed", .{});

        return .disarm;
    }
};

/// LibxevConnection for SSE and streaming support
/// Wraps a Connection with additional streaming capabilities
pub const LibxevConnection = struct {
    /// The underlying TCP connection
    tcp: xev.TCP,
    /// Write queue for buffering data during async operations
    write_queue: std.ArrayList([]const u8),
    /// Active write completion for tracking async writes
    write_completion: xev.Completion,
    /// Whether the connection is in streaming mode (e.g., SSE)
    streaming_mode: bool = false,
    /// Whether the connection has been closed
    closed: bool = false,
    /// Reference to the event loop
    loop: *xev.Loop,
    /// Allocator for memory management
    allocator: std.mem.Allocator,
    /// Whether a write is currently in progress
    write_in_progress: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Total bytes queued (for backpressure detection)
    bytes_queued: usize = 0,

    const MAX_QUEUE_SIZE = 64 * 1024; // 64KB max queue size for backpressure

    /// Initialize a new LibxevConnection
    pub fn init(allocator: std.mem.Allocator, tcp: xev.TCP, loop: *xev.Loop) !*LibxevConnection {
        const conn = try allocator.create(LibxevConnection);
        conn.* = LibxevConnection{
            .tcp = tcp,
            .write_queue = std.ArrayList([]const u8).init(allocator),
            .write_completion = undefined,
            .loop = loop,
            .allocator = allocator,
        };
        return conn;
    }

    /// Clean up the connection
    pub fn deinit(self: *LibxevConnection) void {
        // Free all queued writes
        for (self.write_queue.items) |data| {
            self.allocator.free(data);
        }
        self.write_queue.deinit();
    }

    /// Write a chunk of data without closing the connection
    pub fn writeChunk(self: *LibxevConnection, data: []const u8) @import("../sse_connection.zig").SSEConnectionError!void {
        logger.logDefault(.debug, .connection, "[SSE] writeChunk called: {} bytes, closed={}, streaming={}", .{ data.len, self.closed, self.streaming_mode });
        
        if (self.closed) return error.ConnectionClosed;
        if (!self.streaming_mode) return error.NotStreamingMode;

        // Check for backpressure
        if (self.bytes_queued + data.len > MAX_QUEUE_SIZE) {
            logger.logDefault(.warn, .connection, "[SSE] Buffer full: queued={}, trying to add={}, max={}", .{ self.bytes_queued, data.len, MAX_QUEUE_SIZE });
            return error.BufferFull;
        }

        // Copy data to owned memory
        const data_copy = self.allocator.alloc(u8, data.len) catch return error.AllocationError;
        @memcpy(data_copy, data);

        // Queue the data
        self.write_queue.append(data_copy) catch {
            self.allocator.free(data_copy);
            return error.AllocationError;
        };
        self.bytes_queued += data.len;

        logger.logDefault(.debug, .connection, "[SSE] Data queued: {} bytes, total queued: {}, queue size: {}", .{ data.len, self.bytes_queued, self.write_queue.items.len });
        
        // Log the first 100 bytes of the data
        const preview_len = @min(data.len, 100);
        logger.logDefault(.debug, .connection, "[SSE] Data preview: {s}", .{data[0..preview_len]});

        // If no write is in progress, start one
        if (!self.write_in_progress.swap(true, .seq_cst)) {
            self.processWriteQueue();
        }
    }

    /// Process queued writes
    fn processWriteQueue(self: *LibxevConnection) void {
        logger.logDefault(.debug, .connection, "[SSE] processWriteQueue: queue size={}, bytes_queued={}, closed={}", .{ self.write_queue.items.len, self.bytes_queued, self.closed });
        
        if (self.write_queue.items.len == 0) {
            logger.logDefault(.debug, .connection, "[SSE] Write queue empty, marking write_in_progress=false", .{});
            self.write_in_progress.store(false, .seq_cst);
            
            // If we're marked for closing and queue is empty, close now
            if (self.closed) {
                logger.logDefault(.debug, .connection, "[SSE] Queue drained, closing connection", .{});
                const completion = self.allocator.create(xev.Completion) catch {
                    logger.logDefault(.err, .connection, "[SSE] Failed to allocate close completion", .{});
                    return;
                };
                self.tcp.close(self.loop, completion, LibxevConnection, self, onCloseComplete);
            }
            return;
        }

        // Get the next chunk to write
        const data = self.write_queue.items[0];
        logger.logDefault(.debug, .connection, "[SSE] Writing chunk: {} bytes", .{data.len});
        
        // Allocate a new completion for this write
        const completion = self.allocator.create(xev.Completion) catch {
            logger.logDefault(.err, .connection, "[SSE] Failed to allocate completion", .{});
            self.write_in_progress.store(false, .seq_cst);
            return;
        };
        
        // Start async write
        self.tcp.write(self.loop, completion, .{ .slice = data }, LibxevConnection, self, onWriteComplete);
    }

    /// Handle write completion
    fn onWriteComplete(
        conn_opt: ?*LibxevConnection,
        loop: *xev.Loop,
        completion: *xev.Completion,
        tcp: xev.TCP,
        buffer: xev.WriteBuffer,
        result: xev.WriteError!usize,
    ) xev.CallbackAction {
        _ = loop;
        _ = tcp;
        _ = buffer;

        const conn = conn_opt orelse return .disarm;
        
        // Free the completion object
        defer conn.allocator.destroy(completion);

        // Check for write errors
        const bytes_written = result catch |err| {
            logger.logDefault(.err, .connection, "[SSE] Write error: {}", .{err});
            logger.logDefault(.err, .connection, "SSE write failed: {}", .{err});
            conn.closed = true;
            conn.write_in_progress.store(false, .seq_cst);
            return .disarm;
        };

        logger.logDefault(.debug, .connection, "[SSE] Write complete: {} bytes written", .{bytes_written});
        
        // Remove the written data from queue
        if (conn.write_queue.items.len > 0) {
            const written_data = conn.write_queue.orderedRemove(0);
            conn.allocator.free(written_data);
            conn.bytes_queued -= bytes_written;
            logger.logDefault(.debug, .connection, "[SSE] Removed from queue, remaining: {} items, {} bytes", .{ conn.write_queue.items.len, conn.bytes_queued });
        }

        // Process next item in queue
        conn.processWriteQueue();

        return .disarm;
    }

    /// Flush any buffered data immediately
    pub fn flush(self: *LibxevConnection) @import("../sse_connection.zig").SSEConnectionError!void {
        if (self.closed) return error.ConnectionClosed;
        // In libxev, writes are already async, so this is a no-op
        // The write queue is continuously processed
    }

    /// Close the connection
    pub fn close(self: *LibxevConnection) void {
        if (!self.closed) {
            self.closed = true;
            
            // If there's data in the write queue, mark for closing after queue drains
            if (self.write_queue.items.len > 0 or self.write_in_progress.load(.seq_cst)) {
                logger.logDefault(.debug, .connection, "[SSE] Delaying close until write queue drains: {} items pending", .{self.write_queue.items.len});
                // The connection will be closed when the queue is empty
                return;
            }
            
            // No pending writes, close immediately
            const completion = self.allocator.create(xev.Completion) catch {
                logger.logDefault(.err, .connection, "[SSE] Failed to allocate close completion", .{});
                return;
            };
            self.tcp.close(self.loop, completion, LibxevConnection, self, onCloseComplete);
        }
    }

    /// Handle close completion
    fn onCloseComplete(
        conn_opt: ?*LibxevConnection,
        loop: *xev.Loop,
        completion: *xev.Completion,
        tcp: xev.TCP,
        result: xev.CloseError!void,
    ) xev.CallbackAction {
        _ = loop;
        _ = tcp;
        result catch {};

        if (conn_opt) |conn| {
            // Free the completion object
            conn.allocator.destroy(completion);
            
            conn.deinit();
            conn.allocator.destroy(conn);
        }

        return .disarm;
    }

    /// Check if the connection is still alive
    pub fn isAlive(self: *LibxevConnection) bool {
        return !self.closed;
    }

    /// Enable streaming mode for this connection
    pub fn enableStreamingMode(self: *LibxevConnection) void {
        self.streaming_mode = true;
    }

    /// Convert to SSEConnection tagged union
    pub fn toSSEConnection(self: *LibxevConnection) @import("../sse_connection.zig").SSEConnection {
        return @import("../sse_connection.zig").SSEConnection{ .libxev = self };
    }
};

// Tests
test "LibxevAdapter.init" {
    var app = try H3App.init(std.testing.allocator);
    defer app.deinit();

    var adapter = LibxevAdapter.init(std.testing.allocator, &app);
    defer adapter.deinit();

    const adapter_info = adapter.info();
    // Now we always use real libxev
    try std.testing.expectEqualStrings("libxev", adapter_info.name);
    try std.testing.expect(adapter_info.io_model == .async_single);
    try std.testing.expect(adapter_info.features.streaming);
}

test "LibxevAdapter.parseHttpRequest" {
    var app = try H3App.init(std.testing.allocator);
    defer app.deinit();

    var adapter = LibxevAdapter.init(std.testing.allocator, &app);
    defer adapter.deinit();

    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    const request_data = "GET /api/users?page=1 HTTP/1.1\r\nHost: localhost:3000\r\nContent-Type: application/json\r\n\r\n";

    // Create a dummy connection to test parseHttpRequest
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 3000);
    const tcp = try xev.TCP.init(addr);
    var conn = try LibxevAdapter.Connection.init(&adapter, tcp, addr);
    defer {
        conn.deinit();
        // Manually free the connection memory since we're not using the normal cleanup process
        adapter.allocator.destroy(conn);
    }

    try conn.parseHttpRequest(&event, request_data);

    try std.testing.expectEqual(HttpMethod.GET, event.request.method);
    try std.testing.expectEqualStrings("/api/users", event.request.path);
    try std.testing.expectEqualStrings("page=1", event.request.query.?);
    try std.testing.expectEqualStrings("localhost:3000", event.getHeader("host").?);
}

test "LibxevAdapter.info" {
    var app = try H3App.init(std.testing.allocator);
    defer app.deinit();

    var adapter = LibxevAdapter.init(std.testing.allocator, &app);
    defer adapter.deinit();

    const info = adapter.info();
    try std.testing.expectEqualStrings("libxev", info.name);
    try std.testing.expectEqualStrings("0.1.0", info.version);
    try std.testing.expect(info.io_model == .async_single);
    try std.testing.expect(info.features.streaming);
    try std.testing.expect(info.features.keep_alive);
}
