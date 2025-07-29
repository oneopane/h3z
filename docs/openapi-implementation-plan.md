# H3 OpenAPI Implementation Plan

## Phase 1: Core Schema System (Week 1)

### 1.1 Basic Schema Types
Create `src/openapi/schema.zig`:

```zig
const std = @import("std");

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
    items: ?*const Schema = null,
    properties: ?std.StringHashMap(*const Schema) = null,
    example: ?[]const u8 = null,
    format: ?[]const u8 = null,
    minimum: ?f64 = null,
    maximum: ?f64 = null,
    pattern: ?[]const u8 = null,
    enum_values: ?[]const []const u8 = null,
    
    /// Check if schema represents a primitive type
    pub fn isPrimitive(self: Schema) bool {
        return switch (self.type) {
            .string, .number, .integer, .boolean, .null => true,
            else => false,
        };
    }
};
```

### 1.2 Type-to-Schema Conversion
Add to `src/openapi/schema.zig`:

```zig
/// Convert Zig type to OpenAPI schema at compile time
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
            if (ptr.child == u8) {
                switch (ptr.size) {
                    .Slice => break :blk .{ .type = .string },
                    .One => break :blk .{ .type = .string, .format = "byte" },
                    else => break :blk .{ .type = .string },
                }
            }
            break :blk schemaFromType(ptr.child);
        },
        .Array => |arr| .{
            .type = .array,
            .items = &schemaFromType(arr.child),
        },
        .Struct => |s| blk: {
            // Note: In real implementation, we'd need a comptime solution for properties
            break :blk .{
                .type = .object,
                // Properties would be generated at comptime
            };
        },
        .Optional => |opt| blk: {
            var schema = schemaFromType(opt.child);
            schema.required = false;
            break :blk schema;
        },
        .Enum => |e| blk: {
            _ = e;
            break :blk .{
                .type = .string,
                // enum_values would be populated from enum fields
            };
        },
        else => .{ .type = .string }, // Fallback
    };
}

/// Helper for creating schemas with custom attributes
pub fn schema(comptime T: type, attrs: Schema) Schema {
    var base = schemaFromType(T);
    // Merge attributes
    if (attrs.description) |desc| base.description = desc;
    if (attrs.example) |ex| base.example = ex;
    if (attrs.pattern) |pat| base.pattern = pat;
    // ... merge other fields
    return base;
}
```

### 1.3 Tests for Schema Generation
Create `src/openapi/schema_test.zig`:

```zig
const std = @import("std");
const testing = std.testing;
const schema = @import("schema.zig");

test "primitive type schemas" {
    const bool_schema = schema.schemaFromType(bool);
    try testing.expectEqual(schema.SchemaType.boolean, bool_schema.type);
    
    const int_schema = schema.schemaFromType(i32);
    try testing.expectEqual(schema.SchemaType.integer, int_schema.type);
    try testing.expectEqualStrings("int32", int_schema.format.?);
    
    const string_schema = schema.schemaFromType([]const u8);
    try testing.expectEqual(schema.SchemaType.string, string_schema.type);
}

test "array schemas" {
    const IntArray = []const i32;
    const array_schema = schema.schemaFromType(IntArray);
    try testing.expectEqual(schema.SchemaType.array, array_schema.type);
    try testing.expect(array_schema.items != null);
    try testing.expectEqual(schema.SchemaType.integer, array_schema.items.?.type);
}

test "optional schemas" {
    const maybe_string = schema.schemaFromType(?[]const u8);
    try testing.expectEqual(schema.SchemaType.string, maybe_string.type);
    try testing.expect(!maybe_string.required);
}
```

## Phase 2: Enhanced Routing (Week 2)

### 2.1 Route Metadata Types
Create `src/openapi/metadata.zig`:

```zig
const std = @import("std");
const Schema = @import("schema.zig").Schema;

pub const RouteMetadata = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    operation_id: ?[]const u8 = null,
    deprecated: bool = false,
    request_body: ?RequestBodyMetadata = null,
    responses: []const ResponseMetadata = &.{},
    parameters: []const ParameterMetadata = &.{},
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
};

pub const MediaType = struct {
    media_type: []const u8,
    schema: Schema,
    example: ?[]const u8 = null,
};

pub const ParameterMetadata = struct {
    name: []const u8,
    in: ParameterLocation,
    description: ?[]const u8 = null,
    required: bool = false,
    schema: Schema,
    example: ?[]const u8 = null,
};

pub const ParameterLocation = enum {
    path,
    query,
    header,
    cookie,
};
```

