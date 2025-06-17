//! Utility module entry point
//! This module exports all utility functions for convenient one-time import in other modules

// Export logger module
pub const logger = @import("logger.zig");

// Export common logging types and functions for direct use
pub const log = logger.log; // Base logging function
pub const logDefault = logger.logDefault; // Logging function with default configuration
pub const LogType = logger.LogType; // Log type enumeration
pub const LogConfig = logger.LogConfig; // Log configuration struct
pub const Logger = logger.Logger; // Logger struct
