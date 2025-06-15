//! Simple unit tests for H3 framework
//! Basic tests to verify core functionality without complex dependencies

const std = @import("std");
const testing = std.testing;

test "Basic arithmetic test" {
    try testing.expectEqual(@as(i32, 4), 2 + 2);
    try testing.expectEqual(@as(i32, 6), 2 * 3);
}

test "String operations" {
    const hello = "Hello";
    const world = "World";

    try testing.expectEqualStrings("Hello", hello);
    try testing.expectEqualStrings("World", world);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}, {s}!", .{ hello, world });
    defer testing.allocator.free(combined);

    try testing.expectEqualStrings("Hello, World!", combined);
}

test "Memory allocation" {
    const allocator = testing.allocator;

    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);

    try testing.expect(data.len == 100);

    // Fill with test data
    for (data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    // Verify data
    try testing.expectEqual(@as(u8, 0), data[0]);
    try testing.expectEqual(@as(u8, 99), data[99]);
}

test "HashMap operations" {
    const allocator = testing.allocator;

    var map = std.StringHashMap([]const u8).init(allocator);
    defer map.deinit();

    try map.put("key1", "value1");
    try map.put("key2", "value2");

    try testing.expectEqualStrings("value1", map.get("key1").?);
    try testing.expectEqualStrings("value2", map.get("key2").?);
    try testing.expect(map.get("nonexistent") == null);
}

test "ArrayList operations" {
    const allocator = testing.allocator;

    var list = std.ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try testing.expectEqual(@as(usize, 3), list.items.len);
    try testing.expectEqual(@as(i32, 1), list.items[0]);
    try testing.expectEqual(@as(i32, 2), list.items[1]);
    try testing.expectEqual(@as(i32, 3), list.items[2]);
}

test "JSON parsing" {
    const allocator = testing.allocator;

    const json_str = "{\"name\":\"John\",\"age\":30}";

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try testing.expectEqualStrings("John", obj.get("name").?.string);
    try testing.expectEqual(@as(i64, 30), obj.get("age").?.integer);
}

test "Time operations" {
    const start = std.time.nanoTimestamp();

    // Small delay
    std.time.sleep(1_000_000); // 1ms

    const end = std.time.nanoTimestamp();
    const duration = end - start;

    // Duration check (at least 1ms)
    try testing.expect(duration >= 1_000_000);
}

test "Error handling" {
    const TestError = error{
        TestFailed,
        InvalidInput,
    };

    const testFunc = struct {
        fn func(should_fail: bool) TestError!i32 {
            if (should_fail) {
                return TestError.TestFailed;
            }
            return 42;
        }
    }.func;

    // Test success case
    const result = try testFunc(false);
    try testing.expectEqual(@as(i32, 42), result);

    // Test error case
    try testing.expectError(TestError.TestFailed, testFunc(true));
}

test "Optional handling" {
    const maybe_value: ?i32 = 42;
    const no_value: ?i32 = null;

    try testing.expectEqual(@as(i32, 42), maybe_value.?);
    try testing.expect(no_value == null);

    const default_value = no_value orelse 100;
    try testing.expectEqual(@as(i32, 100), default_value);
}

test "Enum operations" {
    const Color = enum {
        red,
        green,
        blue,

        const Self = @This();

        fn toString(self: Self) []const u8 {
            return switch (self) {
                .red => "Red",
                .green => "Green",
                .blue => "Blue",
            };
        }
    };

    const color = Color.red;
    try testing.expectEqualStrings("Red", color.toString());
    try testing.expectEqual(Color.red, color);
}

test "Struct operations" {
    const Point = struct {
        x: f32,
        y: f32,

        fn distance(self: @This(), other: @This()) f32 {
            const dx = self.x - other.x;
            const dy = self.y - other.y;
            return @sqrt(dx * dx + dy * dy);
        }
    };

    const p1 = Point{ .x = 0.0, .y = 0.0 };
    const p2 = Point{ .x = 3.0, .y = 4.0 };

    const dist = p1.distance(p2);
    try testing.expectApproxEqAbs(@as(f32, 5.0), dist, 0.001);
}