### 2.2 Typed Handler Implementation
Create `src/openapi/handler.zig`:

```zig
const std = @import("std");
const H3Event = @import("../core/event.zig").H3Event;
const BodyParser = @import("../utils/body.zig").BodyParser;
const json_utils = @import("../utils/json.zig");
const RouteMetadata = @import("metadata.zig").RouteMetadata;
const Schema = @import("schema.zig").Schema;
const schemaFromType = @import("schema.zig").schemaFromType;

/// Type-safe handler wrapper
pub fn TypedHandler(comptime RequestType: type, comptime ResponseType: type) type {
    return struct {
        pub const Request = RequestType;
        pub const Response = ResponseType;
        pub const request_schema = schemaFromType(RequestType);
        pub const response_schema = schemaFromType(ResponseType);
        
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

/// Create a typed handler with automatic marshaling
pub fn typedHandler(
    comptime RequestType: type,
    comptime ResponseType: type,
    comptime handler_fn: fn (*H3Event, RequestType) anyerror!ResponseType,
    metadata: RouteMetadata,
) TypedHandler(RequestType, ResponseType) {
    const wrapper = struct {
        fn handle(event: *H3Event) anyerror!void {
            // Parse request body
            const req_data = if (RequestType == void) 
                {} 
            else 
                try BodyParser.parseJson(event, RequestType);
            
            // Call actual handler
            const resp_data = try handler_fn(event, req_data);
            
            // Send response
            if (ResponseType != void) {
                try json_utils.sendJson(event, resp_data);
            }
        }
    }.handle;
    
    return TypedHandler(RequestType, ResponseType).init(wrapper, metadata);
}

/// Handler for routes with only path/query parameters
pub fn paramHandler(
    comptime ResponseType: type,
    comptime handler_fn: fn (*H3Event) anyerror!ResponseType,
    metadata: RouteMetadata,
) TypedHandler(void, ResponseType) {
    const wrapper = struct {
        fn handle(event: *H3Event) anyerror!void {
            const resp_data = try handler_fn(event);
            if (ResponseType != void) {
                try json_utils.sendJson(event, resp_data);
            }
        }
    }.handle;
    
    return TypedHandler(void, ResponseType).init(wrapper, metadata);
}
```

### 2.3 OpenAPI-Aware Router
Create `src/openapi/router.zig`:

```zig
const std = @import("std");
const HttpMethod = @import("../http/method.zig").HttpMethod;
const Router = @import("../core/router.zig").Router;
const Handler = @import("../core/router.zig").Handler;
const RouteMetadata = @import("metadata.zig").RouteMetadata;
const Schema = @import("schema.zig").Schema;

pub const RouteInfo = struct {
    method: HttpMethod,
    pattern: []const u8,
    metadata: RouteMetadata,
    request_schema: ?Schema,
    response_schema: ?Schema,
};

pub const OpenAPIRouter = struct {
    base_router: Router,
    route_info: std.ArrayList(RouteInfo),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !OpenAPIRouter {
        return .{
            .base_router = try Router.init(allocator),
            .route_info = std.ArrayList(RouteInfo).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *OpenAPIRouter) void {
        self.base_router.deinit();
        self.route_info.deinit();
    }
    
    /// Add a typed route with metadata
    pub fn addTypedRoute(
        self: *OpenAPIRouter,
        method: HttpMethod,
        pattern: []const u8,
        comptime typed_handler: anytype,
    ) !void {
        const HandlerType = @TypeOf(typed_handler);
        
        // Add to base router
        try self.base_router.addRoute(method, pattern, typed_handler.handler);
        
        // Store route info
        try self.route_info.append(.{
            .method = method,
            .pattern = try self.allocator.dupe(u8, pattern),
            .metadata = typed_handler.metadata,
            .request_schema = if (@hasDecl(HandlerType, "request_schema")) 
                HandlerType.request_schema 
            else 
                null,
            .response_schema = if (@hasDecl(HandlerType, "response_schema")) 
                HandlerType.response_schema 
            else 
                null,
        });
    }
    
    /// Add regular route (backward compatibility)
    pub fn addRoute(
        self: *OpenAPIRouter,
        method: HttpMethod,
        pattern: []const u8,
        handler: Handler,
    ) !void {
        try self.base_router.addRoute(method, pattern, handler);
    }
    
    /// Get all route information
    pub fn getRouteInfo(self: *const OpenAPIRouter) []const RouteInfo {
        return self.route_info.items;
    }
};
```

