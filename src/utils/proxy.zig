//! Proxy utilities for H3 framework
//! Provides reverse proxy, load balancing, and proxy header handling

const std = @import("std");
const H3Event = @import("../core/event.zig").H3Event;
const HttpMethod = @import("../http/method.zig").HttpMethod;

/// Proxy target configuration
pub const ProxyTarget = struct {
    host: []const u8,
    port: u16,
    path_prefix: []const u8 = "",
    secure: bool = false,
    weight: u32 = 1,
    health_check_path: ?[]const u8 = null,
    timeout_ms: u32 = 5000,

    pub fn getUrl(self: ProxyTarget, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const scheme = if (self.secure) "https" else "http";
        const full_path = if (self.path_prefix.len > 0)
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ self.path_prefix, path })
        else
            path;
        defer if (self.path_prefix.len > 0) allocator.free(full_path);

        return std.fmt.allocPrint(allocator, "{s}://{s}:{d}{s}", .{ scheme, self.host, self.port, full_path });
    }
};

/// Load balancing strategies
pub const LoadBalanceStrategy = enum {
    round_robin,
    weighted_round_robin,
    least_connections,
    random,
    ip_hash,
};

/// Proxy configuration
pub const ProxyConfig = struct {
    targets: []ProxyTarget,
    strategy: LoadBalanceStrategy = .round_robin,
    preserve_host: bool = false,
    preserve_x_forwarded: bool = true,
    timeout_ms: u32 = 5000,
    retry_attempts: u32 = 3,
    health_check_interval_ms: u32 = 30000,
};

/// Load balancer for managing proxy targets
pub const LoadBalancer = struct {
    targets: []ProxyTarget,
    strategy: LoadBalanceStrategy,
    current_index: std.atomic.Atomic(usize),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, targets: []ProxyTarget, strategy: LoadBalanceStrategy) LoadBalancer {
        return LoadBalancer{
            .targets = targets,
            .strategy = strategy,
            .current_index = std.atomic.Atomic(usize).init(0),
            .allocator = allocator,
        };
    }

    /// Select next target based on load balancing strategy
    pub fn selectTarget(self: *LoadBalancer, event: *H3Event) ?*ProxyTarget {
        if (self.targets.len == 0) return null;

        return switch (self.strategy) {
            .round_robin => self.selectRoundRobin(),
            .weighted_round_robin => self.selectWeightedRoundRobin(),
            .random => self.selectRandom(),
            .ip_hash => self.selectByIpHash(event),
            .least_connections => self.selectLeastConnections(),
        };
    }

    fn selectRoundRobin(self: *LoadBalancer) *ProxyTarget {
        const index = self.current_index.fetchAdd(1, .Monotonic) % self.targets.len;
        return &self.targets[index];
    }

    fn selectWeightedRoundRobin(self: *LoadBalancer) *ProxyTarget {
        // Simplified weighted round robin
        var total_weight: u32 = 0;
        for (self.targets) |target| {
            total_weight += target.weight;
        }

        const random_weight = std.crypto.random.intRangeLessThan(u32, 0, total_weight);
        var current_weight: u32 = 0;

        for (self.targets) |*target| {
            current_weight += target.weight;
            if (random_weight < current_weight) {
                return target;
            }
        }

        return &self.targets[0];
    }

    fn selectRandom(self: *LoadBalancer) *ProxyTarget {
        const index = std.crypto.random.intRangeLessThan(usize, 0, self.targets.len);
        return &self.targets[index];
    }

    fn selectByIpHash(self: *LoadBalancer, event: *H3Event) *ProxyTarget {
        const client_ip = ProxyUtils.getClientIp(event);
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(client_ip);
        const hash = hasher.final();
        const index = hash % self.targets.len;
        return &self.targets[index];
    }

    fn selectLeastConnections(self: *LoadBalancer) *ProxyTarget {
        // Simplified implementation - in practice, you'd track active connections
        return self.selectRoundRobin();
    }
};

