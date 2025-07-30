# Web Framework Refactor Plan

## Overview

This document outlines a proposed refactor of the framework to support **dependency injection** and **request extractors**, combining the best patterns from modern web frameworks while maintaining the performance-first philosophy. This refactor also includes renaming library-specific identifiers to more descriptive, functionality-based names.

The design integrates four key concepts:
1. **Service Dependency Injection** - Clean application service management
2. **Request Extractors** - Type-safe parameter extraction from HTTP requests
3. **Compile-time Handler Analysis** - Zero-cost abstractions using Zig's comptime features
4. **Descriptive Naming** - Replace library-specific names with functionality-based identifiers

---

## Current State vs Proposed State

### Current Handler Pattern
Currently, handlers receive a single `HttpContext` object (defined in `src/core/event.zig`) containing all request data and manually extract what they need:

- **Pros**: Simple, predictable, familiar to existing users
- **Cons**: Verbose, error-prone, requires manual parameter validation

### Proposed Handler Pattern
Handlers would declare their exact dependencies as function parameters, with automatic extraction and injection:

- **Pros**: Type-safe, declarative, self-documenting, eliminates boilerplate
- **Cons**: More complex implementation, different from current patterns

---

## Async Execution Model

### Event Loop Coordination with xev

The framework acts as an orchestrator that coordinates between HTTP request handling and the xev event loop execution model:

1. **Request Processing Pipeline**:
   - Framework receives HTTP request and creates HttpContext
   - Analyzes route configuration to determine required middleware and handler
   - Executes middleware chain, extracting/injecting dependencies for each middleware
   - If middleware succeeds, prepares handler execution with all resolved dependencies
   - Packages complete handler invocation and submits to xev event loop
   - Handles response when handler completes

2. **Handler Execution Pattern**:
   ```zig
   // Framework generates something like this internally:
   const handler_call = HandlerInvocation{
       .handler_fn = createUserHandler,
       .resolved_params = .{
           .user_data = parsed_user_data,        // From JSON body extraction
           .authenticated_user = current_user,    // From middleware context
           .database = service_container.get(Database), // From service injection
       }
   };
   
   // Submits to event loop for async execution
   try event_loop.submit(handler_call);
   ```

3. **Clean Separation of Concerns**:
   - **Handlers**: Pure business logic functions that receive typed parameters
   - **Framework**: Manages HTTP protocol, async coordination, parameter extraction/injection
   - **Event Loop**: Handles async execution, concurrency, and I/O operations

This model ensures handlers remain completely decoupled from HTTP and async execution details, making them highly testable and focused purely on business logic.

---

## Route Configuration API

### Complete User Story

Developers define HTTP endpoints by specifying the route pattern, handler function, middleware chain, and execution mode:

```zig
// Define endpoint with complete configuration
app.route("/api/users/:id", .{
    .method = .POST,
    .handler = createUserHandler,
    .middleware = &[_]type{ AuthMiddleware, ValidationMiddleware },
    .blocking = false, // Non-blocking execution in event loop
});

// Alternative syntax for simple cases
app.post("/api/users", createUserHandler);
app.get("/api/users/:id", getUserHandler, &[_]type{ AuthMiddleware });
```

### Execution Flow

1. **Route Registration**: Framework analyzes handler and middleware signatures at compile time
2. **Request Matching**: Incoming requests are matched against registered route patterns
3. **Parameter Extraction**: Path parameters, query strings, and route data are extracted
4. **Middleware Chain Execution**: Each middleware struct's `handle` method is called with its required parameters
5. **Context Modification**: Middleware can write values to request context for handler access
6. **Error Handling**: Middleware errors are converted to HTTP responses via `handleError` methods
7. **Handler Execution**: If middleware succeeds, handler is called with all resolved dependencies
8. **Response Generation**: Handler return values are automatically serialized or sent as configured

### Blocking vs Non-blocking

- **Non-blocking (default)**: Handler execution submitted to event loop, doesn't block request processing thread
- **Blocking**: Handler executed synchronously, suitable for CPU-intensive operations that need immediate results

---

## Core Design Principles

### 1. Compile-Time Analysis
Leverage Zig's `comptime` capabilities to analyze handler function signatures at build time, determining:
- What request data needs to be extracted
- What services need to be injected
- How to generate the appropriate wrapper code

### 2. Zero-Cost Abstractions
The extractor and injection system should have no runtime overhead compared to manual extraction. All analysis and code generation happens at compile time.