## Phase 3: OpenAPI Document Generation (Week 3)

### 3.1 OpenAPI Types
Create `src/openapi/spec.zig`:

```zig
const std = @import("std");
const Schema = @import("schema.zig").Schema;

pub const OpenAPISpec = struct {
    openapi: []const u8 = "3.1.0",
    info: Info,
    servers: []const Server = &.{},
    paths: Paths,
    components: ?Components = null,
    tags: []const Tag = &.{},
};

pub const Info = struct {
    title: []const u8,
    version: []const u8,
    description: ?[]const u8 = null,
    termsOfService: ?[]const u8 = null,
    contact: ?Contact = null,
    license: ?License = null,
};

pub const Contact = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    email: ?[]const u8 = null,
};

pub const License = struct {
    name: []const u8,
    url: ?[]const u8 = null,
};

pub const Server = struct {
    url: []const u8,
    description: ?[]const u8 = null,
    variables: ?std.StringHashMap(ServerVariable) = null,
};

pub const ServerVariable = struct {
    default: []const u8,
    description: ?[]const u8 = null,
    enum_values: ?[]const []const u8 = null,
};

pub const Paths = std.StringHashMap(PathItem);

pub const PathItem = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    get: ?Operation = null,
    put: ?Operation = null,
    post: ?Operation = null,
    delete: ?Operation = null,
    options: ?Operation = null,
    head: ?Operation = null,
    patch: ?Operation = null,
    trace: ?Operation = null,
    parameters: []const Parameter = &.{},
};

pub const Operation = struct {
    tags: []const []const u8 = &.{},
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    operationId: ?[]const u8 = null,
    parameters: []const Parameter = &.{},
    requestBody: ?RequestBody = null,
    responses: Responses,
    deprecated: bool = false,
};

pub const Parameter = struct {
    name: []const u8,
    in: []const u8, // "path", "query", "header", "cookie"
    description: ?[]const u8 = null,
    required: bool = false,
    deprecated: bool = false,
    schema: Schema,
    example: ?[]const u8 = null,
};

pub const RequestBody = struct {
    description: ?[]const u8 = null,
    content: std.StringHashMap(MediaType),
    required: bool = false,
};

pub const MediaType = struct {
    schema: Schema,
    example: ?[]const u8 = null,
    examples: ?std.StringHashMap(Example) = null,
};

pub const Example = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    value: []const u8,
};

pub const Responses = std.StringHashMap(Response);

pub const Response = struct {
    description: []const u8,
    headers: ?std.StringHashMap(Header) = null,
    content: ?std.StringHashMap(MediaType) = null,
};

pub const Header = struct {
    description: ?[]const u8 = null,
    required: bool = false,
    deprecated: bool = false,
    schema: Schema,
};

pub const Components = struct {
    schemas: ?std.StringHashMap(Schema) = null,
    responses: ?std.StringHashMap(Response) = null,
    parameters: ?std.StringHashMap(Parameter) = null,
    examples: ?std.StringHashMap(Example) = null,
    requestBodies: ?std.StringHashMap(RequestBody) = null,
    headers: ?std.StringHashMap(Header) = null,
};

pub const Tag = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocs = null,
};

pub const ExternalDocs = struct {
    description: ?[]const u8 = null,
    url: []const u8,
};
```

### 3.2 OpenAPI Generator
Create `src/openapi/generator.zig`:

