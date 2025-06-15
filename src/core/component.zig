//! Component system for H3 framework
//! Provides interfaces and base types for decoupled component architecture

const std = @import("std");
const config = @import("config.zig");
const MemoryManager = @import("memory_manager.zig").MemoryManager;

/// Component lifecycle states
pub const ComponentState = enum {
    uninitialized,
    initializing,
    initialized,
    starting,
    running,
    stopping,
    stopped,
    error_state,
};

/// Component interface for all H3 components
pub const Component = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        init: *const fn (*anyopaque, *ComponentContext) anyerror!void,
        deinit: *const fn (*anyopaque) void,
        start: *const fn (*anyopaque) anyerror!void,
        stop: *const fn (*anyopaque) anyerror!void,
        getState: *const fn (*anyopaque) ComponentState,
        getName: *const fn (*anyopaque) []const u8,
        getConfig: *const fn (*anyopaque) *const anyopaque,
        setConfig: *const fn (*anyopaque, *const anyopaque) anyerror!void,
    };

    /// Initialize the component
    pub fn init(self: Component, context: *ComponentContext) !void {
        return self.vtable.init(self.ptr, context);
    }

    /// Deinitialize the component
    pub fn deinit(self: Component) void {
        self.vtable.deinit(self.ptr);
    }

    /// Start the component
    pub fn start(self: Component) !void {
        return self.vtable.start(self.ptr);
    }

    /// Stop the component
    pub fn stop(self: Component) !void {
        return self.vtable.stop(self.ptr);
    }

    /// Get component state
    pub fn getState(self: Component) ComponentState {
        return self.vtable.getState(self.ptr);
    }

    /// Get component name
    pub fn getName(self: Component) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    /// Get component configuration
    pub fn getConfig(self: Component, comptime T: type) *const T {
        const config_ptr = self.vtable.getConfig(self.ptr);
        return @ptrCast(@alignCast(config_ptr));
    }

    /// Set component configuration
    pub fn setConfig(self: Component, new_config: anytype) !void {
        return self.vtable.setConfig(self.ptr, &new_config);
    }
};

/// Component context provides shared resources
pub const ComponentContext = struct {
    allocator: std.mem.Allocator,
    memory_manager: *MemoryManager,
    config: *const config.H3Config,
    logger: Logger,

    /// Create a new component context
    pub fn init(
        allocator: std.mem.Allocator,
        memory_manager: *MemoryManager,
        h3_config: *const config.H3Config,
    ) ComponentContext {
        return ComponentContext{
            .allocator = allocator,
            .memory_manager = memory_manager,
            .config = h3_config,
            .logger = Logger.init(h3_config.monitoring.log_level),
        };
    }
};

/// Simple logger for components
pub const Logger = struct {
    level: config.MonitoringConfig.LogLevel,

    pub fn init(level: config.MonitoringConfig.LogLevel) Logger {
        return Logger{ .level = level };
    }

    pub fn debug(self: Logger, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(config.MonitoringConfig.LogLevel.debug)) {
            std.log.debug(fmt, args);
        }
    }

    pub fn info(self: Logger, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(config.MonitoringConfig.LogLevel.info)) {
            std.log.info(fmt, args);
        }
    }

    pub fn warn(self: Logger, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(config.MonitoringConfig.LogLevel.warn)) {
            std.log.warn(fmt, args);
        }
    }

    pub fn err(self: Logger, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(config.MonitoringConfig.LogLevel.err)) {
            std.log.err(fmt, args);
        }
    }
};

/// Base component implementation
pub fn BaseComponent(comptime T: type, comptime ConfigType: type) type {
    return struct {
        const Self = @This();

        state: ComponentState = .uninitialized,
        context: ?*ComponentContext = null,
        component_config: ConfigType,
        name: []const u8,

        /// Create component interface
        pub fn component(self: *Self) Component {
            return Component{
                .ptr = self,
                .vtable = &.{
                    .init = init,
                    .deinit = deinit,
                    .start = start,
                    .stop = stop,
                    .getState = getState,
                    .getName = getName,
                    .getConfig = getConfig,
                    .setConfig = setConfig,
                },
            };
        }

        fn init(ptr: *anyopaque, context: *ComponentContext) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.state = .initializing;
            self.context = context;

            // Call derived class init if available
            if (@hasDecl(T, "initImpl")) {
                try T.initImpl(@fieldParentPtr("base", self), context);
            }

            self.state = .initialized;
            context.logger.info("Component '{s}' initialized", .{self.name});
        }

        fn deinit(ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ptr));

            // Call derived class deinit if available
            if (@hasDecl(T, "deinitImpl")) {
                T.deinitImpl(@fieldParentPtr("base", self));
            }

            self.state = .uninitialized;
            if (self.context) |context| {
                context.logger.info("Component '{s}' deinitialized", .{self.name});
            }
        }

        fn start(ptr: *anyopaque) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            if (self.state != .initialized) return error.InvalidState;

            self.state = .starting;

            // Call derived class start if available
            if (@hasDecl(T, "startImpl")) {
                try T.startImpl(@fieldParentPtr("base", self));
            }

            self.state = .running;
            if (self.context) |context| {
                context.logger.info("Component '{s}' started", .{self.name});
            }
        }

        fn stop(ptr: *anyopaque) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            if (self.state != .running) return error.InvalidState;

            self.state = .stopping;

            // Call derived class stop if available
            if (@hasDecl(T, "stopImpl")) {
                try T.stopImpl(@fieldParentPtr("base", self));
            }

            self.state = .stopped;
            if (self.context) |context| {
                context.logger.info("Component '{s}' stopped", .{self.name});
            }
        }

        fn getState(ptr: *anyopaque) ComponentState {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return self.state;
        }

        fn getName(ptr: *anyopaque) []const u8 {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return self.name;
        }

        fn getConfig(ptr: *anyopaque) *const anyopaque {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return &self.component_config;
        }

        fn setConfig(ptr: *anyopaque, new_config: *const anyopaque) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const typed_config: *const ConfigType = @ptrCast(@alignCast(new_config));
            self.component_config = typed_config.*;

            // Call derived class config update if available
            if (@hasDecl(T, "configUpdated")) {
                try T.configUpdated(@fieldParentPtr("base", self));
            }
        }
    };
}