### 3. Progressive Adoption
The new system should coexist with existing `HttpContext`-based handlers, allowing gradual migration without breaking changes.

### 4. Type Safety
All parameter extraction and service injection should be validated at compile time, preventing common runtime errors.

### 5. Descriptive Naming
Use clear, functionality-based names that describe what components do rather than library-specific identifiers.

---

## Naming Refactor

### Current Library-Specific Names → Proposed Descriptive Names

| Current Name | Proposed Name | Rationale |
|--------------|---------------|-----------|
| `H3App` | `WebApp` | Describes functionality rather than library |
| `H3Event` | `HttpContext` | Clearly indicates HTTP request/response context |
| `H3Config` | `WebAppConfig` | Generic web application configuration |
| `RouterComponent` | `Router` | Components concept being simplified |
| Library prefix `h3.*` | Generic module names | Remove library branding from public API |

### Benefits of Renaming
- **Clarity**: Names immediately convey functionality and purpose
- **Maintainability**: Easier to understand code for new contributors
- **Flexibility**: Not tied to specific library branding
- **Professionalism**: Clean, descriptive API surface

---

## Service Dependency Injection

### Module-Based Service Registration

Applications define their services using a module pattern inspired by Tokamak but adapted for H3's architecture:

**Module Definition**: Services are declared as struct fields with optional configuration hooks for complex initialization, lifecycle management, and dependency relationships.

**Service Types**: Support multiple service patterns including auto-wired dependencies, constant values, factory functions, and custom initializers.

**Integration Point**: Services integrate with WebApp initialization (see `src/core/app.zig`), creating a service container that handlers can access through parameter injection. This would extend the existing `WebApp.initWithConfig()` pattern to include service container initialization.

### Service Lifecycles

**Application-Scoped Services**: Created once during application startup and shared across all requests. Examples include database connection pools, configuration objects, and logging services.

**Request-Scoped Services**: Created per request or request group, automatically cleaned up after response. Examples include database transactions, request-specific context, and user sessions.

**Pooled Services**: Leverage H3's existing object pooling system (see `src/core/event_pool.zig` and `src/core/memory_manager.zig`) for services that benefit from reuse but need per-request isolation.

### Memory Management Integration

Services integrate with the framework's sophisticated memory management system:
- **Automatic Cleanup**: Services with cleanup methods are automatically deinitialized
- **Pool Integration**: Services can leverage existing object pools for performance
- **Memory Monitoring**: Service allocation tracked through the framework's memory statistics system

---

## Middleware System

### Struct-Based Middleware Pattern

Middleware is implemented as structs with comptime-validated methods, providing type safety and zero-cost abstractions:

```zig
const AuthMiddleware = struct {
    // Required: middleware execution logic
    pub fn handle(
        authorization: ?[]const u8,           // Direct header value
        user_context: *ContextValue("user")   // Context modification
    ) AuthError!void {
        const token = authorization orelse return AuthError.MissingToken;
        const user = try validateToken(token);
        user_context.set(user); // Store for handler access
    }
    
    // Required: error to HTTP response conversion
    pub fn handleError(err: AuthError) HttpResponse {
        return switch (err) {
            .MissingToken => .{ .status = .unauthorized, .body = "Auth required" },
            .InvalidToken => .{ .status = .forbidden, .body = "Invalid token" },
            .ExpiredToken => .{ .status = .unauthorized, .body = "Token expired" },
        };
    }
};

const ValidationMiddleware = struct {
    pub fn handle(
        content_type: ?[]const u8,
        request_valid: *ContextValue("request_valid")
    ) ValidationError!void {
        if (content_type == null or !std.mem.startsWith(u8, content_type.?, "application/json")) {
            return ValidationError.InvalidContentType;
        }
        request_valid.set(true);
    }
    
    pub fn handleError(err: ValidationError) HttpResponse {
        return switch (err) {
            .InvalidContentType => .{ .status = .bad_request, .body = "JSON required" },
            .ValidationFailed => .{ .status = .bad_request, .body = "Invalid data" },
        };
    }
};
```

### Comptime Validation

The framework validates middleware structs at compile time, ensuring they implement the required interface:

```zig
fn validateMiddleware(comptime T: type) void {
    // Ensure required methods exist with correct signatures
    if (!@hasDecl(T, "handle")) @compileError("Middleware must have 'handle' method");
    if (!@hasDecl(T, "handleError")) @compileError("Middleware must have 'handleError' method");
    
    // Could add more sophisticated signature checking
    const handle_info = @typeInfo(@TypeOf(T.handle));
    const error_info = @typeInfo(@TypeOf(T.handleError));
    // ... validation logic
}
```

### Middleware Execution Flow

1. **Parameter Extraction**: Framework extracts required parameters for middleware `handle` method
2. **Execution**: Middleware `handle` method is called with extracted parameters
3. **Success Path**: If middleware succeeds, continue to next middleware or handler
4. **Error Path**: If middleware returns error, call `handleError` method and return HTTP response
5. **Context Passing**: Any context modifications are available to subsequent middleware and handlers

### Context Modification Pattern

Middleware can write typed values to the request context that handlers can then access:

```zig
// Middleware writes to context
pub fn handle(
    authorization: ?[]const u8,
    user_context: *ContextValue("user")
) AuthError!void {
    // ... authentication logic
    user_context.set(authenticated_user);
}

// Handler reads from context  
fn createUserHandler(
    user_data: User,                    // From request body
    authenticated_user: User,           // From middleware context
    db: *Database                       // From service injection
) !User {
    // Handler gets the user that middleware authenticated
    return try db.users.create(user_data);
}
```

---

## Request Extractor System

### Building on Existing Parsing Infrastructure

The framework already has solid JSON parsing functionality in `src/core/event.zig` and `src/utils/body.zig`:

```zig
// Current manual usage in handlers
const user_data = try event.readJson(User);
const form_data = try BodyParser.parseFormUrlencoded(event);
```

The extractor system would build on these existing functions rather than replace them, automating their usage through compile-time handler analysis.

### Extractor Types

The framework provides extractors that deliver direct values to handler and middleware parameters:

**Path Parameter Extraction**:
```zig
fn getUserHandler(
    user_id: u32,        // Path parameter :id parsed as integer
    format: ?[]const u8  // Optional path parameter :format
) !User { /* ... */ }
```

**Body Extraction** (leveraging existing parsing functions):
```zig
fn createUserHandler(
    user_data: User,           // JSON body parsed into User struct
    form_data: FormData,       // Form-urlencoded body as key-value map
    raw_body: ?[]const u8      // Raw request body bytes
) !void { /* ... */ }
```

**Query Parameter Extraction**:
```zig
fn searchHandler(
    query: []const u8,    // Required query parameter ?query=...
    page: u32 = 1,        // Optional query parameter with default
    limit: u32 = 10       // Optional query parameter with default
) !SearchResults { /* ... */ }
```

**Header Extraction**:
```zig
fn apiHandler(
    authorization: ?[]const u8,    // Authorization header value
    content_type: []const u8,      // Required Content-Type header
    user_agent: ?[]const u8        // Optional User-Agent header
) !void { /* ... */ }
```

**Request Metadata**:
```zig
fn logHandler(
    method: HttpMethod,      // HTTP method (GET, POST, etc.)
    path: []const u8,        // Request path
    remote_addr: []const u8  // Client IP address
) !void { /* ... */ }
```

### Type Safety and Validation

**Compile-Time Validation**: Extractor types are validated at compile time, ensuring handlers only declare valid parameter types.

**Runtime Parsing**: Request data is parsed and validated at runtime, with appropriate HTTP error responses for malformed requests.

**Error Handling**: Failed extraction results in standard HTTP error responses (400 Bad Request, 415 Unsupported Media Type, etc.) without reaching the handler, using the same error handling patterns already established in the existing parsing functions.

### Leveraging Existing Parsing Functions

The extractor implementations would be thin wrappers around existing proven functionality:

**Framework Implementation Details**:

The framework uses compile-time analysis to detect parameter types and generate appropriate extraction code:

```zig
// Framework detects User type parameter and generates:
fn extractUserFromJson(ctx: *HttpContext) !User {
    // Reuse existing parsing logic
    return try ctx.readJson(User);
}

// Framework detects FormData type parameter and generates:
fn extractFormData(ctx: *HttpContext) !FormData {
    // Reuse existing form parsing logic  
    return try BodyParser.parseFormUrlencoded(ctx);
}

// Framework detects u32 path parameter and generates:
fn extractPathParam(ctx: *HttpContext, param_name: []const u8) !u32 {
    const param_value = ctx.getParam(param_name) orelse return error.MissingParameter;
    return std.fmt.parseInt(u32, param_value, 10);
}
```

