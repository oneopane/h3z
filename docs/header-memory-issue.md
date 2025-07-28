# HTTP Response Header Memory Management Issue

## Overview

The H3 framework currently has a memory management bug in the HTTP response header handling that causes a bus error (memory access violation) when attempting to free header memory. As a temporary fix, we've disabled the memory cleanup, which results in a memory leak.

## The Problem

### What Happens

When the server processes an HTTP request and sends a response, it crashes with a bus error when trying to clean up the response headers. The crash occurs at this line:

```zig
self.allocator.free(entry.key_ptr.*);  // 💥 Bus error here
```

### When It Happens

The crash occurs in two scenarios:

1. **Without event pooling**: Crashes after the first request when `response.deinit()` is called
2. **With event pooling**: Crashes on the second request when `response.reset()` is called

Both methods use the same pattern to free headers, and both crash at the same point.

## Technical Details

### How Headers Are Stored

Headers in H3 are stored in a HashMap with case-insensitive string keys:

```zig
// From headers.zig
pub const Headers = std.HashMap([]const u8, []const u8, HeaderContext, std.hash_map.default_max_load_percentage);
```

The `HeaderContext` provides case-insensitive comparison and hashing for header names.

### Memory Allocation Flow

When a header is set:

```zig
pub fn setHeader(self: *Response, name: []const u8, value: []const u8) !void {
    // 1. Duplicate the strings to ensure they persist
    const name_copy = try self.allocator.dupe(u8, name);
    const value_copy = try self.allocator.dupe(u8, value);
    
    // 2. Store in the HashMap
    try self.headers.put(name_copy, value_copy);
}
```

This creates heap-allocated copies of both the header name and value.

### The Cleanup Attempt

When cleaning up, we try to free these allocated strings:

```zig
pub fn deinit(self: *Response) void {
    // Iterate through all headers
    var iter = self.headers.iterator();
    while (iter.next()) |entry| {
        // Free the allocated strings
        self.allocator.free(entry.key_ptr.*);  // 💥 Crash here!
        self.allocator.free(entry.value_ptr.*);
    }
    
    // Free the HashMap structure
    self.headers.deinit();
}
```

## Why It Crashes

### The Mystery

The confusing part is that isolated tests work perfectly:

```zig
// This test passes without any issues
test "Response header cleanup" {
    var response = Response.init(allocator);
    defer response.deinit();
    
    try response.setHeader("Content-Type", "text/plain");
    try response.setHeader("Content-Length", "42");
    
    // deinit() successfully frees the headers
}
```

But in the actual server context, the same code crashes.

### Potential Causes

1. **Iterator Invalidation**: The HashMap iterator might be returning invalid pointers in certain contexts
2. **Memory Corruption**: Something else in the server might be corrupting the heap
3. **Allocator Issues**: The allocator state might be different between test and server contexts
4. **Timing/Threading**: There might be race conditions or timing-dependent behavior

### What We Know

- The crash happens specifically when dereferencing `entry.key_ptr.*`
- The pointer itself exists, but points to invalid memory
- The issue only manifests in the full server context, not in isolation
- Both `deinit()` and `reset()` exhibit the same crash

## Current Workaround

We've temporarily disabled the manual memory cleanup:

```zig
pub fn deinit(self: *Response) void {
    // TODO: Fix memory management issue with headers
    // Individual key/value strings will be leaked
    self.headers.deinit();  // Only frees the HashMap structure
}
```

This prevents the crash but causes a memory leak.

## Memory Leak Impact

### What Leaks

For each HTTP response, we leak:
- Every header name string
- Every header value string

### Example

A typical response might have:
```
Content-Type: application/json     (31 bytes)
Content-Length: 1234              (20 bytes)
Connection: close                 (17 bytes)
Cache-Control: no-cache           (23 bytes)
```

Total: ~91 bytes per request

### Severity

- **Short-lived servers**: Minor impact
- **Long-running servers**: Significant over time (91KB per 1000 requests)
- **High-traffic servers**: Could exhaust memory

## Potential Solutions

### 1. Different Data Structure

Instead of a HashMap, we could use:
- **ArrayList of key-value pairs**: Simpler memory management
- **Fixed-size array**: For common headers
- **Arena allocator**: Batch-free all headers at once

### 2. Reference Counting

Track references to headers and only free when count reaches zero.

### 3. Ownership Model

Change the ownership model so headers don't own their strings, but reference external storage.

### 4. Debug the Root Cause

- Add memory debugging tools
- Use Valgrind or AddressSanitizer
- Add extensive logging around the crash
- Check for heap corruption

## Code Examples

### Current (Leaking) Implementation

```zig
// Headers are set with allocated copies
try response.setHeader("Content-Type", "application/json");

// But cleanup is disabled to prevent crashes
pub fn deinit(self: *Response) void {
    self.headers.deinit();  // Only frees HashMap, not entries
}
```

### What Should Work (But Crashes)

```zig
pub fn deinit(self: *Response) void {
    // Free all entries
    var iter = self.headers.iterator();
    while (iter.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.*);
    }
    
    // Free the HashMap
    self.headers.deinit();
}
```

### Alternative Approach (Arena Allocator)

```zig
pub const Response = struct {
    headers: Headers,
    header_arena: std.heap.ArenaAllocator,
    
    pub fn init(allocator: Allocator) Response {
        var arena = std.heap.ArenaAllocator.init(allocator);
        return .{
            .headers = Headers.init(arena.allocator()),
            .header_arena = arena,
        };
    }
    
    pub fn deinit(self: *Response) void {
        self.headers.deinit();
        self.header_arena.deinit();  // Frees all headers at once
    }
};
```

## Next Steps

1. **Investigation**: Add debugging to understand why the iterator returns bad pointers
2. **Testing**: Create tests that reproduce the server context more accurately
3. **Alternative Design**: Consider if HashMap is the right choice for headers
4. **Proper Fix**: Implement a solution that doesn't leak memory

## References

- [Zig HashMap Documentation](https://ziglang.org/documentation/master/std/#A;std:hash_map)
- [Memory Management in Zig](https://ziglearn.org/chapter-2/)
- Original issue: Bus error when freeing HashMap entries in server context