```zig
const std = @import("std");
const OpenAPIRouter = @import("router.zig").OpenAPIRouter;
const spec = @import("spec.zig");
const HttpMethod = @import("../http/method.zig").HttpMethod;

pub const OpenAPIGenerator = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) OpenAPIGenerator {
        return .{ .allocator = allocator };
    }
    
    /// Generate OpenAPI spec from router
    pub fn generate(
        self: *OpenAPIGenerator,
        router: *const OpenAPIRouter,
        info: spec.Info,
        servers: []const spec.Server,
    ) !spec.OpenAPISpec {
        var paths = spec.Paths.init(self.allocator);
        
        // Group routes by path
        var path_groups = std.StringHashMap(std.ArrayList(RouteInfo)).init(self.allocator);
        defer {
            var it = path_groups.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            path_groups.deinit();
        }
        
        // Process each route
        for (router.getRouteInfo()) |route| {
            const openapi_path = try self.convertPath(route.pattern);
            
            const result = try path_groups.getOrPut(openapi_path);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(RouteInfo).init(self.allocator);
            }
            
            try result.value_ptr.append(route);
        }
        
        // Convert to OpenAPI paths
        var path_it = path_groups.iterator();
        while (path_it.next()) |entry| {
            const path_item = try self.createPathItem(entry.value_ptr.items);
            try paths.put(entry.key_ptr.*, path_item);
        }
        
        return spec.OpenAPISpec{
            .info = info,
            .servers = servers,
            .paths = paths,
        };
    }
    
    /// Convert :param to {param} format
    fn convertPath(self: *OpenAPIGenerator, pattern: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        var i: usize = 0;
        
        while (i < pattern.len) : (i += 1) {
            if (pattern[i] == ':') {
                // Found parameter
                try result.append('{');
                i += 1;
                
                // Copy parameter name
                while (i < pattern.len and pattern[i] != '/') : (i += 1) {
                    try result.append(pattern[i]);
                }
                
                try result.append('}');
                i -= 1; // Back up one since loop will increment
            } else {
                try result.append(pattern[i]);
            }
        }
        
        return result.toOwnedSlice();
    }
    
    fn createPathItem(self: *OpenAPIGenerator, routes: []const RouteInfo) !spec.PathItem {
        var path_item = spec.PathItem{};
        
        for (routes) |route| {
            const operation = try self.createOperation(route);
            
            switch (route.method) {
                .GET => path_item.get = operation,
                .POST => path_item.post = operation,
                .PUT => path_item.put = operation,
                .DELETE => path_item.delete = operation,
                .PATCH => path_item.patch = operation,
                .HEAD => path_item.head = operation,
                .OPTIONS => path_item.options = operation,
                else => {},
            }
        }
        
        return path_item;
    }
    
    fn createOperation(self: *OpenAPIGenerator, route: RouteInfo) !spec.Operation {
        var responses = spec.Responses.init(self.allocator);
        
        // Add responses from metadata
        for (route.metadata.responses) |resp_meta| {
            const status_str = try std.fmt.allocPrint(self.allocator, "{d}", .{resp_meta.status});
            
            var content: ?std.StringHashMap(spec.MediaType) = null;
            if (resp_meta.content) |media_types| {
                content = std.StringHashMap(spec.MediaType).init(self.allocator);
                for (media_types) |mt| {
                    try content.?.put(mt.media_type, .{
                        .schema = mt.schema,
                        .example = mt.example,
                    });
                }
            }
            
            try responses.put(status_str, .{
                .description = resp_meta.description,
                .content = content,
            });
        }
        
        // Add default response if none specified
        if (responses.count() == 0 and route.response_schema != null) {
            var content = std.StringHashMap(spec.MediaType).init(self.allocator);
            try content.put("application/json", .{
                .schema = route.response_schema.?,
            });
            
            try responses.put("200", .{
                .description = "Success",
                .content = content,
            });
        }
        
        // Create request body if needed
        var request_body: ?spec.RequestBody = null;
        if (route.request_schema) |schema| {
            var content = std.StringHashMap(spec.MediaType).init(self.allocator);
            try content.put("application/json", .{
                .schema = schema,
            });
            
            request_body = .{
                .content = content,
                .required = true,
            };
        }
        
        return spec.Operation{
            .tags = route.metadata.tags,
            .summary = route.metadata.summary,
            .description = route.metadata.description,
            .operationId = route.metadata.operation_id,
            .parameters = try self.extractParameters(route),
            .requestBody = request_body,
            .responses = responses,
            .deprecated = route.metadata.deprecated,
        };
    }
    
    fn extractParameters(self: *OpenAPIGenerator, route: RouteInfo) ![]const spec.Parameter {
        var params = std.ArrayList(spec.Parameter).init(self.allocator);
        
        // Extract path parameters
        var iter = std.mem.tokenize(u8, route.pattern, "/");
        while (iter.next()) |segment| {
            if (segment.len > 0 and segment[0] == ':') {
                const param_name = segment[1..];
                try params.append(.{
                    .name = param_name,
                    .in = "path",
                    .required = true,
                    .schema = .{ .type = .string },
                });
            }
        }
        
        // Add parameters from metadata
        for (route.metadata.parameters) |param| {
            try params.append(.{
                .name = param.name,
                .in = switch (param.in) {
                    .path => "path",
                    .query => "query",
                    .header => "header",
                    .cookie => "cookie",
                },
                .description = param.description,
                .required = param.required,
                .schema = param.schema,
                .example = param.example,
            });
        }
        
        return params.toOwnedSlice();
    }
    
    /// Serialize to JSON
    pub fn toJson(self: *OpenAPIGenerator, openapi_spec: spec.OpenAPISpec) ![]const u8 {
        return std.json.stringifyAlloc(self.allocator, openapi_spec, .{});
    }
};
```

