//! Architecture Refactoring Demo
//! Demonstrates the new component-based architecture with unified configuration

const std = @import("std");
const h3 = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🏗️  H3 Framework Architecture Refactoring Demo", .{});
    std.log.info("=" ** 60, .{});

    try demonstrateConfigurationSystem(allocator);
    try demonstrateMemoryManagement(allocator);
    try demonstrateComponentArchitecture(allocator);
    try demonstratePerformanceComparison(allocator);

    std.log.info("✅ Architecture refactoring demonstration completed!", .{});
}

fn demonstrateConfigurationSystem(allocator: std.mem.Allocator) !void {
    std.log.info("\n📋 1. Unified Configuration System", .{});
    std.log.info("-" ** 40, .{});

    // Demonstrate configuration builder pattern
    var builder = h3.ConfigBuilder.init();
    const custom_config = try builder
        .memory(h3.MemoryConfig.optimizeFor(.performance))
        .router(h3.RouterConfig.optimizeForPerformance(.high))
        .security(h3.SecurityConfig{
            .enable_cors = true,
            .enable_security_headers = true,
            .max_body_size = 2 * 1024 * 1024, // 2MB
        })
        .monitoring(h3.MonitoringConfig{
            .enable_metrics = true,
            .log_level = .info,
        })
        .build();

    std.log.info("✓ Custom configuration built with fluent API", .{});
    std.log.info("  - Memory strategy: {s}", .{@tagName(custom_config.memory.allocation_strategy)});
    std.log.info("  - Router strategy: {s}", .{@tagName(custom_config.router.matching_strategy)});
    std.log.info("  - CORS enabled: {}", .{custom_config.security.enable_cors});
    std.log.info("  - Metrics enabled: {}", .{custom_config.monitoring.enable_metrics});

    // Demonstrate preset configurations
    const dev_config = h3.H3Config.development();
    const prod_config = h3.H3Config.production();
    const test_config = h3.H3Config.testing();

    std.log.info("✓ Preset configurations available:", .{});
    std.log.info("  - Development: Memory={s}, Router={s}", .{
        @tagName(dev_config.memory.allocation_strategy),
        @tagName(dev_config.router.matching_strategy),
    });
    std.log.info("  - Production: Memory={s}, Router={s}", .{
        @tagName(prod_config.memory.allocation_strategy),
        @tagName(prod_config.router.matching_strategy),
    });
    std.log.info("  - Testing: Memory={s}, Logging={s}", .{
        @tagName(test_config.memory.allocation_strategy),
        @tagName(test_config.monitoring.log_level),
    });

    _ = allocator;
}

fn demonstrateMemoryManagement(allocator: std.mem.Allocator) !void {
    std.log.info("\n💾 2. Advanced Memory Management", .{});
    std.log.info("-" ** 40, .{});

    // Create memory manager with performance configuration
    const memory_config = h3.MemoryConfig.optimizeFor(.performance);
    var memory_manager = try h3.MemoryManager.init(allocator, memory_config);
    defer memory_manager.deinit();

    std.log.info("✓ Memory manager initialized with performance strategy", .{});
    std.log.info("  - Event pool size: {d}", .{memory_config.event_pool_size});
    std.log.info("  - Params pool size: {d}", .{memory_config.params_pool_size});
    std.log.info("  - Memory stats enabled: {}", .{memory_config.enable_memory_stats});

    // Demonstrate object pooling
    const event1 = try memory_manager.acquireEvent();
    const event2 = try memory_manager.acquireEvent();
    const event3 = try memory_manager.acquireEvent();

    memory_manager.releaseEvent(event1);
    memory_manager.releaseEvent(event2);
    memory_manager.releaseEvent(event3);

    const stats = memory_manager.getStats();
    std.log.info("✓ Object pooling demonstration:", .{});
    std.log.info("  - Pool efficiency: {d:.1}%", .{memory_manager.getPoolEfficiency() * 100});
    std.log.info("  - Pool hits: {d}", .{stats.pool_hits});
    std.log.info("  - Pool misses: {d}", .{stats.pool_misses});
    std.log.info("  - Current usage: {d} bytes", .{stats.current_usage});
    std.log.info("  - Peak usage: {d} bytes", .{stats.peak_usage});

    // Get memory report
    const report = try memory_manager.getReport(allocator);
    defer allocator.free(report);
    std.log.info("✓ Memory report generated ({d} bytes)", .{report.len});

    // Check memory health
    const is_healthy = memory_manager.isMemoryHealthy();
    std.log.info("✓ Memory health status: {s}", .{if (is_healthy) "Healthy" else "Needs Attention"});
}

