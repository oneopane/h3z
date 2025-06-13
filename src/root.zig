//! ZH3 - A Zig HTTP framework inspired by H3.js
//!
//! ZH3 is a minimal, fast, and composable HTTP server framework for Zig.
//! It provides a simple API for building web applications and APIs.

const std = @import("std");

// Re-export core modules
pub const H3 = @import("core/app.zig").H3;
pub const H3Event = @import("core/event.zig").H3Event;
pub const HttpMethod = @import("http/method.zig").HttpMethod;
pub const HttpStatus = @import("http/status.zig").HttpStatus;

// Re-export utility functions
pub const utils = @import("utils.zig");

// Re-export server functions
pub const serve = @import("server/serve.zig").serve;

test {
    // Import all test files
    _ = @import("core/app.zig");
    _ = @import("core/event.zig");
    _ = @import("http/method.zig");
    _ = @import("http/status.zig");
}
