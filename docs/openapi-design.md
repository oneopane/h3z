# H3 OpenAPI Schema Export Design

## Overview

This document outlines the design for adding OpenAPI schema export capabilities to the H3 Zig HTTP framework. The design prioritizes:
- Type-safe schema generation using Zig's comptime features
- Zero-cost abstractions that don't impact runtime performance
- Backward compatibility with existing handler signatures
- Compile-time validation of schemas

## Architecture

### 1. Schema Definition System

#### Core Schema Types

```zig
// src/openapi/schema.zig
pub const SchemaType = enum {
    string,
    number,
    integer,
    boolean,
    array,
    object,
    null,
};

pub const Schema = struct {
    type: SchemaType,
    description: ?[]const u8 = null,
    required: bool = false,
    items: ?*const Schema = null, // For arrays
    properties: ?std.StringHashMap(*const Schema) = null, // For objects
    example: ?[]const u8 = null,
    format: ?[]const u8 = null, // e.g., "date-time", "email"
    minimum: ?f64 = null,
    maximum: ?f64 = null,
    pattern: ?[]const u8 = null,
    enum_values: ?[]const []const u8 = null,
};

/// Generate schema from Zig type at compile time
pub fn schemaFromType(comptime T: type) Schema {
    const type_info = @typeInfo(T);
    
    return switch (type_info) {
        .Bool => .{ .type = .boolean },
        .Int => .{ .type = .integer },
        .Float => .{ .type = .number },
        .Pointer => |ptr| blk: {
            if (ptr.child == u8 and ptr.size == .Slice) {
                break :blk .{ .type = .string };
            }
            // Handle other pointer types
            break :blk .{ .type = .string };
        },
        .Array => |arr| .{
            .type = .array,
            .items = &schemaFromType(arr.child),
        },
        .Struct => |s| blk: {
            var properties = std.StringHashMap(*const Schema).init(std.heap.page_allocator);
            inline for (s.fields) |field| {
                properties.put(field.name, &schemaFromType(field.type)) catch {};
            }
            break :blk .{
                .type = .object,
                .properties = properties,
            };
        },
        .Optional => |opt| schemaFromType(opt.child),
        else => .{ .type = .string }, // Fallback
    };
}
```

### 2. Enhanced Route Definition

#### Route Metadata

```zig
// src/openapi/route_metadata.zig
pub const RouteMetadata = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: ?[]const []const u8 = null,
    operation_id: ?[]const u8 = null,
    deprecated: bool = false,
    request_body: ?RequestBodyMetadata = null,
    responses: []const ResponseMetadata,
    parameters: []const ParameterMetadata = &.{},
    security: ?[]const SecurityRequirement = null,
};

pub const RequestBodyMetadata = struct {
    description: ?[]const u8 = null,
    required: bool = true,
    content: []const MediaType,
};

pub const ResponseMetadata = struct {
    status: u16,
    description: []const u8,
    content: ?[]const MediaType = null,
    headers: ?[]const HeaderMetadata = null,
};

pub const MediaType = struct {
    media_type: []const u8, // e.g., "application/json"
    schema: Schema,
    example: ?[]const u8 = null,
};

pub const ParameterMetadata = struct {
    name: []const u8,
    in: enum { path, query, header, cookie },
    description: ?[]const u8 = null,
    required: bool = false,
    schema: Schema,
    example: ?[]const u8 = null,
};
```

#### Enhanced Handler Type

```zig
// src/openapi/handler.zig
pub fn TypedHandler(comptime RequestType: type, comptime ResponseType: type) type {
    return struct {
        pub const Request = RequestType;
        pub const Response = ResponseType;
        
        handler: *const fn (*H3Event) anyerror!void,
        metadata: RouteMetadata,
        
        pub fn init(
            handler: *const fn (*H3Event) anyerror!void,
            metadata: RouteMetadata,
        ) @This() {
            return .{
                .handler = handler,
                .metadata = metadata,
            };
        }
    };
}

/// Wrapper to create a typed handler with automatic schema generation
pub fn typedHandler(
    comptime RequestType: type,
    comptime ResponseType: type,
    comptime handler_fn: fn (*H3Event, RequestType) anyerror!ResponseType,
    metadata: RouteMetadata,
) TypedHandler(RequestType, ResponseType) {
    const wrapper = struct {
        fn handle(event: *H3Event) anyerror!void {
            const req_data = try BodyParser.parseJson(event, RequestType);
            const resp_data = try handler_fn(event, req_data);
            try sendJson(event, resp_data);
        }
    }.handle;
    
    return TypedHandler(RequestType, ResponseType).init(wrapper, metadata);
}
```