fn demonstrateComponentArchitecture(allocator: std.mem.Allocator) !void {
    std.log.info("\n🔧 3. Component-Based Architecture", .{});
    std.log.info("-" ** 40, .{});

    // Create component-based application
    var app = try h3.createComponentApp(allocator);
    defer app.deinit();

    std.log.info("✓ Component-based H3 application created", .{});

    // Add routes using the new API
    const homeHandler = struct {
        fn handler(event: *h3.Event) !void {
            try h3.sendJson(event, .{
                .message = "Hello from component architecture!",
                .version = "2.0",
                .architecture = "component-based",
            });
        }
    }.handler;

    const healthHandler = struct {
        fn handler(event: *h3.Event) !void {
            try h3.sendJson(event, .{
                .status = "healthy",
                .message = "Component architecture working",
                .timestamp = std.time.timestamp(),
            });
        }
    }.handler;

    _ = try app.get("/", homeHandler);
    _ = try app.get("/health", healthHandler);

    std.log.info("✓ Routes registered using component API", .{});
    std.log.info("  - Route count: {d}", .{app.getRouteCount()});

    // Get component health status
    const health = app.getHealthStatus();
    std.log.info("✓ Component health status:", .{});
    std.log.info("  - Healthy components: {d}/{d}", .{ health.healthy, health.total });

    // Get memory statistics
    const memory_stats = app.getMemoryStats();
    std.log.info("✓ Memory statistics:", .{});
    std.log.info("  - Efficiency: {d:.1}%", .{memory_stats.efficiency() * 100});
    std.log.info("  - Current usage: {d} bytes", .{memory_stats.current_usage});

    // Optimize memory
    app.optimizeMemory();
    std.log.info("✓ Memory optimization performed", .{});

    // Test request handling
    var event = h3.Event.init(allocator);
    defer event.deinit();

    event.request.method = .GET;
    try event.request.parseUrl("/");

    try app.handle(&event);
    std.log.info("✓ Request handled successfully", .{});
    std.log.info("  - Response status: {d}", .{@intFromEnum(event.response.status)});
}

fn demonstratePerformanceComparison(allocator: std.mem.Allocator) !void {
    std.log.info("\n⚡ 4. Performance Comparison", .{});
    std.log.info("-" ** 40, .{});

    const iterations = 1000;

    // Test legacy H3 application
    {
        var legacy_app = h3.createApp(allocator);
        defer legacy_app.deinit();

        const testHandler = struct {
            fn handler(event: *h3.Event) !void {
                try event.sendText("Legacy response");
            }
        }.handler;

        _ = legacy_app.get("/test", testHandler);

        const start_time = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            var event = h3.Event.init(allocator);
            defer event.deinit();

            event.request.method = .GET;
            try event.request.parseUrl("/test");
            try legacy_app.handle(&event);
        }
        const end_time = std.time.nanoTimestamp();
        const legacy_time = @as(u64, @intCast(end_time - start_time));

        std.log.info("✓ Legacy H3 performance:", .{});
        std.log.info("  - {d} requests in {d:.2}ms", .{ iterations, @as(f64, @floatFromInt(legacy_time)) / 1_000_000.0 });
        std.log.info("  - Average: {d:.2}μs per request", .{@as(f64, @floatFromInt(legacy_time)) / @as(f64, @floatFromInt(iterations)) / 1000.0});
    }

    // Test component-based H3 application
    {
        var component_app = try h3.createProductionApp(allocator);
        defer component_app.deinit();

        const testHandler = struct {
            fn handler(event: *h3.Event) !void {
                try event.sendText("Component response");
            }
        }.handler;

        _ = try component_app.get("/test", testHandler);

        const start_time = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            var event = h3.Event.init(allocator);
            defer event.deinit();

            event.request.method = .GET;
            try event.request.parseUrl("/test");
            try component_app.handle(&event);
        }
        const end_time = std.time.nanoTimestamp();
        const component_time = @as(u64, @intCast(end_time - start_time));

        std.log.info("✓ Component H3 performance:", .{});
        std.log.info("  - {d} requests in {d:.2}ms", .{ iterations, @as(f64, @floatFromInt(component_time)) / 1_000_000.0 });
        std.log.info("  - Average: {d:.2}μs per request", .{@as(f64, @floatFromInt(component_time)) / @as(f64, @floatFromInt(iterations)) / 1000.0});

        const memory_stats = component_app.getMemoryStats();
        std.log.info("  - Memory efficiency: {d:.1}%", .{memory_stats.efficiency() * 100});
    }

    std.log.info("✓ Performance comparison completed", .{});
    std.log.info("  - Component architecture provides better memory management", .{});
    std.log.info("  - Unified configuration enables fine-tuned optimizations", .{});
    std.log.info("  - Decoupled components improve maintainability", .{});
}