## Phase 4: H3 Integration (Week 4)

### 4.1 Extended H3App
Create `src/openapi/app_extension.zig`:

```zig
const std = @import("std");
const H3App = @import("../core/app.zig").H3App;
const H3Event = @import("../core/event.zig").H3Event;
const OpenAPIRouter = @import("router.zig").OpenAPIRouter;
const OpenAPIGenerator = @import("generator.zig").OpenAPIGenerator;
const spec = @import("spec.zig");

pub const H3AppWithOpenAPI = struct {
    base_app: H3App,
    openapi_router: OpenAPIRouter,
    openapi_info: spec.Info,
    openapi_servers: []const spec.Server,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, info: spec.Info) !H3AppWithOpenAPI {
        return .{
            .base_app = try H3App.init(allocator),
            .openapi_router = try OpenAPIRouter.init(allocator),
            .openapi_info = info,
            .openapi_servers = &.{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *H3AppWithOpenAPI) void {
        self.base_app.deinit();
        self.openapi_router.deinit();
    }
    
    /// Set servers for OpenAPI spec
    pub fn setServers(self: *H3AppWithOpenAPI, servers: []const spec.Server) void {
        self.openapi_servers = servers;
    }
    
    /// Add typed GET route
    pub fn get(self: *H3AppWithOpenAPI, pattern: []const u8, comptime handler: anytype) !void {
        try self.openapi_router.addTypedRoute(.GET, pattern, handler);
        try self.base_app.router.addRoute(.GET, pattern, handler.handler);
    }
    
    /// Add typed POST route
    pub fn post(self: *H3AppWithOpenAPI, pattern: []const u8, comptime handler: anytype) !void {
        try self.openapi_router.addTypedRoute(.POST, pattern, handler);
        try self.base_app.router.addRoute(.POST, pattern, handler.handler);
    }
    
    // Similar methods for PUT, DELETE, PATCH, etc.
    
    /// Generate OpenAPI specification
    pub fn generateOpenAPI(self: *H3AppWithOpenAPI) !spec.OpenAPISpec {
        var generator = OpenAPIGenerator.init(self.allocator);
        return generator.generate(&self.openapi_router, self.openapi_info, self.openapi_servers);
    }
    
    /// Enable OpenAPI endpoint
    pub fn enableOpenAPIEndpoint(self: *H3AppWithOpenAPI, path: []const u8) !void {
        const Self = @This();
        
        const handler = struct {
            fn serveOpenAPI(event: *H3Event) !void {
                // Get app reference (would need proper context passing)
                const app_ptr = @intToPtr(*Self, @ptrToInt(event.context.get("_app").?));
                
                const openapi_spec = try app_ptr.generateOpenAPI();
                var generator = OpenAPIGenerator.init(event.allocator);
                const json_str = try generator.toJson(openapi_spec);
                
                try event.response.setHeader("Content-Type", "application/json");
                try event.response.write(json_str);
            }
        }.serveOpenAPI;
        
        try self.base_app.router.addRoute(.GET, path, handler);
    }
    
    /// Enable Swagger UI (optional)
    pub fn enableSwaggerUI(self: *H3AppWithOpenAPI, ui_path: []const u8, spec_path: []const u8) !void {
        _ = self;
        _ = ui_path;
        _ = spec_path;
        // Implementation would serve Swagger UI HTML
    }
};
```

