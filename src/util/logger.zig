const std = @import("std");

// Import log options if available
const log_options = if (@hasDecl(@import("root"), "dependencies") and
    @hasDecl(@import("root").dependencies, "log_options"))
    @import("log_options")
else
    struct {
        pub const log_level = std.log.Level.debug;
        pub const enable_connection_logs = true;
        pub const enable_request_logs = true;
        pub const enable_performance_logs = true;
    };

/// Log type enum for categorizing different types of logs
pub const LogType = enum {
    connection, // Connection lifecycle logs
    request, // HTTP request processing logs
    performance, // Performance metrics logs
    general, // General purpose logs
};

/// Default log level from build options
pub const default_log_level: std.log.Level = log_options.log_level;

/// Log configuration struct to control which types of logs are enabled
pub const LogConfig = struct {
    level: std.log.Level = default_log_level,
    enable_connection_logs: bool = log_options.enable_connection_logs,
    enable_request_logs: bool = log_options.enable_request_logs,
    enable_performance_logs: bool = log_options.enable_performance_logs,
};

/// Global default log configuration
pub var default_config = LogConfig{
    .level = default_log_level,
    .enable_connection_logs = log_options.enable_connection_logs,
    .enable_request_logs = log_options.enable_request_logs,
    .enable_performance_logs = log_options.enable_performance_logs,
};

/// Log function that decides whether to output logs based on configuration
/// Parameters:
///   - level: Log level
///   - log_type: Type of log
///   - fmt: Format string
///   - args: Format arguments
///   - config: Log configuration, defaults to global config
pub fn log(
    comptime level: std.log.Level,
    comptime log_type: LogType,
    comptime fmt: []const u8,
    args: anytype,
    config: LogConfig,
) void {
    // First check global log level - only output if level is at least as important as min level
    // For example, if config level is .info, we skip .debug logs but show .info, .warn, .err
    const level_value = @intFromEnum(level);
    const min_level_value = @intFromEnum(config.level);
    if (level_value < min_level_value) {
        return;
    }

    // Then check if specific log type is enabled
    switch (log_type) {
        .connection => if (!config.enable_connection_logs) return,
        .request => if (!config.enable_request_logs) return,
        .performance => if (!config.enable_performance_logs) return,
        .general => {}, // Always enabled if level passes
    }

    // If we get here, output the log
    switch (level) {
        .debug => std.log.debug(fmt, args),
        .info => std.log.info(fmt, args),
        .warn => std.log.warn(fmt, args),
        .err => std.log.err(fmt, args),
    }
}

/// Convenience wrapper for log function with default config
pub fn logDefault(
    comptime level: std.log.Level,
    comptime log_type: LogType,
    comptime fmt: []const u8,
    args: anytype,
) void {
    log(level, log_type, fmt, args, default_config);
}

/// Set global log configuration
pub fn setGlobalConfig(config: LogConfig) void {
    default_config = config;
}

/// Logger struct for creating loggers with custom configurations
pub const Logger = struct {
    config: LogConfig,

    pub fn init(config: LogConfig) Logger {
        return .{ .config = config };
    }

    pub fn log(
        self: *const Logger,
        comptime level: std.log.Level,
        comptime log_type: LogType,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        @import("logger.zig").log(level, log_type, fmt, args, self.config);
    }
};

// Tests
test "logger.basic" {
    // Test default configuration
    logDefault(.debug, .general, "This is a debug message", .{});
    logDefault(.info, .connection, "This is a connection info", .{});

    // Test custom configuration
    const test_config = LogConfig{
        .level = .warn,
        .enable_connection_logs = false,
    };

    // These logs should not be output
    log(.debug, .general, "This should not be logged (level too low)", .{}, test_config);
    log(.info, .connection, "This should not be logged (connection logs disabled)", .{}, test_config);

    // These logs should be output
    log(.warn, .general, "This should be logged (warn level)", .{}, test_config);
    log(.err, .connection, "This should be logged (error overrides connection disabled)", .{}, test_config);

    // Test logger
    var logger = Logger.init(.{
        .level = .info,
        .enable_performance_logs = false,
    });

    logger.log(.info, .request, "This should be logged", .{});
    logger.log(.debug, .performance, "This should not be logged", .{});
}
