# H3 OpenAPI Direct Integration Design

## Overview

This document outlines how OpenAPI schema export will be directly integrated into H3's core router, making it a built-in feature rather than a separate module. The design maintains H3's philosophy of zero-cost abstractions while providing automatic API documentation.

## Core Design Principles

1. **Built-in, not bolted-on**: OpenAPI is a first-class citizen in the router
2. **Zero overhead**: Routes without OpenAPI metadata have no performance impact
3. **Type-safe by default**: Leverage Zig's comptime for schema generation
4. **Progressive enhancement**: Start with regular handlers, add types when needed

## Architecture Changes

### 1. Enhanced Handler System

```zig
// src/core/handler.zig
const std = @import("std");
const H3Event = @import("event.zig").H3Event;

/// Handler types supported by the router
pub const HandlerType = enum {
    regular,        // Legacy: fn(*H3Event) !void
    typed,          // Typed: fn(*H3Event, Request) !Response
    parameterized,  // Path/query only: fn(*H3Event) !Response
    streaming,      // SSE/WebSocket: fn(*H3Event, *Stream) !void
};

/// Unified handler representation
pub const TypedHandler = union(HandlerType) {
    regular: *const fn (*H3Event) anyerror!void,
    typed: struct {
        handler: *const fn (*H3Event) anyerror!void,
        request_schema: ?Schema,
        response_schema: ?Schema,
        metadata: RouteMetadata,
    },
    parameterized: struct {
        handler: *const fn (*H3Event) anyerror!void,
        response_schema: ?Schema,
        metadata: RouteMetadata,
    },
    streaming: struct {
        handler: *const fn (*H3Event) anyerror!void,
        metadata: RouteMetadata,
    },
};

/// Route metadata for OpenAPI
pub const RouteMetadata = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    operation_id: ?[]const u8 = null,
    deprecated: bool = false,
    parameters: []const Parameter = &.{},
    responses: []const Response = &.{},
    security: []const Security = &.{},
};

/// Auto-detect handler type at compile time
pub fn autoDetect(comptime handler: anytype) TypedHandler {
    const T = @TypeOf(handler);
    const type_info = @typeInfo(T);
    
    // Check if it's a regular handler
    if (type_info == .Fn and type_info.Fn.params.len == 1) {
        return .{ .regular = handler };
    }
    
    // Check if it's a typed handler struct
    if (@hasField(T, "handler") and @hasField(T, "metadata")) {
        if (@hasField(T, "request_schema")) {
            return .{ .typed = handler };
        } else {
            return .{ .parameterized = handler };
        }
    }
    
    // Default to regular
    return .{ .regular = handler };
}
```

### 2. Router with Built-in OpenAPI

```zig
// Update src/core/router.zig

pub const Router = struct {
    // ... existing fields ...
    
    /// OpenAPI info (optional, enables OpenAPI generation)
    openapi_info: ?OpenAPIInfo = null,
    
    /// Initialize router with optional OpenAPI support
    pub fn init(allocator: std.mem.Allocator) !Router {
        return Router.initWithOptions(allocator, .{});
    }
    
    pub fn initWithOptions(allocator: std.mem.Allocator, options: RouterOptions) !Router {
        var router = Router{
            // ... existing initialization ...
            .openapi_info = options.openapi_info,
        };
        return router;
    }
    
    /// Add any type of handler
    pub fn addRoute(self: *Router, method: HttpMethod, pattern: []const u8, handler: anytype) !void {
        const typed_handler = autoDetect(handler);
        
        // Store in trie for routing
        const raw_handler = switch (typed_handler) {
            .regular => |h| h,
            .typed => |t| t.handler,
            .parameterized => |p| p.handler,
            .streaming => |s| s.handler,
        };
        
        try self.trie_router.addRoute(method, pattern, raw_handler);
        
        // Store full route info including OpenAPI metadata
        try self.method_routes[@intFromEnum(method)].append(.{
            .method = method,
            .pattern = pattern,
            .handler = raw_handler,
            .typed_handler = typed_handler,
        });
    }
    
    /// Generate OpenAPI specification
    pub fn generateOpenAPI(self: *const Router) ?OpenAPISpec {
        const info = self.openapi_info orelse return null;
        
        var spec = OpenAPISpec{
            .openapi = "3.1.0",
            .info = info,
            .paths = Paths.init(self.allocator),
        };
        
        // Iterate through all routes
        inline for (std.meta.fields(HttpMethod)) |field| {
            const method = @field(HttpMethod, field.name);
            const routes = self.method_routes[@intFromEnum(method)];
            
            for (routes.items) |route| {
                // Convert route to OpenAPI path
                const path = convertToOpenAPIPath(route.pattern);
                
                // Get or create path item
                const path_item = spec.paths.getOrPut(path) catch continue;
                if (!path_item.found_existing) {
                    path_item.value_ptr.* = PathItem{};
                }
                
                // Create operation from route
                const operation = createOperation(route);
                
                // Set operation on path item
                switch (method) {
                    .GET => path_item.value_ptr.get = operation,
                    .POST => path_item.value_ptr.post = operation,
                    .PUT => path_item.value_ptr.put = operation,
                    .DELETE => path_item.value_ptr.delete = operation,
                    .PATCH => path_item.value_ptr.patch = operation,
                    // ... other methods
                }
            }
        }
        
        return spec;
    }
};

pub const RouterOptions = struct {
    // ... existing options ...
    openapi_info: ?OpenAPIInfo = null,
};

pub const OpenAPIInfo = struct {
    title: []const u8,
    version: []const u8,
    description: ?[]const u8 = null,
    terms_of_service: ?[]const u8 = null,
    contact: ?Contact = null,
    license: ?License = null,
};
```

