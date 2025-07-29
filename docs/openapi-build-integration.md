# OpenAPI Build System Integration

## Adding OpenAPI Module to build.zig

Add the following to your `build.zig` file after the H3 module definition:

```zig
// Create OpenAPI module
const openapi = b.addModule("h3_openapi", .{
    .root_source_file = b.path("src/openapi/openapi.zig"),
    .dependencies = &.{
        .{ .name = "h3", .module = h3 },
    },
});
```

## Module Structure

Create `src/openapi/openapi.zig` as the main export file:

```zig
//! H3 OpenAPI module - Type-safe OpenAPI schema generation for H3
//! 
//! This module provides:
//! - Automatic schema generation from Zig types
//! - Type-safe route handlers with metadata
//! - OpenAPI 3.1 specification generation
//! - Zero runtime overhead for regular routes

pub const Schema = @import("schema.zig").Schema;
pub const schemaFromType = @import("schema.zig").schemaFromType;
pub const schema = @import("schema.zig").schema;

pub const RouteMetadata = @import("metadata.zig").RouteMetadata;
pub const RequestBodyMetadata = @import("metadata.zig").RequestBodyMetadata;
pub const ResponseMetadata = @import("metadata.zig").ResponseMetadata;
pub const MediaType = @import("metadata.zig").MediaType;
pub const ParameterMetadata = @import("metadata.zig").ParameterMetadata;
pub const ParameterLocation = @import("metadata.zig").ParameterLocation;

pub const TypedHandler = @import("handler.zig").TypedHandler;
pub const typedHandler = @import("handler.zig").typedHandler;
pub const paramHandler = @import("handler.zig").paramHandler;

pub const OpenAPIRouter = @import("router.zig").OpenAPIRouter;
pub const RouteInfo = @import("router.zig").RouteInfo;

pub const spec = @import("spec.zig");
pub const OpenAPIGenerator = @import("generator.zig").OpenAPIGenerator;

pub const H3AppWithOpenAPI = @import("app_extension.zig").H3AppWithOpenAPI;

pub const helpers = @import("helpers.zig");
pub const responses = helpers.responses;
pub const route = helpers.route;
pub const jsonHandler = helpers.jsonHandler;

/// Create an H3 app with OpenAPI support
pub fn createAppWithOpenAPI(allocator: std.mem.Allocator, info: spec.Info) !H3AppWithOpenAPI {
    return H3AppWithOpenAPI.init(allocator, info);
}
```

## Testing Configuration

Add OpenAPI tests to your test suite in `build.zig`:

```zig
// OpenAPI tests
const openapi_tests = b.addTest(.{
    .root_source_file = b.path("src/openapi/tests.zig"),
    .target = target,
    .optimize = optimize,
});

openapi_tests.root_module.addImport("h3", h3);
openapi_tests.root_module.addImport("h3_openapi", openapi);

const run_openapi_tests = b.addRunArtifact(openapi_tests);
test_step.dependOn(&run_openapi_tests.step);
```

Create `src/openapi/tests.zig`:

```zig
const std = @import("std");
const testing = std.testing;

// Import all test files
test {
    _ = @import("schema_test.zig");
    _ = @import("handler_test.zig");
    _ = @import("router_test.zig");
    _ = @import("generator_test.zig");
}
```

## Example Programs

Add OpenAPI examples to the build system:

```zig
// OpenAPI example
const openapi_example = b.addExecutable(.{
    .name = "openapi_example",
    .root_source_file = b.path("examples/openapi_server.zig"),
    .target = target,
    .optimize = optimize,
});

openapi_example.root_module.addImport("h3", h3);
openapi_example.root_module.addImport("h3_openapi", openapi);

b.installArtifact(openapi_example);

const run_openapi_example = b.addRunArtifact(openapi_example);
run_openapi_example.step.dependOn(b.getInstallStep());

const run_openapi_step = b.step("run-openapi", "Run the OpenAPI example server");
run_openapi_step.dependOn(&run_openapi_example.step);
```

## Complete Build Configuration Example

Here's how the OpenAPI-related sections integrate into your existing `build.zig`:

```zig
pub fn build(b: *std.Build) void {
    // ... existing configuration ...

    // Create h3 module (existing)
    const h3 = b.addModule("h3", .{
        .root_source_file = b.path("src/root.zig"),
        .dependencies = &.{
            .{ .name = "libxev", .module = libxev_dep.module("libxev") },
        },
    });

    // Create OpenAPI module (new)
    const openapi = b.addModule("h3_openapi", .{
        .root_source_file = b.path("src/openapi/openapi.zig"),
        .dependencies = &.{
            .{ .name = "h3", .module = h3 },
        },
    });

    // ... existing build configurations ...

    // Add OpenAPI feature flag (optional)
    const enable_openapi = b.option(
        bool,
        "enable-openapi",
        "Enable OpenAPI schema generation support (default: true)",
    ) orelse true;

    if (enable_openapi) {
        // Add OpenAPI tests to test suite
        const openapi_test_step = b.step("test-openapi", "Run OpenAPI tests");
        
        const openapi_tests = b.addTest(.{
            .root_source_file = b.path("src/openapi/tests.zig"),
            .target = target,
            .optimize = optimize,
        });
        
        openapi_tests.root_module.addImport("h3", h3);
        openapi_tests.root_module.addImport("h3_openapi", openapi);
        
        const run_openapi_tests = b.addRunArtifact(openapi_tests);
        openapi_test_step.dependOn(&run_openapi_tests.step);
        test_step.dependOn(openapi_test_step);
    }

    // ... rest of build configuration ...
}
```

## Usage in Applications

Applications can now import both modules:

```zig
const std = @import("std");
const h3 = @import("h3");
const openapi = @import("h3_openapi");

pub fn main() !void {
    // Use OpenAPI-enhanced app
    var app = try openapi.createAppWithOpenAPI(allocator, .{
        .title = "My API",
        .version = "1.0.0",
    });
    
    // ... rest of application ...
}
```

## Conditional Compilation

For applications that want to conditionally enable OpenAPI:

```zig
const enable_openapi = @import("build_options").enable_openapi;

pub fn main() !void {
    if (enable_openapi) {
        // Use OpenAPI-enhanced version
        var app = try openapi.createAppWithOpenAPI(...);
    } else {
        // Use regular H3 app
        var app = try h3.createApp(...);
    }
}
```

## Performance Considerations

The OpenAPI module is designed with zero runtime overhead for regular routes:
- Schema generation happens at compile time
- Only routes registered with typed handlers incur metadata storage
- OpenAPI document generation only happens when explicitly requested
- Regular H3 handlers work exactly as before

## Next Steps

1. Implement the core schema system
2. Add comprehensive tests
3. Create example applications
4. Add benchmarks to verify zero overhead claim
5. Document migration path for existing applications