/// Proxy request/response utilities
pub const ProxyUtils = struct {
    /// Forward request to target server
    pub fn forwardRequest(event: *H3Event, target: *ProxyTarget, config: ProxyConfig) !void {
        const target_url = try target.getUrl(event.allocator, event.getPath());
        defer event.allocator.free(target_url);

        // In a real implementation, you would:
        // 1. Create HTTP client request
        // 2. Copy headers from original request
        // 3. Copy request body
        // 4. Send request to target
        // 5. Copy response back to client

        // For now, this is a placeholder that sets appropriate headers
        try setProxyHeaders(event, target, config);

        // Simulate forwarding by setting a response
        try event.sendText("Proxied response (placeholder)");
    }

    /// Set proxy-related headers
    pub fn setProxyHeaders(event: *H3Event, target: *ProxyTarget, config: ProxyConfig) !void {
        if (config.preserve_x_forwarded) {
            // Set X-Forwarded-For
            const client_ip = getClientIp(event);
            const existing_xff = event.getHeader("x-forwarded-for");
            const xff_value = if (existing_xff) |existing|
                try std.fmt.allocPrint(event.allocator, "{s}, {s}", .{ existing, client_ip })
            else
                try std.fmt.allocPrint(event.allocator, "{s}", .{client_ip});
            defer event.allocator.free(xff_value);
            try event.setHeader("X-Forwarded-For", xff_value);

            // Set X-Forwarded-Proto
            const proto = if (target.secure) "https" else "http";
            try event.setHeader("X-Forwarded-Proto", proto);

            // Set X-Forwarded-Host
            if (event.getHeader("host")) |host| {
                try event.setHeader("X-Forwarded-Host", host);
            }
        }

        if (!config.preserve_host) {
            const new_host = try std.fmt.allocPrint(event.allocator, "{s}:{d}", .{ target.host, target.port });
            defer event.allocator.free(new_host);
            try event.setHeader("Host", new_host);
        }
    }

    /// Create a reverse proxy middleware
    pub fn createReverseProxy(allocator: std.mem.Allocator, config: ProxyConfig) !fn (*H3Event, @import("../core/interfaces.zig").MiddlewareContext, usize, @import("../core/handler.zig").Handler) anyerror!void {
        const load_balancer = LoadBalancer.init(allocator, config.targets, config.strategy);
        _ = load_balancer;

        const ProxyMiddleware = struct {
            fn middleware(event: *H3Event, context: @import("../core/interfaces.zig").MiddlewareContext, index: usize, final_handler: @import("../core/handler.zig").Handler) !void {
                _ = context;
                _ = index;
                _ = final_handler;

                // In a real implementation, you would:
                // 1. Select target using load balancer
                // 2. Forward request to target
                // 3. Handle response

                // For now, just send a placeholder response
                try event.sendText("Reverse proxy response (placeholder)");
            }
        };

        return ProxyMiddleware.middleware;
    }

    /// Health check for proxy targets
    pub fn healthCheck(allocator: std.mem.Allocator, target: *ProxyTarget) !bool {
        const health_path = target.health_check_path orelse "/health";
        const health_url = try target.getUrl(allocator, health_path);
        defer allocator.free(health_url);

        // In a real implementation, you would:
        // 1. Make HTTP request to health check endpoint
        // 2. Check response status and content
        // 3. Return true if healthy, false otherwise

        // For now, always return true (placeholder)
        return true;
    }

    /// Get client IP considering proxy headers
    pub fn getClientIp(event: *H3Event) []const u8 {
        // Try X-Forwarded-For header first
        if (event.getHeader("x-forwarded-for")) |xff| {
            // Get the first IP in the chain
            if (std.mem.indexOf(u8, xff, ",")) |comma| {
                return std.mem.trim(u8, xff[0..comma], " ");
            }
            return std.mem.trim(u8, xff, " ");
        }

        // Try X-Real-IP header
        if (event.getHeader("x-real-ip")) |real_ip| {
            return real_ip;
        }

        // Try CF-Connecting-IP (Cloudflare)
        if (event.getHeader("cf-connecting-ip")) |cf_ip| {
            return cf_ip;
        }

        // Try True-Client-IP (Akamai)
        if (event.getHeader("true-client-ip")) |true_ip| {
            return true_ip;
        }

        // Fallback to connection IP (would need to be passed from server)
        return "unknown";
    }

    /// Check if request is from a trusted proxy
    pub fn isTrustedProxy(client_ip: []const u8, trusted_proxies: []const []const u8) bool {
        for (trusted_proxies) |proxy| {
            if (std.mem.eql(u8, client_ip, proxy)) {
                return true;
            }
        }
        return false;
    }

    /// Parse proxy protocol header (for TCP load balancers)
    pub fn parseProxyProtocol(header: []const u8) ?ProxyProtocolInfo {
        // PROXY TCP4 192.168.1.1 192.168.1.2 12345 80
        if (!std.mem.startsWith(u8, header, "PROXY ")) return null;

        var parts = std.mem.split(u8, header[6..], " ");
        const protocol = parts.next() orelse return null;
        const src_ip = parts.next() orelse return null;
        const dest_ip = parts.next() orelse return null;
        const src_port_str = parts.next() orelse return null;
        const dest_port_str = parts.next() orelse return null;

        const src_port = std.fmt.parseInt(u16, src_port_str, 10) catch return null;
        const dest_port = std.fmt.parseInt(u16, dest_port_str, 10) catch return null;

        return ProxyProtocolInfo{
            .protocol = protocol,
            .src_ip = src_ip,
            .dest_ip = dest_ip,
            .src_port = src_port,
            .dest_port = dest_port,
        };
    }
};