### 3. Router Integration

#### Enhanced Router with Metadata Storage

```zig
// Extend the existing Router
pub const OpenAPIRouter = struct {
    base_router: Router,
    route_metadata: std.ArrayList(struct {
        method: HttpMethod,
        pattern: []const u8,
        metadata: RouteMetadata,
        request_schema: ?Schema,
        response_schema: ?Schema,
    }),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !OpenAPIRouter {
        return .{
            .base_router = try Router.init(allocator),
            .route_metadata = std.ArrayList(...).init(allocator),
            .allocator = allocator,
        };
    }
    
    /// Add a typed route with automatic schema extraction
    pub fn addTypedRoute(
        self: *OpenAPIRouter,
        method: HttpMethod,
        pattern: []const u8,
        comptime handler: anytype,
    ) !void {
        const HandlerType = @TypeOf(handler);
        
        // Extract request and response types
        const request_schema = schemaFromType(HandlerType.Request);
        const response_schema = schemaFromType(HandlerType.Response);
        
        // Add to base router
        try self.base_router.addRoute(method, pattern, handler.handler);
        
        // Store metadata
        try self.route_metadata.append(.{
            .method = method,
            .pattern = pattern,
            .metadata = handler.metadata,
            .request_schema = request_schema,
            .response_schema = response_schema,
        });
    }
    
    /// Add a regular route (backward compatibility)
    pub fn addRoute(
        self: *OpenAPIRouter,
        method: HttpMethod,
        pattern: []const u8,
        handler: Handler,
    ) !void {
        try self.base_router.addRoute(method, pattern, handler);
    }
};
```

### 4. OpenAPI Document Generation

```zig
// src/openapi/generator.zig
pub const OpenAPIGenerator = struct {
    pub const OpenAPIDocument = struct {
        openapi: []const u8 = "3.1.0",
        info: Info,
        servers: ?[]const Server = null,
        paths: std.StringHashMap(PathItem),
        components: ?Components = null,
        security: ?[]const SecurityRequirement = null,
        tags: ?[]const Tag = null,
    };
    
    pub const Info = struct {
        title: []const u8,
        version: []const u8,
        description: ?[]const u8 = null,
        termsOfService: ?[]const u8 = null,
        contact: ?Contact = null,
        license: ?License = null,
    };
    
    pub fn generate(router: *OpenAPIRouter, info: Info) !OpenAPIDocument {
        var paths = std.StringHashMap(PathItem).init(router.allocator);
        
        // Group routes by path
        var path_groups = std.StringHashMap(std.ArrayList(RouteEntry)).init(router.allocator);
        defer {
            var it = path_groups.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            path_groups.deinit();
        }
        
        // Process each route
        for (router.route_metadata.items) |route| {
            const normalized_path = normalizePathForOpenAPI(route.pattern);
            
            const result = try path_groups.getOrPut(normalized_path);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(RouteEntry).init(router.allocator);
            }
            
            try result.value_ptr.append(route);
        }
        
        // Convert to OpenAPI paths
        var path_it = path_groups.iterator();
        while (path_it.next()) |entry| {
            const path_item = try createPathItem(entry.value_ptr.items);
            try paths.put(entry.key_ptr.*, path_item);
        }
        
        return .{
            .info = info,
            .paths = paths,
        };
    }
    
    /// Convert path parameters from :param to {param}
    fn normalizePathForOpenAPI(pattern: []const u8) []const u8 {
        // Implementation to convert /users/:id to /users/{id}
        // This would use allocator to create new string
    }
    
    /// Generate JSON representation
    pub fn toJson(doc: OpenAPIDocument, allocator: std.mem.Allocator) ![]const u8 {
        // Use std.json to serialize the document
        return std.json.stringify(doc, .{}, allocator);
    }
    
    /// Generate YAML representation
    pub fn toYaml(doc: OpenAPIDocument, allocator: std.mem.Allocator) ![]const u8 {
        // Implementation for YAML generation
        // Could use a simple YAML writer or external library
    }
};
```

### 5. Integration with H3App

