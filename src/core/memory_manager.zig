//! Unified memory management system for H3 framework
//! Provides centralized memory allocation, pooling, and statistics

const std = @import("std");
const config = @import("config.zig");
const H3Event = @import("event.zig").H3Event;

/// Memory statistics for monitoring
pub const MemoryStats = struct {
    total_allocated: usize = 0,
    total_freed: usize = 0,
    current_usage: usize = 0,
    peak_usage: usize = 0,
    pool_hits: usize = 0,
    pool_misses: usize = 0,

    /// Get memory efficiency ratio
    pub fn efficiency(self: MemoryStats) f64 {
        if (self.pool_hits + self.pool_misses == 0) return 0.0;
        return @as(f64, @floatFromInt(self.pool_hits)) / @as(f64, @floatFromInt(self.pool_hits + self.pool_misses));
    }

    /// Reset statistics
    pub fn reset(self: *MemoryStats) void {
        self.* = MemoryStats{};
    }
};

/// Generic object pool for memory management
pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();

        objects: std.ArrayList(*T),
        allocator: std.mem.Allocator,
        max_size: usize,
        stats: *MemoryStats,

        pub fn init(allocator: std.mem.Allocator, max_size: usize, stats: *MemoryStats) Self {
            return Self{
                .objects = std.ArrayList(*T).init(allocator),
                .allocator = allocator,
                .max_size = max_size,
                .stats = stats,
            };
        }

        pub fn deinit(self: *Self) void {
            // Free all pooled objects
            for (self.objects.items) |obj| {
                obj.deinit();
                self.allocator.destroy(obj);
            }
            self.objects.deinit();
        }

        /// Acquire an object from the pool or create new one
        pub fn acquire(self: *Self) !*T {
            if (self.objects.items.len > 0) {
                self.stats.pool_hits += 1;
                return self.objects.orderedRemove(self.objects.items.len - 1);
            }

            self.stats.pool_misses += 1;
            const obj = try self.allocator.create(T);

            // Initialize the object based on its type
            if (T == H3Event) {
                obj.* = H3Event.init(self.allocator);
            } else {
                // For other types, assume they have an init method
                obj.* = T.init(self.allocator);
            }

            self.stats.total_allocated += @sizeOf(T);
            self.stats.current_usage += @sizeOf(T);
            if (self.stats.current_usage > self.stats.peak_usage) {
                self.stats.peak_usage = self.stats.current_usage;
            }

            return obj;
        }

        /// Release an object back to the pool
        pub fn release(self: *Self, obj: *T) void {
            // Reset object state
            obj.reset();

            if (self.objects.items.len < self.max_size) {
                self.objects.append(obj) catch {
                    // Pool is full, destroy the object
                    obj.deinit();
                    self.allocator.destroy(obj);
                    self.stats.total_freed += @sizeOf(T);
                    self.stats.current_usage -= @sizeOf(T);
                };
            } else {
                // Pool is full, destroy the object
                obj.deinit();
                self.allocator.destroy(obj);
                self.stats.total_freed += @sizeOf(T);
                self.stats.current_usage -= @sizeOf(T);
            }
        }

        /// Get pool statistics
        pub fn getStats(self: *const Self) struct { size: usize, capacity: usize } {
            return .{
                .size = self.objects.items.len,
                .capacity = self.max_size,
            };
        }

        /// Warm up the pool with pre-allocated objects
        pub fn warmUp(self: *Self, count: usize) !void {
            const actual_count = @min(count, self.max_size);
            for (0..actual_count) |_| {
                const obj = try self.acquire();
                self.release(obj);
            }
        }
    };
}