/// Proxy protocol information
pub const ProxyProtocolInfo = struct {
    protocol: []const u8,
    src_ip: []const u8,
    dest_ip: []const u8,
    src_port: u16,
    dest_port: u16,
};

/// Circuit breaker for proxy targets
pub const CircuitBreaker = struct {
    failure_threshold: u32,
    recovery_timeout_ms: u32,
    failure_count: std.atomic.Atomic(u32),
    last_failure_time: std.atomic.Atomic(i64),
    state: std.atomic.Atomic(State),

    const State = enum(u8) {
        closed,
        open,
        half_open,
    };

    pub fn init(failure_threshold: u32, recovery_timeout_ms: u32) CircuitBreaker {
        return CircuitBreaker{
            .failure_threshold = failure_threshold,
            .recovery_timeout_ms = recovery_timeout_ms,
            .failure_count = std.atomic.Atomic(u32).init(0),
            .last_failure_time = std.atomic.Atomic(i64).init(0),
            .state = std.atomic.Atomic(State).init(.closed),
        };
    }

    /// Check if request should be allowed
    pub fn allowRequest(self: *CircuitBreaker) bool {
        const current_state = self.state.load(.Monotonic);

        switch (current_state) {
            .closed => return true,
            .open => {
                const now = std.time.milliTimestamp();
                const last_failure = self.last_failure_time.load(.Monotonic);

                if (now - last_failure > self.recovery_timeout_ms) {
                    // Try to transition to half-open
                    if (self.state.compareAndSwap(.open, .half_open, .Monotonic, .Monotonic) == null) {
                        return true;
                    }
                }
                return false;
            },
            .half_open => return true,
        }
    }

    /// Record successful request
    pub fn recordSuccess(self: *CircuitBreaker) void {
        self.failure_count.store(0, .Monotonic);
        self.state.store(.closed, .Monotonic);
    }

    /// Record failed request
    pub fn recordFailure(self: *CircuitBreaker) void {
        const failures = self.failure_count.fetchAdd(1, .Monotonic) + 1;
        self.last_failure_time.store(std.time.milliTimestamp(), .Monotonic);

        if (failures >= self.failure_threshold) {
            self.state.store(.open, .Monotonic);
        }
    }
};

// Tests
test "ProxyTarget URL generation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const target = ProxyTarget{
        .host = "api.example.com",
        .port = 8080,
        .path_prefix = "/v1",
        .secure = true,
    };

    const url = try target.getUrl(allocator, "/users");
    defer allocator.free(url);

    try testing.expectEqualStrings("https://api.example.com:8080/v1/users", url);
}

test "LoadBalancer round robin" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const targets = [_]ProxyTarget{
        .{ .host = "server1", .port = 8080 },
        .{ .host = "server2", .port = 8080 },
        .{ .host = "server3", .port = 8080 },
    };

    var lb = LoadBalancer.init(allocator, &targets, .round_robin);

    // Create a mock event
    var event = @import("../core/event.zig").H3Event.init(allocator);
    defer event.deinit();

    const target1 = lb.selectTarget(&event);
    const target2 = lb.selectTarget(&event);
    const target3 = lb.selectTarget(&event);
    const target4 = lb.selectTarget(&event);

    try testing.expect(target1 != null);
    try testing.expect(target2 != null);
    try testing.expect(target3 != null);
    try testing.expect(target4 != null);

    // Should cycle back to first target
    try testing.expectEqualStrings(target1.?.host, target4.?.host);
}

test "CircuitBreaker functionality" {
    const testing = std.testing;

    var cb = CircuitBreaker.init(3, 1000);

    // Initially closed, should allow requests
    try testing.expect(cb.allowRequest());

    // Record failures
    cb.recordFailure();
    cb.recordFailure();
    try testing.expect(cb.allowRequest()); // Still closed

    cb.recordFailure();
    try testing.expect(!cb.allowRequest()); // Now open

    // Record success should close circuit
    cb.recordSuccess();
    try testing.expect(cb.allowRequest());
}
