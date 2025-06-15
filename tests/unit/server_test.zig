//! Unit tests for H3 server adapters
//! Tests adapter selection, configuration, and basic functionality

const std = @import("std");
const testing = std.testing;
const h3 = @import("h3");
const test_utils = @import("test_utils");

test "Adapter type selection" {
    // Test best adapter selection
    const best = h3.server.adapter.AdapterType.getBest();
    try testing.expect(best == .libxev or best == .std);

    // Test adapter availability
    try testing.expect(h3.server.adapter.AdapterUtils.isAvailable(.std));
    try testing.expect(h3.server.adapter.AdapterUtils.isAvailable(.libxev));

    // Test adapter names
    try testing.expectEqualStrings("std", h3.server.adapter.AdapterUtils.getName(.std));
    try testing.expectEqualStrings("libxev", h3.server.adapter.AdapterUtils.getName(.libxev));
    try testing.expectEqualStrings("auto", h3.server.adapter.AdapterUtils.getName(.auto));
}

test "Adapter performance comparison" {
    const comparison = h3.server.adapter.AdapterUtils.comparePerformance(.libxev, .std);
    try testing.expect(comparison == .gt); // libxev performance comparison

    const same = h3.server.adapter.AdapterUtils.comparePerformance(.std, .std);
    try testing.expect(same == .eq);
}

test "Server configuration validation" {
    // Test valid configuration
    var valid_config = h3.server.serve.ServeOptions{
        .host = "127.0.0.1",
        .port = 3000,
        .backlog = 128,
    };
    try valid_config.validate();

    // Test invalid port
    var invalid_port = h3.server.serve.ServeOptions{
        .port = 0,
    };
    try testing.expectError(error.InvalidPort, invalid_port.validate());

    // Test invalid host
    var invalid_host = h3.server.serve.ServeOptions{
        .host = "",
        .port = 3000,
    };
    try testing.expectError(error.InvalidHost, invalid_host.validate());

    // Test too many workers
    var too_many_workers = h3.server.serve.ServeOptions{
        .thread_pool = .{ .workers = 2000 },
    };
    try testing.expectError(error.TooManyWorkers, too_many_workers.validate());
}

test "Server configuration worker count calculation" {
    // Test auto worker count (0 = auto-detect)
    var auto_config = h3.server.serve.ServeOptions{
        .thread_pool = .{ .workers = 0 },
    };
    const auto_workers = auto_config.getWorkerCount();
    try testing.expect(auto_workers >= 1);
    try testing.expect(auto_workers <= 64); // Reasonable upper bound

    // Test explicit worker count
    var explicit_config = h3.server.serve.ServeOptions{
        .thread_pool = .{ .workers = 8 },
    };
    const explicit_workers = explicit_config.getWorkerCount();
    try testing.expectEqual(@as(u32, 8), explicit_workers);
}

test "Server configuration URL generation" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    // Test HTTP URL with default port
    var http_default = h3.server.serve.ServeOptions{
        .host = "localhost",
        .port = 80,
    };
    const http_url = try http_default.getUrl(allocator);
    defer allocator.free(http_url);
    try testing.expectEqualStrings("http://localhost", http_url);

    // Test HTTP URL with custom port
    var http_custom = h3.server.serve.ServeOptions{
        .host = "127.0.0.1",
        .port = 3000,
    };
    const http_custom_url = try http_custom.getUrl(allocator);
    defer allocator.free(http_custom_url);
    try testing.expectEqualStrings("http://127.0.0.1:3000", http_custom_url);

    // Test HTTPS URL with default port
    var https_default = h3.server.serve.ServeOptions{
        .host = "example.com",
        .port = 443,
        .ssl = .{
            .cert_file = "cert.pem",
            .key_file = "key.pem",
        },
    };
    const https_url = try https_default.getUrl(allocator);
    defer allocator.free(https_url);
    try testing.expectEqualStrings("https://example.com", https_url);

    // Test HTTPS URL with custom port
    var https_custom = h3.server.serve.ServeOptions{
        .host = "secure.example.com",
        .port = 8443,
        .ssl = .{
            .cert_file = "cert.pem",
            .key_file = "key.pem",
        },
    };
    const https_custom_url = try https_custom.getUrl(allocator);
    defer allocator.free(https_custom_url);
    try testing.expectEqualStrings("https://secure.example.com:8443", https_custom_url);
}