```zig
// Extension to H3App
pub const H3AppWithOpenAPI = struct {
    base_app: H3App,
    openapi_router: OpenAPIRouter,
    openapi_info: OpenAPIGenerator.Info,
    
    /// Generate OpenAPI document
    pub fn generateOpenAPI(self: *H3AppWithOpenAPI) !OpenAPIGenerator.OpenAPIDocument {
        return OpenAPIGenerator.generate(&self.openapi_router, self.openapi_info);
    }
    
    /// Add endpoint to serve OpenAPI spec
    pub fn enableOpenAPIEndpoint(self: *H3AppWithOpenAPI, path: []const u8) !void {
        const handler = struct {
            fn serveOpenAPI(event: *H3Event) !void {
                const app = @fieldParentPtr(H3AppWithOpenAPI, "base_app", event.context.get("app").?);
                const doc = try app.generateOpenAPI();
                const json = try OpenAPIGenerator.toJson(doc, event.allocator);
                
                try event.setHeader("Content-Type", "application/json");
                try event.send(json);
            }
        }.serveOpenAPI;
        
        try self.base_app.get(path, handler);
    }
};
```

## Usage Examples

### Basic Usage

```zig
const std = @import("std");
const h3 = @import("h3");

// Define request/response types
const CreateUserRequest = struct {
    name: []const u8,
    email: []const u8,
    age: ?u32 = null,
};

const UserResponse = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    age: ?u32,
    created_at: []const u8,
};

pub fn main() !void {
    var app = try h3.createAppWithOpenAPI(allocator, .{
        .title = "User API",
        .version = "1.0.0",
        .description = "A simple user management API",
    });
    defer app.deinit();
    
    // Add typed route
    const createUserHandler = h3.typedHandler(
        CreateUserRequest,
        UserResponse,
        createUser,
        .{
            .summary = "Create a new user",
            .description = "Creates a new user in the system",
            .tags = &.{"users"},
            .responses = &.{
                .{
                    .status = 201,
                    .description = "User created successfully",
                },
                .{
                    .status = 400,
                    .description = "Invalid request data",
                },
            },
        },
    );
    
    try app.post("/users", createUserHandler);
    
    // Enable OpenAPI endpoint
    try app.enableOpenAPIEndpoint("/openapi.json");
    
    // Regular handlers still work
    try app.get("/health", healthHandler);
    
    try h3.serve(&app, .{ .port = 3000 });
}

fn createUser(event: *h3.Event, req: CreateUserRequest) !UserResponse {
    // Implementation
    return UserResponse{
        .id = 123,
        .name = req.name,
        .email = req.email,
        .age = req.age,
        .created_at = "2024-01-20T10:00:00Z",
    };
}

fn healthHandler(event: *h3.Event) !void {
    try h3.send(event, "OK");
}
```

### Advanced Usage with Validation

```zig
// Custom schema with validation
const EmailString = struct {
    value: []const u8,
    
    pub fn schema() h3.Schema {
        return .{
            .type = .string,
            .format = "email",
            .pattern = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$",
        };
    }
};

// Use in request type
const SignupRequest = struct {
    username: []const u8,
    email: EmailString,
    password: []const u8,
    terms_accepted: bool,
};
```

## Implementation Phases

### Phase 1: Core Schema System
- Implement `Schema` type and `schemaFromType` function
- Add basic type mapping for primitive types
- Create tests for schema generation

### Phase 2: Enhanced Routing
- Create `TypedHandler` wrapper
- Implement `OpenAPIRouter` with metadata storage
- Maintain backward compatibility

### Phase 3: OpenAPI Generation
- Implement `OpenAPIGenerator`
- Add JSON serialization
- Create path normalization utilities

### Phase 4: Integration
- Extend `H3App` with OpenAPI support
- Add OpenAPI endpoint serving
- Create comprehensive examples

### Phase 5: Advanced Features
- Add YAML output support
- Implement schema validation
- Add support for external schema references
- Create schema customization attributes

## Benefits

1. **Type Safety**: Schemas are generated from actual Zig types
2. **Zero Runtime Cost**: All schema generation happens at compile time
3. **Backward Compatible**: Existing handlers continue to work
4. **Self-Documenting**: API documentation is always in sync with code
5. **Developer Experience**: Auto-completion and type checking for API contracts

## Future Enhancements

1. **Swagger UI Integration**: Serve interactive API documentation
2. **Client Generation**: Generate type-safe clients from OpenAPI spec
3. **Validation Middleware**: Automatic request/response validation
4. **Schema Versioning**: Support for API versioning
5. **External Schema Support**: Import/export OpenAPI schemas