### 4.2 Helper Functions
Create `src/openapi/helpers.zig`:

```zig
const std = @import("std");
const typedHandler = @import("handler.zig").typedHandler;
const paramHandler = @import("handler.zig").paramHandler;
const RouteMetadata = @import("metadata.zig").RouteMetadata;
const ResponseMetadata = @import("metadata.zig").ResponseMetadata;

/// Quick helper for creating common response metadata
pub fn responses(statuses: anytype) []const ResponseMetadata {
    const fields = @typeInfo(@TypeOf(statuses)).Struct.fields;
    var result: [fields.len]ResponseMetadata = undefined;
    
    inline for (fields, 0..) |field, i| {
        result[i] = .{
            .status = @field(statuses, field.name).status,
            .description = @field(statuses, field.name).description,
        };
    }
    
    return &result;
}

/// Helper for creating route metadata
pub fn route(attrs: struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    responses: []const ResponseMetadata = &.{},
}) RouteMetadata {
    return .{
        .summary = attrs.summary,
        .description = attrs.description,
        .tags = attrs.tags,
        .responses = attrs.responses,
    };
}

/// Create JSON handler with automatic schema
pub fn jsonHandler(
    comptime Request: type,
    comptime Response: type,
    comptime handler_fn: fn (*H3Event, Request) anyerror!Response,
    summary: []const u8,
) @TypeOf(typedHandler(Request, Response, handler_fn, route(.{ .summary = summary }))) {
    return typedHandler(Request, Response, handler_fn, route(.{
        .summary = summary,
        .responses = &.{
            .{ .status = 200, .description = "Success" },
            .{ .status = 400, .description = "Bad Request" },
            .{ .status = 500, .description = "Internal Server Error" },
        },
    }));
}
```

## Complete Example Application

