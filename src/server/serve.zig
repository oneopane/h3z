//! Simple HTTP server implementation for H3

const std = @import("std");
const H3 = @import("../core/app.zig").H3;
const H3Event = @import("../core/event.zig").H3Event;
const HttpMethod = @import("../http/method.zig").HttpMethod;

/// Server configuration
pub const ServeOptions = struct {
    port: u16 = 3000,
    host: []const u8 = "127.0.0.1",
    backlog: u32 = 128,
};

/// Simple HTTP server
pub const Server = struct {
    app: *H3,
    options: ServeOptions,
    allocator: std.mem.Allocator,

    pub fn init(app: *H3, options: ServeOptions, allocator: std.mem.Allocator) Server {
        return Server{
            .app = app,
            .options = options,
            .allocator = allocator,
        };
    }

    /// Start the server
    pub fn listen(self: *Server) !void {
        const address = try std.net.Address.parseIp(self.options.host, self.options.port);
        var listener = try address.listen(.{ .reuse_address = true });
        defer listener.deinit();

        std.log.info("Server listening on http://{s}:{}", .{ self.options.host, self.options.port });

        while (true) {
            const connection = listener.accept() catch |err| {
                std.log.err("Failed to accept connection: {}", .{err});
                continue;
            };

            // Handle connection in a separate thread (simplified)
            self.handleConnection(connection) catch |err| {
                std.log.err("Failed to handle connection: {}", .{err});
            };
        }
    }

    /// Handle a single connection
    fn handleConnection(self: *Server, connection: std.net.Server.Connection) !void {
        defer connection.stream.close();

        // Read request - use read() instead of readAll() for HTTP
        var buffer: [8192]u8 = undefined;
        var total_read: usize = 0;

        // Read until we have a complete HTTP request (ends with \r\n\r\n)
        while (total_read < buffer.len - 1) {
            const bytes_read = connection.stream.read(buffer[total_read..]) catch |err| {
                std.log.err("Failed to read request: {}", .{err});
                return;
            };

            if (bytes_read == 0) break; // Connection closed

            total_read += bytes_read;

            // Check if we have a complete HTTP request
            if (total_read >= 4) {
                const data = buffer[0..total_read];
                if (std.mem.indexOf(u8, data, "\r\n\r\n") != null) {
                    break; // Found end of headers
                }
            }
        }

        if (total_read == 0) {
            std.log.warn("Received empty request", .{});
            return;
        }

        const request_data = buffer[0..total_read];

        // Parse HTTP request
        var event = H3Event.init(self.allocator);
        defer event.deinit();

        self.parseHttpRequest(&event, request_data) catch |err| {
            std.log.err("Failed to parse request: {}", .{err});
            event.setStatus(.bad_request);
            try event.sendText("Bad Request");
            try self.sendHttpResponse(connection.stream, &event);
            return;
        };

        // Handle the request
        self.app.handle(&event) catch |err| {
            std.log.err("Error handling request: {}", .{err});
            event.setStatus(.internal_server_error);
            try event.sendText("Internal Server Error");
        };

        // Send response
        self.sendHttpResponse(connection.stream, &event) catch |err| {
            std.log.err("Failed to send response: {}", .{err});
        };
    }

    /// Parse HTTP request from raw data
    fn parseHttpRequest(self: *Server, event: *H3Event, data: []const u8) !void {
        _ = self;

        // Debug: log the raw request
        std.log.debug("Raw request data: {s}", .{data});

        var lines = std.mem.splitSequence(u8, data, "\r\n");

        // Parse request line
        if (lines.next()) |request_line| {
            std.log.debug("Request line: {s}", .{request_line});

            var parts = std.mem.splitSequence(u8, request_line, " ");

            // Method
            if (parts.next()) |method_str| {
                event.request.method = HttpMethod.fromString(method_str) orelse .GET;
                std.log.debug("Method: {s}", .{method_str});
            }

            // URL
            if (parts.next()) |url| {
                try event.request.parseUrl(url);
                std.log.debug("URL: {s}", .{url});
            }

            // Version (default to HTTP/1.1 if not specified)
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
            if (line.len == 0) break; // Empty line indicates end of headers

            if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
                const name = std.mem.trim(u8, line[0..colon_pos], " \t");
                const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
                try event.request.setHeader(name, value);
                std.log.debug("Header: {s}: {s}", .{ name, value });
            }
        }

        // Parse body (if any)
        const remaining = lines.rest();
        if (remaining.len > 0) {
            event.request.body = remaining;
            std.log.debug("Body length: {d}", .{remaining.len});
        }

        // Parse query parameters
        try event.parseQuery();
    }

    /// Send HTTP response
    fn sendHttpResponse(self: *Server, stream: std.net.Stream, event: *H3Event) !void {
        _ = self;

        // Ensure we have a response body
        const body = event.response.body orelse "";

        // Content-Length should already be set by response methods like setJson, setText, etc.
        // If not set, set it now
        if (event.response.getHeader("content-length") == null) {
            try event.response.setContentLength(body.len);
        }

        // Set Connection: close to ensure proper connection handling
        if (event.response.getHeader("connection") == null) {
            try event.response.setHeader("Connection", "close");
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

        // Empty line to separate headers from body
        try writer.writeAll("\r\n");

        // Body
        if (body.len > 0) {
            try writer.writeAll(body);
        }

        // Send the complete response
        const response_data = fbs.getWritten();
        try stream.writeAll(response_data);

        // Ensure data is flushed to the network
        // Note: Zig's std.net.Stream doesn't have a flush method,
        // but writeAll should handle this
    }
};

/// Start a server with the given H3 app
pub fn serve(app: *H3, options: ServeOptions) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = Server.init(app, options, allocator);
    try server.listen();
}

/// Start a server with default options
pub fn serveDefault(app: *H3) !void {
    try serve(app, ServeOptions{});
}

test "ServeOptions default values" {
    const options = ServeOptions{};
    try std.testing.expectEqual(@as(u16, 3000), options.port);
    try std.testing.expectEqualStrings("127.0.0.1", options.host);
    try std.testing.expectEqual(@as(u32, 128), options.backlog);
}

test "Server.init" {
    var app = H3.init(std.testing.allocator);
    defer app.deinit();

    const options = ServeOptions{ .port = 8080 };
    const server = Server.init(&app, options, std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 8080), server.options.port);
}

test "Server.parseHttpRequest" {
    var app = H3.init(std.testing.allocator);
    defer app.deinit();

    var server = Server.init(&app, ServeOptions{}, std.testing.allocator);
    var event = H3Event.init(std.testing.allocator);
    defer event.deinit();

    const request_data = "GET /api/users?page=1 HTTP/1.1\r\nHost: localhost:3000\r\nContent-Type: application/json\r\n\r\n";

    try server.parseHttpRequest(&event, request_data);

    try std.testing.expectEqual(HttpMethod.GET, event.request.method);
    try std.testing.expectEqualStrings("/api/users", event.request.path);
    try std.testing.expectEqualStrings("page=1", event.request.query.?);
    try std.testing.expectEqualStrings("localhost:3000", event.getHeader("host").?);
    try std.testing.expectEqualStrings("application/json", event.getHeader("content-type").?);
}
