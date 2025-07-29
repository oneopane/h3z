//! Server configuration for H3 framework
//! Provides comprehensive configuration options for different server adapters

const std = @import("std");

/// SSL/TLS configuration
pub const SSLConfig = struct {
    /// Certificate file path
    cert_file: []const u8,
    /// Private key file path
    key_file: []const u8,
    /// CA certificate file path (optional)
    ca_file: ?[]const u8 = null,
    /// SSL/TLS protocol versions to support
    protocols: []const SSLProtocol = &.{ .tls_1_2, .tls_1_3 },
    /// Cipher suites (empty means use defaults)
    ciphers: []const []const u8 = &.{},
    /// Verify client certificates
    verify_client: bool = false,
    /// Session timeout in seconds
    session_timeout: u32 = 300,
};

/// SSL/TLS protocol versions
pub const SSLProtocol = enum {
    tls_1_0,
    tls_1_1,
    tls_1_2,
    tls_1_3,
};

/// Compression configuration
pub const CompressionConfig = struct {
    /// Enable gzip compression
    gzip: bool = true,
    /// Enable brotli compression
    brotli: bool = false,
    /// Minimum response size to compress (bytes)
    min_size: usize = 1024,
    /// Maximum compression level (1-9 for gzip, 1-11 for brotli)
    level: u8 = 6,
    /// MIME types to compress
    mime_types: []const []const u8 = &.{
        "text/html",
        "text/css",
        "text/javascript",
        "application/javascript",
        "application/json",
        "text/xml",
        "application/xml",
    },
};

/// Rate limiting configuration
pub const RateLimitConfig = struct {
    /// Enable rate limiting
    enabled: bool = false,
    /// Maximum requests per window
    max_requests: u32 = 100,
    /// Time window in seconds
    window_seconds: u32 = 60,
    /// Burst size (requests allowed above limit)
    burst: u32 = 10,
};

/// Thread pool configuration
pub const ThreadPoolConfig = struct {
    /// Number of worker threads (0 = auto-detect)
    workers: u32 = 0,
    /// Maximum queue size for pending requests
    queue_size: u32 = 1000,
    /// Thread stack size in bytes
    stack_size: usize = 1024 * 1024, // 1MB
};

/// Keep-alive configuration
pub const KeepAliveConfig = struct {
    /// Enable keep-alive connections
    enabled: bool = true,
    /// Maximum number of requests per connection
    max_requests: u32 = 100,
    /// Connection timeout in seconds
    timeout: u32 = 30,
    /// Time to wait for next request (seconds)
    keep_alive_timeout: u32 = 5,
};

/// Logging configuration
pub const LogConfig = struct {
    /// Enable access logging
    access_log: bool = true,
    /// Enable error logging
    error_log: bool = true,
    /// Log level
    level: std.log.Level = .info,
    /// Log format
    format: LogFormat = .common,
    /// Log file path (null = stdout)
    file: ?[]const u8 = null,
};

/// Log format types
pub const LogFormat = enum {
    common, // Common Log Format
    combined, // Combined Log Format
    json, // JSON format
    custom, // Custom format
};

/// Server limits configuration
pub const LimitsConfig = struct {
    /// Maximum number of concurrent connections
    max_connections: u32 = 1000,
    /// Maximum request header size (bytes)
    max_header_size: usize = 8192,
    /// Maximum request body size (bytes)
    max_body_size: usize = 1024 * 1024, // 1MB
    /// Request timeout in seconds
    request_timeout: u32 = 30,
    /// Response timeout in seconds
    response_timeout: u32 = 30,
    /// Maximum number of headers per request
    max_headers: u32 = 100,
};

/// Main server configuration
pub const ServeOptions = struct {
    /// Server bind address
    host: []const u8 = "127.0.0.1",
    /// Server port
    port: u16 = 3000,
    /// Listen backlog size
    backlog: u32 = 128,

    /// SSL/TLS configuration
    ssl: ?SSLConfig = null,
    /// Compression configuration
    compression: CompressionConfig = .{},
    /// Rate limiting configuration
    rate_limit: RateLimitConfig = .{},
    /// Thread pool configuration
    thread_pool: ThreadPoolConfig = .{},
    /// Keep-alive configuration
    keep_alive: KeepAliveConfig = .{},
    /// Logging configuration
    logging: LogConfig = .{},
    /// Server limits configuration
    limits: LimitsConfig = .{},

    /// Adapter-specific options
    adapter: AdapterOptions = .{},

    /// Validate configuration
    pub fn validate(self: ServeOptions) !void {
        if (self.port == 0) {
            return error.InvalidPort;
        }

        if (self.host.len == 0) {
            return error.InvalidHost;
        }

        if (self.limits.max_connections == 0) {
            return error.InvalidMaxConnections;
        }

        if (self.limits.max_header_size == 0) {
            return error.InvalidMaxHeaderSize;
        }

        if (self.limits.max_body_size == 0) {
            return error.InvalidMaxBodySize;
        }

        if (self.thread_pool.workers > 1000) {
            return error.TooManyWorkers;
        }

        if (self.ssl) |ssl_config| {
            if (ssl_config.cert_file.len == 0) {
                return error.InvalidCertFile;
            }
            if (ssl_config.key_file.len == 0) {
                return error.InvalidKeyFile;
            }
        }
    }

    /// Get effective worker count
    pub fn getWorkerCount(self: ServeOptions) u32 {
        if (self.thread_pool.workers == 0) {
            const cpu_count = std.Thread.getCpuCount() catch 1;
            return @max(1, @as(u32, @intCast(cpu_count)));
        }
        return self.thread_pool.workers;
    }

    /// Check if HTTPS is enabled
    pub fn isHttps(self: ServeOptions) bool {
        return self.ssl != null;
    }

    /// Get server URL
    pub fn getUrl(self: ServeOptions, allocator: std.mem.Allocator) ![]u8 {
        const scheme = if (self.isHttps()) "https" else "http";
        const default_port: u16 = if (self.isHttps()) 443 else 80;

        if (self.port == default_port) {
            return std.fmt.allocPrint(allocator, "{s}://{s}", .{ scheme, self.host });
        } else {
            return std.fmt.allocPrint(allocator, "{s}://{s}:{d}", .{ scheme, self.host, self.port });
        }
    }
};

