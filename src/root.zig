//! H3 - Zero-dependency HTTP framework for Zig
//!
//! H3 is a fast, lightweight HTTP framework inspired by H3.js but built specifically for Zig.
//! It provides a clean API for building web applications and APIs with zero external dependencies.
//!
//! This is the legacy entry point. Use the new h3.zig module for the modern API.

// Re-export the new API
pub usingnamespace @import("h3.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