test "Configuration builder fluent API" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    // Test fluent configuration building
    var builder = h3.server.serve.config();
    const options = try builder
        .host("0.0.0.0")
        .port(8080)
        .workers(4)
        .maxConnections(2000)
        .stackSize(2 * 1024 * 1024)
        .backlog(256)
        .libxevTimerResolution(5)
        .build();

    // Verify configuration
    try testing.expectEqualStrings("0.0.0.0", options.host);
    try testing.expectEqual(@as(u16, 8080), options.port);
    try testing.expectEqual(@as(u32, 4), options.thread_pool.workers);
    try testing.expectEqual(@as(u32, 2000), options.limits.max_connections);
    try testing.expectEqual(@as(usize, 2 * 1024 * 1024), options.thread_pool.stack_size);
    try testing.expectEqual(@as(u32, 256), options.backlog);
    try testing.expectEqual(@as(u32, 5), options.adapter.libxev.timer_resolution);

    // Test URL generation
    const url = try options.getUrl(allocator);
    defer allocator.free(url);
    try testing.expectEqualStrings("http://0.0.0.0:8080", url);
}

test "Server adapter creation and info" {
    var test_alloc = test_utils.TestAllocator.init();
    defer test_alloc.deinit();
    const allocator = test_alloc.allocator;

    var app = h3.createApp(allocator);
    defer app.deinit();

    // Test automatic adapter selection
    var auto_server = h3.server.serve.Server.init(allocator, &app);
    defer auto_server.deinit();

    const auto_info = auto_server.getAdapterInfo();
    try testing.expect(auto_info.name.len > 0);
    try testing.expect(auto_info.version.len > 0);

    // Test specific adapter selection
    var libxev_server = h3.server.serve.Server.initWithAdapter(allocator, &app, .libxev);
    defer libxev_server.deinit();

    const libxev_info = libxev_server.getAdapterInfo();
    try testing.expectEqualStrings("libxev", libxev_info.name);
    try testing.expect(libxev_info.features.streaming);

    var std_server = h3.server.serve.Server.initWithAdapter(allocator, &app, .std);
    defer std_server.deinit();

    const std_info = std_server.getAdapterInfo();
    try testing.expectEqualStrings("std", std_info.name);
}

test "Thread pool configuration validation" {
    // Test valid thread pool configurations
    const valid_config = h3.server.config.ThreadPoolConfig{
        .workers = 4,
        .queue_size = 1000,
        .stack_size = 1024 * 1024,
    };
    _ = valid_config; // Use the config

    // Test edge cases
    const min_config = h3.server.config.ThreadPoolConfig{
        .workers = 1,
        .queue_size = 1,
        .stack_size = 64 * 1024, // 64KB minimum
    };
    _ = min_config;

    const max_config = h3.server.config.ThreadPoolConfig{
        .workers = 32,
        .queue_size = 10000,
        .stack_size = 8 * 1024 * 1024, // 8MB
    };
    _ = max_config;
}

test "SSL configuration validation" {
    // Test valid SSL configuration
    const valid_ssl = h3.server.config.SSLConfig{
        .cert_file = "server.crt",
        .key_file = "server.key",
        .protocols = &.{ .tls_1_2, .tls_1_3 },
        .verify_client = false,
        .session_timeout = 300,
    };

    var ssl_options = h3.server.serve.ServeOptions{
        .ssl = valid_ssl,
    };
    try ssl_options.validate();

    // Test invalid SSL configuration (empty cert file)
    const invalid_ssl = h3.server.config.SSLConfig{
        .cert_file = "",
        .key_file = "server.key",
    };

    var invalid_ssl_options = h3.server.serve.ServeOptions{
        .ssl = invalid_ssl,
    };
    try testing.expectError(error.InvalidCertFile, invalid_ssl_options.validate());

    // Test invalid SSL configuration (empty key file)
    const invalid_key_ssl = h3.server.config.SSLConfig{
        .cert_file = "server.crt",
        .key_file = "",
    };

    var invalid_key_options = h3.server.serve.ServeOptions{
        .ssl = invalid_key_ssl,
    };
    try testing.expectError(error.InvalidKeyFile, invalid_key_options.validate());
}