/// Adapter-specific configuration options
pub const AdapterOptions = struct {
    /// libxev adapter options
    libxev: LibxevAdapterOptions = .{},
};


/// libxev adapter specific options
pub const LibxevAdapterOptions = struct {
    /// Number of event loop threads
    loop_threads: u32 = 1,
    /// Use io_uring on Linux
    use_io_uring: bool = true,
    /// Use kqueue on macOS/BSD
    use_kqueue: bool = true,
    /// Use IOCP on Windows
    use_iocp: bool = true,
    /// Event batch size
    batch_size: u32 = 64,
    /// Timer resolution in milliseconds
    timer_resolution: u32 = 1,
};

/// Configuration builder for fluent API
pub const ConfigBuilder = struct {
    options: ServeOptions,

    pub fn init() ConfigBuilder {
        return ConfigBuilder{
            .options = ServeOptions{},
        };
    }

    pub fn host(self: *ConfigBuilder, host_addr: []const u8) *ConfigBuilder {
        self.options.host = host_addr;
        return self;
    }

    pub fn port(self: *ConfigBuilder, port_num: u16) *ConfigBuilder {
        self.options.port = port_num;
        return self;
    }

    pub fn ssl(self: *ConfigBuilder, ssl_config: SSLConfig) *ConfigBuilder {
        self.options.ssl = ssl_config;
        return self;
    }

    pub fn compression(self: *ConfigBuilder, comp_config: CompressionConfig) *ConfigBuilder {
        self.options.compression = comp_config;
        return self;
    }

    pub fn workers(self: *ConfigBuilder, worker_count: u32) *ConfigBuilder {
        self.options.thread_pool.workers = worker_count;
        return self;
    }

    pub fn maxConnections(self: *ConfigBuilder, max_conn: u32) *ConfigBuilder {
        self.options.limits.max_connections = max_conn;
        return self;
    }

    pub fn stackSize(self: *ConfigBuilder, stack_size: usize) *ConfigBuilder {
        self.options.thread_pool.stack_size = stack_size;
        return self;
    }

    pub fn backlog(self: *ConfigBuilder, backlog_size: u32) *ConfigBuilder {
        self.options.backlog = backlog_size;
        return self;
    }

    pub fn libxevTimerResolution(self: *ConfigBuilder, resolution_ms: u32) *ConfigBuilder {
        self.options.adapter.libxev.timer_resolution = resolution_ms;
        return self;
    }

    pub fn build(self: ConfigBuilder) !ServeOptions {
        try self.options.validate();
        return self.options;
    }
};

// Tests
test "ServeOptions default values" {
    const options = ServeOptions{};
    try std.testing.expectEqualStrings("127.0.0.1", options.host);
    try std.testing.expectEqual(@as(u16, 3000), options.port);
    try std.testing.expectEqual(@as(u32, 128), options.backlog);
    try std.testing.expect(!options.isHttps());
}

test "ServeOptions validation" {
    var options = ServeOptions{};
    try options.validate();

    // Test invalid port
    options.port = 0;
    try std.testing.expectError(error.InvalidPort, options.validate());

    // Test invalid host
    options.port = 3000;
    options.host = "";
    try std.testing.expectError(error.InvalidHost, options.validate());
}

test "ConfigBuilder fluent API" {
    const allocator = std.testing.allocator;

    var builder = ConfigBuilder.init();
    const options = try builder
        .host("0.0.0.0")
        .port(8080)
        .workers(4)
        .maxConnections(2000)
        .build();

    try std.testing.expectEqualStrings("0.0.0.0", options.host);
    try std.testing.expectEqual(@as(u16, 8080), options.port);
    try std.testing.expectEqual(@as(u32, 4), options.thread_pool.workers);
    try std.testing.expectEqual(@as(u32, 2000), options.limits.max_connections);

    const url = try options.getUrl(allocator);
    defer allocator.free(url);
    try std.testing.expectEqualStrings("http://0.0.0.0:8080", url);
}