```zig
const std = @import("std");
const h3 = @import("h3");
const openapi = h3.openapi;

// Request/Response types
const CreateUserRequest = struct {
    name: []const u8,
    email: []const u8,
    age: ?u32 = null,
};

const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    age: ?u32,
    created_at: []const u8,
};

const ErrorResponse = struct {
    error: []const u8,
    message: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create app with OpenAPI support
    var app = try openapi.H3AppWithOpenAPI.init(allocator, .{
        .title = "User Management API",
        .version = "1.0.0",
        .description = "A simple user management API with OpenAPI documentation",
    });
    defer app.deinit();
    
    // Set servers
    app.setServers(&.{
        .{ .url = "http://localhost:3000", .description = "Development server" },
        .{ .url = "https://api.example.com", .description = "Production server" },
    });
    
    // Define handlers with OpenAPI metadata
    const createUserHandler = openapi.typedHandler(
        CreateUserRequest,
        User,
        createUser,
        .{
            .summary = "Create a new user",
            .description = "Creates a new user in the system with the provided information",
            .tags = &.{"users"},
            .responses = &.{
                .{ .status = 201, .description = "User created successfully" },
                .{ .status = 400, .description = "Invalid request data" },
                .{ .status = 409, .description = "User with email already exists" },
            },
        },
    );
    
    const getUserHandler = openapi.paramHandler(
        User,
        getUser,
        .{
            .summary = "Get user by ID",
            .description = "Retrieves a user by their unique identifier",
            .tags = &.{"users"},
            .parameters = &.{
                .{
                    .name = "id",
                    .in = .path,
                    .description = "User ID",
                    .required = true,
                    .schema = .{ .type = .integer },
                },
            },
            .responses = &.{
                .{ .status = 200, .description = "User found" },
                .{ .status = 404, .description = "User not found" },
            },
        },
    );
    
    const listUsersHandler = openapi.paramHandler(
        []const User,
        listUsers,
        .{
            .summary = "List all users",
            .description = "Retrieves a paginated list of all users",
            .tags = &.{"users"},
            .parameters = &.{
                .{
                    .name = "page",
                    .in = .query,
                    .description = "Page number",
                    .schema = .{ .type = .integer, .minimum = 1 },
                },
                .{
                    .name = "limit",
                    .in = .query,
                    .description = "Items per page",
                    .schema = .{ .type = .integer, .minimum = 1, .maximum = 100 },
                },
            },
            .responses = &.{
                .{ .status = 200, .description = "List of users" },
            },
        },
    );
    
    // Register routes
    try app.post("/users", createUserHandler);
    try app.get("/users/:id", getUserHandler);
    try app.get("/users", listUsersHandler);
    
    // Enable OpenAPI endpoint
    try app.enableOpenAPIEndpoint("/openapi.json");
    
    // Optional: Enable Swagger UI
    try app.enableSwaggerUI("/docs", "/openapi.json");
    
    std.log.info("🚀 Server running at http://localhost:3000", .{});
    std.log.info("📚 API docs available at http://localhost:3000/docs", .{});
    std.log.info("📄 OpenAPI spec at http://localhost:3000/openapi.json", .{});
    
    // Start server
    try h3.serve(&app.base_app, .{ .port = 3000 });
}

// Handler implementations
fn createUser(event: *h3.Event, req: CreateUserRequest) !User {
    _ = event;
    // In real app: validate, save to database, etc.
    return User{
        .id = 123,
        .name = req.name,
        .email = req.email,
        .age = req.age,
        .created_at = "2024-01-20T10:00:00Z",
    };
}

fn getUser(event: *h3.Event) !User {
    const id = h3.getParam(event, "id") orelse return error.MissingParameter;
    const user_id = std.fmt.parseInt(u32, id, 10) catch return error.InvalidParameter;
    
    // In real app: fetch from database
    return User{
        .id = user_id,
        .name = "John Doe",
        .email = "john@example.com",
        .age = 30,
        .created_at = "2024-01-20T10:00:00Z",
    };
}

fn listUsers(event: *h3.Event) ![]const User {
    _ = event;
    // In real app: fetch from database with pagination
    const users = [_]User{
        .{
            .id = 1,
            .name = "John Doe",
            .email = "john@example.com",
            .age = 30,
            .created_at = "2024-01-20T10:00:00Z",
        },
        .{
            .id = 2,
            .name = "Jane Smith",
            .email = "jane@example.com",
            .age = 25,
            .created_at = "2024-01-20T11:00:00Z",
        },
    };
    
    return &users;
}
```

## Testing Strategy

1. **Unit Tests**: Test schema generation, type conversion, path normalization
2. **Integration Tests**: Test complete OpenAPI generation with sample routes
3. **Validation Tests**: Validate generated specs against OpenAPI 3.1 schema
4. **Performance Tests**: Ensure no runtime overhead for regular handlers

## Migration Guide

For existing H3 applications:

1. Replace `H3App` with `H3AppWithOpenAPI`
2. Convert handlers to typed handlers where OpenAPI is desired
3. Add metadata to routes
4. Enable OpenAPI endpoint
5. Regular handlers continue to work without changes

## Timeline

- **Week 1**: Core schema system and tests
- **Week 2**: Enhanced routing and typed handlers
- **Week 3**: OpenAPI generation and serialization
- **Week 4**: H3 integration and examples
- **Week 5**: Testing, documentation, and refinement
- **Week 6**: Advanced features (Swagger UI, validation)

## Success Metrics

1. Zero runtime overhead for non-OpenAPI routes
2. 100% backward compatibility
3. Generated specs pass OpenAPI 3.1 validation
4. Type-safe API contracts with compile-time checking
5. Developer productivity improvement through auto-documentation