//! String formatting utilities
//!
//! This module provides string formatting functions for use across the library.

const std = @import("std");

/// Convert snake_case string to Title Case at compile time
/// Example: "not_found" -> "Not Found"
pub fn snakeCaseToTitleCase(comptime snake_case: []const u8) *const [snake_case.len]u8 {
    comptime {
        @setEvalBranchQuota(10000);
        var result: [snake_case.len]u8 = undefined;
        var capitalize = true;
        
        for (snake_case, 0..) |c, i| {
            if (c == '_') {
                result[i] = ' ';
                capitalize = true;
            } else if (capitalize) {
                result[i] = std.ascii.toUpper(c);
                capitalize = false;
            } else {
                result[i] = c;
            }
        }
        
        const final = result;
        return &final;
    }
}

// Tests
test "snakeCaseToTitleCase" {
    const testing = std.testing;
    
    // Basic cases
    try testing.expectEqualStrings("Not Found", comptime snakeCaseToTitleCase("not_found"));
    try testing.expectEqualStrings("Bad Request", comptime snakeCaseToTitleCase("bad_request"));
    try testing.expectEqualStrings("Internal Server Error", comptime snakeCaseToTitleCase("internal_server_error"));
    
    // Single word
    try testing.expectEqualStrings("Created", comptime snakeCaseToTitleCase("created"));
    
    // Already capitalized
    try testing.expectEqualStrings("Ok", comptime snakeCaseToTitleCase("ok"));
    
    // With underscores at end (like continue_)
    try testing.expectEqualStrings("Continue ", comptime snakeCaseToTitleCase("continue_"));
}