/// Centralized memory manager for H3 framework
pub const MemoryManager = struct {
    allocator: std.mem.Allocator,
    config: config.MemoryConfig,
    stats: MemoryStats,

    // Object pools
    event_pool: ?ObjectPool(H3Event) = null,

    const Self = @This();

    /// Initialize memory manager with configuration
    pub fn init(allocator: std.mem.Allocator, memory_config: config.MemoryConfig) !Self {
        var manager = Self{
            .allocator = allocator,
            .config = memory_config,
            .stats = MemoryStats{},
        };

        // Initialize event pool if enabled
        if (memory_config.enable_event_pool) {
            manager.event_pool = ObjectPool(H3Event).init(allocator, memory_config.event_pool_size, &manager.stats);

            // Warm up the pool based on strategy
            const warmup_count = switch (memory_config.allocation_strategy) {
                .minimal => memory_config.event_pool_size / 4,
                .balanced => memory_config.event_pool_size / 2,
                .performance => memory_config.event_pool_size,
            };
            try manager.event_pool.?.warmUp(warmup_count);
        }

        return manager;
    }

    /// Deinitialize memory manager
    pub fn deinit(self: *Self) void {
        if (self.event_pool) |*pool| {
            pool.deinit();
        }
    }

    /// Acquire an event from the pool
    pub fn acquireEvent(self: *Self) !*H3Event {
        if (self.event_pool) |*pool| {
            return pool.acquire();
        }

        // Fallback to direct allocation
        const event = try self.allocator.create(H3Event);
        event.* = H3Event.init(self.allocator);

        self.stats.total_allocated += @sizeOf(H3Event);
        self.stats.current_usage += @sizeOf(H3Event);
        if (self.stats.current_usage > self.stats.peak_usage) {
            self.stats.peak_usage = self.stats.current_usage;
        }

        return event;
    }

    /// Release an event back to the pool
    pub fn releaseEvent(self: *Self, event: *H3Event) void {
        if (self.event_pool) |*pool| {
            pool.release(event);
            return;
        }

        // Fallback to direct deallocation
        event.deinit();
        self.allocator.destroy(event);

        self.stats.total_freed += @sizeOf(H3Event);
        self.stats.current_usage -= @sizeOf(H3Event);
    }

    /// Get memory statistics
    pub fn getStats(self: *const Self) MemoryStats {
        return self.stats;
    }

    /// Reset memory statistics
    pub fn resetStats(self: *Self) void {
        self.stats.reset();
    }

    /// Get pool efficiency
    pub fn getPoolEfficiency(self: *const Self) f64 {
        return self.stats.efficiency();
    }

    /// Check if memory usage is within limits
    pub fn isMemoryHealthy(self: *const Self) bool {
        const efficiency = self.getPoolEfficiency();
        return switch (self.config.allocation_strategy) {
            .minimal => efficiency > 0.5,
            .balanced => efficiency > 0.7,
            .performance => efficiency > 0.8,
        };
    }

    /// Optimize memory usage based on current statistics
    pub fn optimize(self: *Self) void {
        if (!self.isMemoryHealthy()) {
            // Could implement dynamic pool resizing here
            std.log.warn("Memory efficiency is low: {d:.2}%", .{self.getPoolEfficiency() * 100});
        }
    }

    /// Get memory usage report
    pub fn getReport(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const stats = self.getStats();
        return std.fmt.allocPrint(allocator,
            \\Memory Manager Report:
            \\  Total Allocated: {d} bytes
            \\  Total Freed: {d} bytes
            \\  Current Usage: {d} bytes
            \\  Peak Usage: {d} bytes
            \\  Pool Efficiency: {d:.2}%
            \\  Pool Hits: {d}
            \\  Pool Misses: {d}
            \\  Strategy: {s}
            \\  Health: {s}
        , .{
            stats.total_allocated,
            stats.total_freed,
            stats.current_usage,
            stats.peak_usage,
            self.getPoolEfficiency() * 100,
            stats.pool_hits,
            stats.pool_misses,
            @tagName(self.config.allocation_strategy),
            if (self.isMemoryHealthy()) "Healthy" else "Needs Attention",
        });
    }
};

/// Memory-aware allocator wrapper
pub const ManagedAllocator = struct {
    child_allocator: std.mem.Allocator,
    stats: *MemoryStats,

    const Self = @This();

    pub fn init(child_allocator: std.mem.Allocator, stats: *MemoryStats) Self {
        return Self{
            .child_allocator = child_allocator,
            .stats = stats,
        };
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const result = self.child_allocator.rawAlloc(len, log2_ptr_align, ret_addr);
        if (result) |_| {
            self.stats.total_allocated += len;
            self.stats.current_usage += len;
            if (self.stats.current_usage > self.stats.peak_usage) {
                self.stats.peak_usage = self.stats.current_usage;
            }
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const result = self.child_allocator.rawResize(buf, log2_buf_align, new_len, ret_addr);
        if (result) {
            if (new_len > buf.len) {
                self.stats.total_allocated += new_len - buf.len;
                self.stats.current_usage += new_len - buf.len;
            } else {
                self.stats.total_freed += buf.len - new_len;
                self.stats.current_usage -= buf.len - new_len;
            }
            if (self.stats.current_usage > self.stats.peak_usage) {
                self.stats.peak_usage = self.stats.current_usage;
            }
        }
        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.child_allocator.rawFree(buf, log2_buf_align, ret_addr);
        self.stats.total_freed += buf.len;
        self.stats.current_usage -= buf.len;
    }
};

test "MemoryManager basic operations" {
    var manager = try MemoryManager.init(std.testing.allocator, config.MemoryConfig{});
    defer manager.deinit();

    const event = try manager.acquireEvent();
    manager.releaseEvent(event);

    const stats = manager.getStats();
    try std.testing.expect(stats.pool_hits > 0 or stats.pool_misses > 0);
}

test "ObjectPool operations" {
    var stats = MemoryStats{};
    var pool = ObjectPool(H3Event).init(std.testing.allocator, 5, &stats);
    defer pool.deinit();

    const event = try pool.acquire();
    pool.release(event);

    try std.testing.expect(stats.pool_misses == 1);

    const event2 = try pool.acquire();
    pool.release(event2);

    try std.testing.expect(stats.pool_hits == 1);
}
