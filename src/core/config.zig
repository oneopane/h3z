//! Unified configuration system for H3 framework
//! Provides centralized configuration management with validation and defaults

const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;

/// Memory management configuration
pub const MemoryConfig = struct {
    /// Enable object pooling for events
    enable_event_pool: bool = true,

    /// Event pool size
    event_pool_size: usize = 200,

    /// Enable route parameter pooling
    enable_params_pool: bool = true,

    /// Route parameters pool size
    params_pool_size: usize = 200,

    /// Enable memory statistics tracking
    enable_memory_stats: bool = false,

    /// Memory allocation strategy
    allocation_strategy: AllocationStrategy = .balanced,

    pub const AllocationStrategy = enum {
        minimal, // Minimize memory usage
        balanced, // Balance between speed and memory
        performance, // Maximize performance
    };

    /// Validate memory configuration
    pub fn validate(self: MemoryConfig) !void {
        if (self.event_pool_size == 0) return error.InvalidEventPoolSize;
        if (self.params_pool_size == 0) return error.InvalidParamsPoolSize;
        if (self.event_pool_size > 10000) return error.EventPoolSizeTooLarge;
        if (self.params_pool_size > 10000) return error.ParamsPoolSizeTooLarge;
    }

    /// Get optimized configuration for strategy
    pub fn optimizeFor(strategy: AllocationStrategy) MemoryConfig {
        return switch (strategy) {
            .minimal => MemoryConfig{
                .enable_event_pool = false,
                .enable_params_pool = false,
                .event_pool_size = 10,
                .params_pool_size = 10,
                .allocation_strategy = .minimal,
            },
            .balanced => MemoryConfig{}, // Use defaults
            .performance => MemoryConfig{
                .event_pool_size = 500,
                .params_pool_size = 500,
                .enable_memory_stats = true,
                .allocation_strategy = .performance,
            },
        };
    }
};

/// Router configuration
pub const RouterConfig = struct {
    /// Enable LRU cache for route lookups
    enable_cache: bool = true,

    /// Cache size for route lookups
    cache_size: usize = 1000,

    /// Enable compile-time route optimization
    enable_compile_time_optimization: bool = true,

    /// Maximum route depth for security
    max_route_depth: usize = 32,

    /// Maximum number of route parameters
    max_route_params: usize = 16,

    /// Route matching strategy
    matching_strategy: MatchingStrategy = .hybrid,

    pub const MatchingStrategy = enum {
        linear, // Simple linear search
        trie, // Trie-based matching
        hybrid, // Cache + Trie + Linear fallback
        compiled, // Compile-time optimized
    };

    /// Validate router configuration
    pub fn validate(self: RouterConfig) !void {
        if (self.cache_size == 0) return error.InvalidCacheSize;
        if (self.max_route_depth == 0) return error.InvalidMaxRouteDepth;
        if (self.max_route_params == 0) return error.InvalidMaxRouteParams;
        if (self.cache_size > 100000) return error.CacheSizeTooLarge;
    }

    /// Get optimized configuration for performance level
    pub fn optimizeForPerformance(level: enum { low, medium, high }) RouterConfig {
        return switch (level) {
            .low => RouterConfig{
                .enable_cache = false,
                .cache_size = 100,
                .matching_strategy = .linear,
            },
            .medium => RouterConfig{}, // Use defaults
            .high => RouterConfig{
                .cache_size = 5000,
                .matching_strategy = .hybrid,
                .enable_compile_time_optimization = true,
            },
        };
    }
};

/// Middleware configuration
pub const MiddlewareConfig = struct {
    /// Enable fast middleware execution
    enable_fast_middleware: bool = true,

    /// Maximum number of middlewares
    max_middlewares: usize = 32,

    /// Enable middleware statistics
    enable_middleware_stats: bool = false,

    /// Middleware execution strategy
    execution_strategy: ExecutionStrategy = .fast,

    /// Enable middleware caching
    enable_middleware_cache: bool = false,

    pub const ExecutionStrategy = enum {
        legacy, // Traditional middleware chain
        fast, // Zero-allocation fast middleware
        hybrid, // Adaptive based on middleware type
    };

    /// Validate middleware configuration
    pub fn validate(self: MiddlewareConfig) !void {
        if (self.max_middlewares == 0) return error.InvalidMaxMiddlewares;
        if (self.max_middlewares > 256) return error.TooManyMiddlewares;
    }
};

/// Security configuration
pub const SecurityConfig = struct {
    /// Enable CORS protection
    enable_cors: bool = false,

    /// Enable CSRF protection
    enable_csrf: bool = false,

    /// Enable rate limiting
    enable_rate_limiting: bool = false,

    /// Maximum request body size (bytes)
    max_body_size: usize = 1024 * 1024, // 1MB

    /// Maximum header size (bytes)
    max_header_size: usize = 8192, // 8KB

    /// Request timeout (milliseconds)
    request_timeout: u32 = 30000, // 30 seconds

    /// Enable security headers
    enable_security_headers: bool = true,

    /// Validate security configuration
    pub fn validate(self: SecurityConfig) !void {
        if (self.max_body_size == 0) return error.InvalidMaxBodySize;
        if (self.max_header_size == 0) return error.InvalidMaxHeaderSize;
        if (self.request_timeout == 0) return error.InvalidRequestTimeout;
    }
};

