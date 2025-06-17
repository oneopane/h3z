//! Event pool for high-performance H3Event object reuse
//! Reduces memory allocation overhead by reusing event objects

const std = @import("std");
const H3Event = @import("event.zig").H3Event;

/// Pool for reusing H3Event objects to reduce allocation overhead
pub const EventPool = struct {
    events: std.ArrayList(*H3Event),
    allocator: std.mem.Allocator,
    max_size: usize,
    created_count: usize,
    reuse_count: usize,

    /// Initialize a new event pool
    pub fn init(allocator: std.mem.Allocator, max_size: usize) EventPool {
        return EventPool{
            .events = std.ArrayList(*H3Event).init(allocator),
            .allocator = allocator,
            .max_size = max_size,
            .created_count = 0,
            .reuse_count = 0,
        };
    }

    /// Deinitialize the pool and free all events
    pub fn deinit(self: *EventPool) void {
        for (self.events.items) |event| {
            event.deinit();
            self.allocator.destroy(event);
        }
        self.events.deinit();
    }

    /// Acquire an event from the pool or create a new one
    pub fn acquire(self: *EventPool) !*H3Event {
        if (self.events.items.len > 0) {
            const event = self.events.pop();
            if (event) |e| {
                // Efficiently reset event object without reallocating memory
                // Use clearRetainingCapacity instead of clearAndFree
                // This preserves the hash map capacity, improving performance
                e.context.clearRetainingCapacity();
                e.params.clearRetainingCapacity();
                e.query.clearRetainingCapacity();

                // Reset request object
                e.request.method = .GET;
                e.request.url = "";

                // Only free path memory when necessary
                if (e.request.path.len > 0 and !std.mem.eql(u8, e.request.path, "/") and !std.mem.eql(u8, e.request.path, "")) {
                    e.allocator.free(e.request.path);
                }
                e.request.path = "";

                // Free request body
                if (e.request.body) |b| {
                    e.allocator.free(b);
                    e.request.body = null;
                }

                // Free query string
                if (e.request.query) |q| {
                    e.allocator.free(q);
                    e.request.query = null;
                }

                // Clear request headers, retain capacity
                e.request.headers.clearRetainingCapacity();

                // Reset response object
                e.response.status = .ok;
                if (e.response.body_owned and e.response.body != null) {
                    e.allocator.free(e.response.body.?);
                }
                e.response.body = null;
                e.response.body_owned = false;
                e.response.sent = false;
                e.response.finished = false;

                // Clear response headers, retain capacity
                e.response.headers.clearRetainingCapacity();

                self.reuse_count += 1;
                return e;
            }
        }

        // Create a new event
        const event = try self.allocator.create(H3Event);
        event.* = H3Event.init(self.allocator);
        self.created_count += 1;
        return event;
    }

    /// Release an event back to the pool
    pub fn release(self: *EventPool, event: *H3Event) void {
        if (self.events.items.len < self.max_size) {
            // Put the object back into the pool directly without resetting
            // Reset operation will be performed on next acquire
            self.events.append(event) catch {
                // Only destroy the object if adding to pool fails
                event.deinit();
                self.allocator.destroy(event);
            };
        } else {
            // Pool is full, destroy the object
            event.deinit();
            self.allocator.destroy(event);
        }
    }

    /// Get pool statistics
    pub fn getStats(self: *const EventPool) PoolStats {
        return PoolStats{
            .pool_size = self.events.items.len,
            .max_size = self.max_size,
            .created_count = self.created_count,
            .reuse_count = self.reuse_count,
            .reuse_ratio = if (self.created_count > 0)
                @as(f64, @floatFromInt(self.reuse_count)) / @as(f64, @floatFromInt(self.created_count + self.reuse_count))
            else
                0.0,
        };
    }

    /// Reset pool statistics
    pub fn resetStats(self: *EventPool) void {
        self.created_count = 0;
        self.reuse_count = 0;
    }

    /// Warm up the pool by pre-allocating events
    pub fn warmUp(self: *EventPool, count: usize) !void {
        const actual_count = @min(count, self.max_size);

        for (0..actual_count) |_| {
            const event = try self.allocator.create(H3Event);
            event.* = H3Event.init(self.allocator);
            try self.events.append(event);
            self.created_count += 1;
        }
    }

    /// Shrink pool to target size
    pub fn shrink(self: *EventPool, target_size: usize) void {
        while (self.events.items.len > target_size) {
            const event = self.events.pop();
            event.deinit();
            self.allocator.destroy(event);
        }
    }
};

/// Pool statistics for monitoring
pub const PoolStats = struct {
    pool_size: usize,
    max_size: usize,
    created_count: usize,
    reuse_count: usize,
    reuse_ratio: f64,
};

/// Global event pool instance (optional)
var global_pool: ?EventPool = null;
var global_pool_mutex: std.Thread.Mutex = .{};

/// Initialize global event pool
pub fn initGlobalPool(allocator: std.mem.Allocator, max_size: usize) void {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();

    if (global_pool == null) {
        global_pool = EventPool.init(allocator, max_size);
    }
}

/// Deinitialize global event pool
pub fn deinitGlobalPool() void {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();

    if (global_pool) |*pool| {
        pool.deinit();
        global_pool = null;
    }
}

/// Acquire from global pool
pub fn acquireGlobal() !*H3Event {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();

    if (global_pool) |*pool| {
        return pool.acquire();
    }
    return error.GlobalPoolNotInitialized;
}

/// Release to global pool
pub fn releaseGlobal(event: *H3Event) void {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();

    if (global_pool) |*pool| {
        pool.release(event);
    }
}

test "EventPool basic operations" {
    var pool = EventPool.init(std.testing.allocator, 5);
    defer pool.deinit();

    // Acquire events
    const event1 = try pool.acquire();
    const event2 = try pool.acquire();

    // Release events
    pool.release(event1);
    pool.release(event2);

    // Acquire again should reuse
    const event3 = try pool.acquire();
    pool.release(event3);

    const stats = pool.getStats();
    try std.testing.expect(stats.reuse_count > 0);
}

test "EventPool warm up" {
    var pool = EventPool.init(std.testing.allocator, 10);
    defer pool.deinit();

    try pool.warmUp(5);
    try std.testing.expectEqual(@as(usize, 5), pool.events.items.len);

    const event = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 4), pool.events.items.len);

    pool.release(event);
    try std.testing.expectEqual(@as(usize, 5), pool.events.items.len);
}

test "EventPool max size limit" {
    var pool = EventPool.init(std.testing.allocator, 2);
    defer pool.deinit();

    const event1 = try pool.acquire();
    const event2 = try pool.acquire();
    const event3 = try pool.acquire();

    pool.release(event1);
    pool.release(event2);
    pool.release(event3); // This should be destroyed, not pooled

    try std.testing.expectEqual(@as(usize, 2), pool.events.items.len);
}