test "Compression configuration" {
    // Test default compression config
    const default_compression = h3.server.config.CompressionConfig{};
    try testing.expect(default_compression.gzip);
    try testing.expect(!default_compression.brotli);
    try testing.expectEqual(@as(usize, 1024), default_compression.min_size);
    try testing.expectEqual(@as(u8, 6), default_compression.level);

    // Test custom compression config
    const custom_compression = h3.server.config.CompressionConfig{
        .gzip = true,
        .brotli = true,
        .min_size = 512,
        .level = 9,
        .mime_types = &.{
            "text/html",
            "application/json",
            "text/css",
        },
    };
    try testing.expect(custom_compression.gzip);
    try testing.expect(custom_compression.brotli);
    try testing.expectEqual(@as(usize, 512), custom_compression.min_size);
    try testing.expectEqual(@as(u8, 9), custom_compression.level);
    try testing.expectEqual(@as(usize, 3), custom_compression.mime_types.len);
}

test "Rate limiting configuration" {
    // Test default rate limiting (disabled)
    const default_rate_limit = h3.server.config.RateLimitConfig{};
    try testing.expect(!default_rate_limit.enabled);

    // Test enabled rate limiting
    const enabled_rate_limit = h3.server.config.RateLimitConfig{
        .enabled = true,
        .max_requests = 100,
        .window_seconds = 60,
        .burst = 10,
    };
    try testing.expect(enabled_rate_limit.enabled);
    try testing.expectEqual(@as(u32, 100), enabled_rate_limit.max_requests);
    try testing.expectEqual(@as(u32, 60), enabled_rate_limit.window_seconds);
    try testing.expectEqual(@as(u32, 10), enabled_rate_limit.burst);
}

test "Keep-alive configuration" {
    // Test default keep-alive config
    const default_keepalive = h3.server.config.KeepAliveConfig{};
    try testing.expect(default_keepalive.enabled);
    try testing.expectEqual(@as(u32, 100), default_keepalive.max_requests);
    try testing.expectEqual(@as(u32, 30), default_keepalive.timeout);
    try testing.expectEqual(@as(u32, 5), default_keepalive.keep_alive_timeout);

    // Test custom keep-alive config
    const custom_keepalive = h3.server.config.KeepAliveConfig{
        .enabled = false,
        .max_requests = 50,
        .timeout = 15,
        .keep_alive_timeout = 2,
    };
    try testing.expect(!custom_keepalive.enabled);
    try testing.expectEqual(@as(u32, 50), custom_keepalive.max_requests);
    try testing.expectEqual(@as(u32, 15), custom_keepalive.timeout);
    try testing.expectEqual(@as(u32, 2), custom_keepalive.keep_alive_timeout);
}

test "Logging configuration" {
    // Test default logging config
    const default_logging = h3.server.config.LogConfig{};
    try testing.expect(default_logging.access_log);
    try testing.expect(default_logging.error_log);
    try testing.expectEqual(std.log.Level.info, default_logging.level);
    try testing.expectEqual(h3.server.config.LogFormat.common, default_logging.format);
    try testing.expect(default_logging.file == null);

    // Test custom logging config
    const custom_logging = h3.server.config.LogConfig{
        .access_log = false,
        .error_log = true,
        .level = .debug,
        .format = .json,
        .file = "app.log",
    };
    try testing.expect(!custom_logging.access_log);
    try testing.expect(custom_logging.error_log);
    try testing.expectEqual(std.log.Level.debug, custom_logging.level);
    try testing.expectEqual(h3.server.config.LogFormat.json, custom_logging.format);
    try testing.expectEqualStrings("app.log", custom_logging.file.?);
}