**Generated Handler Wrapper**:
```zig
// For: fn createUser(user_data: User, user_id: u32, db: *Database) !User
fn wrappedCreateUser(ctx: *HttpContext) !void {
    // Extract all parameters using appropriate extractors
    const user_data = try extractUserFromJson(ctx);
    const user_id = try extractPathParam(ctx, "id");
    const db = service_container.get(Database);
    
    // Call the actual handler with direct values
    const result = try createUser(user_data, user_id, db);
    try ctx.sendJsonValue(result);
}
```

This approach ensures that:
- **Existing parsing logic is preserved** and battle-tested
- **Error handling remains consistent** with current patterns
- **Performance characteristics are maintained** 
- **Migration is simpler** since the underlying behavior is identical

---

## Handler Analysis and Code Generation

### Compile-Time Route Analysis

Since routes are fixed at application startup, the framework can perform comprehensive compile-time analysis:

**Route-Specific Optimization**: Each route gets a custom-generated wrapper function optimized for its exact requirements:

```zig
// Route: POST /api/users/:id
// Handler: fn updateUser(user_id: u32, updates: UserUpdate, db: *Database) !User

// Framework generates optimized wrapper:
fn route_POST_api_users_id(ctx: *HttpContext) !void {
    // Only extract what this specific route needs
    const user_id = try std.fmt.parseInt(u32, ctx.getParam("id").?, 10);
    const updates = try ctx.readJson(UserUpdate);
    const db = service_container.get(Database);
    
    // Direct handler invocation
    const result = try updateUser(user_id, updates, db);
    try ctx.sendJsonValue(result);
}
```

### Handler Signature Analysis

The framework uses Zig's type introspection to analyze each parameter:

**Parameter Type Detection**:
```zig
fn analyzeHandler(comptime handler: anytype) HandlerInfo {
    const fn_info = @typeInfo(@TypeOf(handler));
    const params = fn_info.Fn.params;
    
    var handler_info = HandlerInfo{};
    
    for (params) |param| {
        const param_type = param.type.?;
        
        if (isServiceType(param_type)) {
            handler_info.services.append(.{ .type = param_type });
        } else if (isJsonBodyType(param_type)) {
            handler_info.json_body = param_type;
        } else if (isPathParamType(param_type)) {
            handler_info.path_params.append(.{ .type = param_type });
        }
        // ... other type classifications
    }
    
    return handler_info;
}
```

### Zero-Cost Code Generation

**Compile-Time Wrapper Generation**: Each route gets a specialized wrapper with no runtime overhead:

```zig
// Framework generates at comptime based on handler signature analysis
fn generateWrapper(comptime route: Route, comptime handler: anytype) fn(*HttpContext) !void {
    return struct {
        fn wrapper(ctx: *HttpContext) !void {
            // Generated extraction code specific to this handler's needs
            @call(.always_inline, handler, extractParameters(ctx, handler));
        }
    }.wrapper;
}
```

**Route-Specific Parameter Extraction**: Only extracts what each specific handler actually needs:
- **Path Parameters**: Only parse parameters that exist in the route pattern
- **Body Parsing**: Only parse request body if handler has body parameter
- **Service Injection**: Only resolve services that handler actually uses
- **Header Access**: Only extract headers that handler parameters request

This eliminates all unnecessary work and generates the most efficient possible code for each route.

---

## Integration with Existing H3 Architecture

### Component System Evolution

Rather than replace the existing component system, services represent a complementary layer:

**Framework Components**: Continue to handle the framework's internal systems (routing, memory management, event pooling). The existing `ComponentRegistry` in `src/core/component.zig` could be simplified to focus only on core framework infrastructure.

**Application Services**: New service system handles business logic dependencies and application-specific concerns.

**Clear Separation**: Framework components manage infrastructure, while services manage application logic dependencies. This avoids the current confusion about what constitutes a "component" by clearly separating framework internals from application dependencies.

### Router Integration

The routing system integrates seamlessly with the new handler pattern:

**Transparent Registration**: Route registration API remains unchanged from the user perspective. The existing `WebApp.get()`, `WebApp.post()`, etc. methods in `src/core/app.zig` would continue to work but gain the ability to analyze handler signatures.

**Automatic Wrapping**: Handlers are automatically analyzed and wrapped during route registration. This would extend the current `Router.addRoute()` functionality in `src/core/router.zig` to detect and wrap new-style handlers.