/// Performance monitoring configuration
pub const MonitoringConfig = struct {
    /// Enable performance metrics collection
    enable_metrics: bool = false,

    /// Enable request/response logging
    enable_logging: bool = true,

    /// Log level
    log_level: LogLevel = .info,

    /// Enable profiling
    enable_profiling: bool = false,

    /// Metrics collection interval (milliseconds)
    metrics_interval: u32 = 1000,

    pub const LogLevel = enum { debug, info, warn, err, none };

    /// Validate monitoring configuration
    pub fn validate(self: MonitoringConfig) !void {
        if (self.metrics_interval == 0) return error.InvalidMetricsInterval;
    }
};

/// Main H3 framework configuration
pub const H3Config = struct {
    /// Memory management configuration
    memory: MemoryConfig = MemoryConfig{},

    /// Router configuration
    router: RouterConfig = RouterConfig{},

    /// Middleware configuration
    middleware: MiddlewareConfig = MiddlewareConfig{},

    /// Security configuration
    security: SecurityConfig = SecurityConfig{},

    /// Monitoring configuration
    monitoring: MonitoringConfig = MonitoringConfig{},

    /// Global error handler
    on_error: ?*const fn (*@import("event.zig").H3Event, anyerror) anyerror!void = null,

    /// Global response hook
    on_response: ?*const fn (*@import("event.zig").H3Event) anyerror!void = null,

    /// Global request hook
    on_request: ?*const fn (*@import("event.zig").H3Event) anyerror!void = null,

    /// Validate entire configuration
    pub fn validate(self: H3Config) !void {
        try self.memory.validate();
        try self.router.validate();
        try self.middleware.validate();
        try self.security.validate();
        try self.monitoring.validate();
    }

    /// Create development configuration
    pub fn development() H3Config {
        return H3Config{
            .memory = MemoryConfig.optimizeFor(.minimal),
            .router = RouterConfig.optimizeForPerformance(.medium),
            .middleware = MiddlewareConfig{
                .enable_middleware_stats = true,
            },
            .monitoring = MonitoringConfig{
                .enable_metrics = true,
                .log_level = .debug,
            },
        };
    }

    /// Create production configuration
    pub fn production() H3Config {
        return H3Config{
            .memory = MemoryConfig.optimizeFor(.performance),
            .router = RouterConfig.optimizeForPerformance(.high),
            .middleware = MiddlewareConfig{
                .enable_fast_middleware = true,
                .enable_middleware_stats = false,
            },
            .security = SecurityConfig{
                .enable_cors = true,
                .enable_security_headers = true,
                .enable_rate_limiting = true,
            },
            .monitoring = MonitoringConfig{
                .enable_metrics = true,
                .log_level = .warn,
            },
        };
    }

    /// Create testing configuration
    pub fn testing() H3Config {
        return H3Config{
            .memory = MemoryConfig.optimizeFor(.minimal),
            .router = RouterConfig{
                .enable_cache = false,
                .matching_strategy = .linear,
            },
            .middleware = MiddlewareConfig{
                .enable_fast_middleware = false,
            },
            .monitoring = MonitoringConfig{
                .enable_logging = false,
                .log_level = .none,
            },
        };
    }
};

/// Configuration builder for fluent API
pub const ConfigBuilder = struct {
    config: H3Config,

    pub fn init() ConfigBuilder {
        return ConfigBuilder{
            .config = H3Config{},
        };
    }

    /// Set memory configuration
    pub fn memory(self: *ConfigBuilder, memory_config: MemoryConfig) *ConfigBuilder {
        self.config.memory = memory_config;
        return self;
    }

    /// Set router configuration
    pub fn router(self: *ConfigBuilder, router_config: RouterConfig) *ConfigBuilder {
        self.config.router = router_config;
        return self;
    }

    /// Set middleware configuration
    pub fn middleware(self: *ConfigBuilder, middleware_config: MiddlewareConfig) *ConfigBuilder {
        self.config.middleware = middleware_config;
        return self;
    }

    /// Set security configuration
    pub fn security(self: *ConfigBuilder, security_config: SecurityConfig) *ConfigBuilder {
        self.config.security = security_config;
        return self;
    }

    /// Set monitoring configuration
    pub fn monitoring(self: *ConfigBuilder, monitoring_config: MonitoringConfig) *ConfigBuilder {
        self.config.monitoring = monitoring_config;
        return self;
    }

    /// Build and validate configuration
    pub fn build(self: ConfigBuilder) !H3Config {
        try self.config.validate();
        return self.config;
    }
};

test "H3Config validation" {
    const config = H3Config.development();
    try config.validate();

    const prod_config = H3Config.production();
    try prod_config.validate();

    const test_config = H3Config.testing();
    try test_config.validate();
}

test "ConfigBuilder fluent API" {
    var builder = ConfigBuilder.init();
    const config = try builder
        .memory(MemoryConfig.optimizeFor(.performance))
        .router(RouterConfig.optimizeForPerformance(.high))
        .build();

    try std.testing.expect(config.memory.allocation_strategy == .performance);
    try std.testing.expect(config.router.matching_strategy == .hybrid);
}