### 3. Schema Generation (Built into Router)

```zig
// src/core/schema.zig (part of core, not separate module)

pub const Schema = struct {
    type: SchemaType,
    format: ?[]const u8 = null,
    description: ?[]const u8 = null,
    example: ?[]const u8 = null,
    required: bool = true,
    nullable: bool = false,
    // ... other OpenAPI schema fields
};

/// Generate schema from Zig type at compile time
pub fn schemaFromType(comptime T: type) Schema {
    const type_info = @typeInfo(T);
    
    return switch (type_info) {
        .Bool => .{ .type = .boolean },
        .Int => |int| .{ 
            .type = .integer,
            .format = if (int.bits == 32) "int32" else if (int.bits == 64) "int64" else null,
        },
        .Float => |float| .{ 
            .type = .number,
            .format = if (float.bits == 32) "float" else if (float.bits == 64) "double" else null,
        },
        .Pointer => |ptr| blk: {
            if (ptr.child == u8 and ptr.size == .Slice) {
                break :blk .{ .type = .string };
            }
            break :blk schemaFromType(ptr.child);
        },
        .Struct => |s| blk: {
            // Generate object schema with properties
            var properties = std.StringHashMap(Schema).init(std.heap.page_allocator);
            inline for (s.fields) |field| {
                properties.put(field.name, schemaFromType(field.type)) catch {};
            }
            break :blk .{
                .type = .object,
                .properties = properties,
            };
        },
        .Optional => |opt| blk: {
            var schema = schemaFromType(opt.child);
            schema.nullable = true;
            schema.required = false;
            break :blk schema;
        },
        else => .{ .type = .string }, // Fallback
    };
}
```

### 4. Enhanced App with Built-in OpenAPI

```zig
// Update src/core/app.zig

pub const H3App = struct {
    // ... existing fields ...
    
    /// Enable OpenAPI with info
    pub fn enableOpenAPI(self: *H3App, info: OpenAPIInfo) void {
        self.router.openapi_info = info;
    }
    
    /// Add OpenAPI endpoint
    pub fn serveOpenAPI(self: *H3App, path: []const u8) !void {
        const handler = struct {
            fn handle(event: *H3Event) !void {
                const app = @fieldParentPtr(H3App, "router", event.app);
                const spec = app.router.generateOpenAPI() orelse {
                    return event.sendError(.not_found, "OpenAPI not enabled");
                };
                
                const json = try std.json.stringifyAlloc(event.allocator, spec, .{});
                defer event.allocator.free(json);
                
                try event.sendJson(json);
            }
        }.handle;
        
        try self.router.addRoute(.GET, path, handler);
    }
    
    /// Add Swagger UI endpoint
    pub fn serveSwaggerUI(self: *H3App, ui_path: []const u8, spec_path: []const u8) !void {
        const handler = struct {
            fn handle(event: *H3Event) !void {
                const html = try std.fmt.allocPrint(event.allocator,
                    \\<!DOCTYPE html>
                    \\<html>
                    \\<head>
                    \\    <title>API Documentation</title>
                    \\    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist/swagger-ui.css">
                    \\</head>
                    \\<body>
                    \\    <div id="swagger-ui"></div>
                    \\    <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist/swagger-ui-bundle.js"></script>
                    \\    <script>
                    \\        SwaggerUIBundle({{
                    \\            url: '{s}',
                    \\            dom_id: '#swagger-ui'
                    \\        }})
                    \\    </script>
                    \\</body>
                    \\</html>
                , .{spec_path});
                defer event.allocator.free(html);
                
                try event.sendHtml(html);
            }
        }.handle;
        
        try self.router.addRoute(.GET, ui_path, handler);
    }
};
```

### 5. Helper Functions in Root