**Performance Optimization**: Generated wrapper code is optimized for the specific route's requirements, maintaining the framework's multi-tier routing performance (cache → trie → linear fallback).

### Memory Manager Compatibility

Services leverage the framework's existing memory management capabilities:

**Pool Integration**: Services can participate in object pooling where beneficial.

**Statistics Tracking**: Service allocation and lifecycle events are tracked in memory statistics.

**Resource Limits**: Services respect existing memory limits and allocation strategies.

---

## Response Handling Patterns

### Flexible Return Types

Handlers can return different types to control response behavior:

**Automatic Serialization**: Return structured data for automatic JSON serialization with appropriate content-type headers.

**Manual Response Control**: Return void to maintain current H3Event-based response handling.

**Explicit Response Objects**: Return response objects for fine-grained control over status codes, headers, and body content.

**Error Handling**: Return errors for automatic HTTP error response generation with appropriate status codes.

### Backward Compatibility

**Gradual Migration**: Existing HttpContext-based handlers continue to work unchanged during transition periods. The current handler signature `fn(ctx: *HttpContext) !void` would remain fully supported.

**Mixed Usage**: Applications can use both patterns simultaneously, allowing incremental adoption:

```zig
// Legacy style - still works
fn legacyHandler(ctx: *HttpContext) !void {
    const user_data = try ctx.readJson(User);
    // ... manual extraction
}

// New style - direct parameters
fn modernHandler(user_data: User, db: *Database) !User {
    return try db.users.create(user_data);
}

// Both can be registered together
app.post("/api/legacy", legacyHandler);
app.post("/api/modern", modernHandler);
```

**Performance Parity**: Both handler styles achieve equivalent performance characteristics, with the new style often being faster due to optimized extraction code generation.

---

## Performance Characteristics

### Zero-Cost Abstractions

**Compile-Time Resolution**: All handler analysis and wrapper generation occurs at build time.

**Optimized Generated Code**: Wrapper functions are tailored to each handler's specific requirements.

**No Runtime Overhead**: Parameter extraction performs equivalently to manual extraction code.

### Memory Efficiency

**Pool Integration**: Services and extractors leverage existing object pooling where beneficial.

**Minimal Allocations**: Request-scoped data uses efficient allocation patterns.

**Cleanup Automation**: Automatic resource cleanup prevents memory leaks.

---

## Migration Strategy

### Phase 1: Core Infrastructure
Implement the service container and basic extractor types, ensuring they integrate cleanly with existing H3 architecture.

### Phase 2: Handler Analysis
Add compile-time handler analysis and wrapper generation, initially supporting a subset of extractor types.

### Phase 3: Full Extractor Suite
Implement comprehensive extractor types covering all common HTTP request patterns.

### Phase 4: Response System
Add flexible response handling patterns and automatic serialization capabilities.

### Phase 5: Optimization
Optimize generated code, integrate with H3's pooling systems, and add performance monitoring.

---

## Benefits

### Developer Experience
- **Reduced Boilerplate**: Handlers focus on business logic rather than parameter extraction
- **Type Safety**: Compile-time validation prevents common runtime errors
- **Self-Documenting**: Handler signatures clearly indicate dependencies and requirements
- **IDE Support**: Better autocompletion and error checking in development environments

### Application Architecture
- **Clean Dependency Management**: Services are explicitly declared and automatically injected
- **Testability**: Handler dependencies are explicit, making unit testing straightforward
- **Modularity**: Clear separation between request handling and business logic
- **Scalability**: Service lifecycle management supports both simple and complex applications

### Performance
- **Zero Runtime Overhead**: Compile-time analysis eliminates abstraction costs
- **Optimized Extraction**: Generated code is tailored to specific handler requirements
- **Memory Efficiency**: Integration with H3's sophisticated memory management system
- **Reduced Allocations**: Object pooling and efficient parsing minimize memory pressure

---

## Conclusion

This design represents a natural evolution of H3's architecture, building on its existing strengths while addressing common web development patterns. By combining dependency injection with request extractors, H3 can provide a modern, type-safe development experience while maintaining its performance leadership.

The compile-time analysis approach ensures that these improvements come with zero runtime cost, staying true to H3's philosophy of sophisticated optimizations and explicit control over performance characteristics.

The modular design allows for gradual adoption, ensuring existing H3 applications can migrate incrementally while new applications can take full advantage of the enhanced developer experience from day one.