/// Component registry for managing components
pub const ComponentRegistry = struct {
    components: std.ArrayList(Component),
    allocator: std.mem.Allocator,
    context: ComponentContext,

    const Self = @This();

    /// Initialize component registry
    pub fn init(
        allocator: std.mem.Allocator,
        memory_manager: *MemoryManager,
        h3_config: *const config.H3Config,
    ) Self {
        return Self{
            .components = std.ArrayList(Component).init(allocator),
            .allocator = allocator,
            .context = ComponentContext.init(allocator, memory_manager, h3_config),
        };
    }

    /// Deinitialize component registry
    pub fn deinit(self: *Self) void {
        // Stop and deinitialize all components in reverse order
        var i = self.components.items.len;
        while (i > 0) {
            i -= 1;
            const component = self.components.items[i];
            if (component.getState() == .running) {
                component.stop() catch |err| {
                    self.context.logger.err("Failed to stop component '{s}': {}", .{ component.getName(), err });
                };
            }
            component.deinit();
        }
        self.components.deinit();
    }

    /// Register a component
    pub fn register(self: *Self, component: Component) !void {
        try component.init(&self.context);
        try self.components.append(component);
        self.context.logger.info("Registered component '{s}'", .{component.getName()});
    }

    /// Start all components
    pub fn startAll(self: *Self) !void {
        for (self.components.items) |component| {
            try component.start();
        }
        self.context.logger.info("Started all components", .{});
    }

    /// Stop all components
    pub fn stopAll(self: *Self) !void {
        // Stop in reverse order
        var i = self.components.items.len;
        while (i > 0) {
            i -= 1;
            try self.components.items[i].stop();
        }
        self.context.logger.info("Stopped all components", .{});
    }

    /// Find component by name
    pub fn find(self: *Self, name: []const u8) ?Component {
        for (self.components.items) |component| {
            if (std.mem.eql(u8, component.getName(), name)) {
                return component;
            }
        }
        return null;
    }

    /// Get all components with specific state
    pub fn getByState(self: *Self, state: ComponentState, allocator: std.mem.Allocator) ![]Component {
        var result = std.ArrayList(Component).init(allocator);
        for (self.components.items) |component| {
            if (component.getState() == state) {
                try result.append(component);
            }
        }
        return result.toOwnedSlice();
    }

    /// Get component count
    pub fn count(self: *const Self) usize {
        return self.components.items.len;
    }

    /// Get health status of all components
    pub fn getHealthStatus(self: *Self) struct { healthy: usize, total: usize } {
        var healthy: usize = 0;
        for (self.components.items) |component| {
            const state = component.getState();
            if (state == .running or state == .initialized) {
                healthy += 1;
            }
        }
        return .{ .healthy = healthy, .total = self.components.items.len };
    }
};

test "Component lifecycle" {
    const TestComponent = struct {
        base: BaseComponent(@This(), config.RouterConfig),

        pub fn initImpl(self: *@This(), context: *ComponentContext) !void {
            _ = self;
            _ = context;
        }

        pub fn startImpl(self: *@This()) !void {
            _ = self;
        }

        pub fn stopImpl(self: *@This()) !void {
            _ = self;
        }
    };

    var memory_manager = try MemoryManager.init(std.testing.allocator, config.MemoryConfig{});
    defer memory_manager.deinit();

    var registry = ComponentRegistry.init(std.testing.allocator, &memory_manager, &config.H3Config{});
    defer registry.deinit();

    var test_component = TestComponent{
        .base = .{
            .component_config = config.RouterConfig{},
            .name = "test",
        },
    };

    try registry.register(test_component.base.component());
    try registry.startAll();
    try registry.stopAll();

    try std.testing.expectEqual(@as(usize, 1), registry.count());
}