```zig
// Add to src/root.zig

/// Create a typed handler with automatic schema generation
pub fn typedHandler(
    comptime Request: type,
    comptime Response: type,
    comptime handler_fn: fn (*H3Event, Request) anyerror!Response,
    metadata: RouteMetadata,
) TypedHandler {
    const wrapper = struct {
        fn handle(event: *H3Event) anyerror!void {
            const req = if (Request == void) {} else try event.readJson(Request);
            const res = try handler_fn(event, req);
            if (Response != void) try event.sendJsonValue(res);
        }
    }.handle;
    
    return .{
        .typed = .{
            .handler = wrapper,
            .request_schema = if (Request == void) null else schemaFromType(Request),
            .response_schema = if (Response == void) null else schemaFromType(Response),
            .metadata = metadata,
        },
    };
}

/// Create a parameterized handler (no request body)
pub fn paramHandler(
    comptime Response: type,
    comptime handler_fn: fn (*H3Event) anyerror!Response,
    metadata: RouteMetadata,
) TypedHandler {
    const wrapper = struct {
        fn handle(event: *H3Event) anyerror!void {
            const res = try handler_fn(event);
            if (Response != void) try event.sendJsonValue(res);
        }
    }.handle;
    
    return .{
        .parameterized = .{
            .handler = wrapper,
            .response_schema = if (Response == void) null else schemaFromType(Response),
            .metadata = metadata,
        },
    };
}

/// Quick route metadata helper
pub fn route(config: struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
}) RouteMetadata {
    return .{
        .summary = config.summary,
        .description = config.description,
        .tags = config.tags,
    };
}
```

## Usage Examples

### Basic Usage

```zig
const std = @import("std");
const h3 = @import("h3");

pub fn main() !void {
    var app = try h3.createApp(allocator);
    defer app.deinit();
    
    // Enable OpenAPI
    app.enableOpenAPI(.{
        .title = "My API",
        .version = "1.0.0",
        .description = "A simple API with OpenAPI support",
    });
    
    // Regular handler (works as before)
    try app.get("/", homeHandler);
    
    // Typed handler with OpenAPI
    const createUser = h3.typedHandler(
        CreateUserRequest,
        User,
        createUserHandler,
        h3.route(.{
            .summary = "Create a new user",
            .tags = &.{"users"},
        }),
    );
    try app.post("/users", createUser);
    
    // Parameterized handler
    const getUser = h3.paramHandler(
        User,
        getUserHandler,
        h3.route(.{
            .summary = "Get user by ID",
            .tags = &.{"users"},
        }),
    );
    try app.get("/users/:id", getUser);
    
    // Serve OpenAPI spec and docs
    try app.serveOpenAPI("/openapi.json");
    try app.serveSwaggerUI("/docs", "/openapi.json");
    
    try h3.serve(&app, .{ .port = 3000 });
}

// Types
const CreateUserRequest = struct {
    name: []const u8,
    email: []const u8,
};

const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
};

// Handlers
fn homeHandler(event: *h3.Event) !void {
    try event.sendText("Welcome!");
}

fn createUserHandler(event: *h3.Event, req: CreateUserRequest) !User {
    // Create user...
    return User{
        .id = 123,
        .name = req.name,
        .email = req.email,
    };
}

fn getUserHandler(event: *h3.Event) !User {
    const id = h3.getParam(event, "id") orelse return error.NotFound;
    // Get user...
    return User{
        .id = try std.fmt.parseInt(u32, id, 10),
        .name = "John Doe",
        .email = "john@example.com",
    };
}
```

### Advanced Usage

```zig
// Custom schema attributes
const EmailString = struct {
    value: []const u8,
    
    pub const schema = h3.Schema{
        .type = .string,
        .format = "email",
        .pattern = "^[\\w.-]+@[\\w.-]+\\.\\w+$",
    };
};

// Complex handler with full metadata
const handler = h3.typedHandler(
    LoginRequest,
    LoginResponse,
    loginHandler,
    .{
        .summary = "User login",
        .description = "Authenticate user and return access token",
        .tags = &.{"auth"},
        .responses = &.{
            .{ .status = 200, .description = "Login successful" },
            .{ .status = 401, .description = "Invalid credentials" },
            .{ .status = 429, .description = "Too many attempts" },
        },
        .security = &.{
            .{ .type = "apiKey", .name = "X-API-Key", .in = "header" },
        },
    },
);
```

## Benefits of Direct Integration

1. **Simpler API**: No need to import separate OpenAPI module
2. **Better Performance**: Tighter integration with router internals
3. **Easier Adoption**: OpenAPI is just a flag away
4. **Type Safety**: Same compile-time guarantees
5. **Zero Config**: Works out of the box with sensible defaults

## Implementation Phases

1. **Phase 1**: Update handler system in router
2. **Phase 2**: Add schema generation to core
3. **Phase 3**: Integrate OpenAPI generation into router
4. **Phase 4**: Add helper functions to root.zig
5. **Phase 5**: Update examples and tests

## Migration Path

For existing H3 apps:
1. No changes needed - existing handlers continue to work
2. Call `app.enableOpenAPI()` to turn on OpenAPI support
3. Gradually convert handlers to typed handlers for documentation
4. Add `/openapi.json` endpoint when ready

## Performance Guarantees

- Zero overhead for routes without OpenAPI metadata
- Schema generation happens at compile time
- OpenAPI spec generation only when explicitly requested
- No runtime type checking or validation overhead