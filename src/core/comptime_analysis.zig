//! Compile-time function signature analysis for H3 Framework
//! Phase 1.1: Basic parameter type detection and service classification
//!
//! This module provides compile-time introspection of handler function signatures
//! to enable automatic parameter extraction and dependency injection.

const std = @import("std");
const H3Event = @import("event.zig").H3Event;

/// Parameter classification for different extraction strategies
pub const ParameterClassification = enum {
    path_param,     // Extracted from URL path parameters like :id
    query_param,    // Extracted from query string parameters
    header_param,   // Extracted from HTTP headers
    body_param,     // Extracted and parsed from request body (JSON)
    service,        // Injected service dependency (pointer types)
    unknown,        // Unable to classify
};

/// Information about a single function parameter
pub const ParameterInfo = struct {
    index: usize,
    type_name: []const u8,
    classification: ParameterClassification,
    is_optional: bool,
    is_pointer: bool,
    size_bytes: usize,
    
    /// Create parameter info from type analysis
    pub fn init(comptime index: usize, comptime T: type) ParameterInfo {
        const type_info = @typeInfo(T);
        
        return ParameterInfo{
            .index = index,
            .type_name = @typeName(T),
            .classification = classifyParameterType(T),
            .is_optional = type_info == .optional,
            .is_pointer = type_info == .pointer,
            .size_bytes = @sizeOf(T),
        };
    }
};

/// Complete analysis result for a handler function
pub const HandlerAnalysis = struct {
    param_count: usize,
    params: []const ParameterInfo,
    return_type_name: []const u8,
    return_is_error_union: bool,
    return_is_void: bool,
    has_services: bool,
    has_extractors: bool,
    is_valid: bool,
    error_message: ?[]const u8,
    
    /// Check if the handler has any service dependencies
    pub fn hasServiceDependencies(self: HandlerAnalysis) bool {
        return self.has_services;
    }
    
    /// Check if the handler requires parameter extraction
    pub fn requiresExtraction(self: HandlerAnalysis) bool {
        return self.has_extractors;
    }
    
    /// Get count of path parameters
    pub fn getPathParamCount(self: HandlerAnalysis) usize {
        var count: usize = 0;
        for (self.params) |param| {
            if (param.classification == .path_param) count += 1;
        }
        return count;
    }
    
    /// Get count of query parameters
    pub fn getQueryParamCount(self: HandlerAnalysis) usize {
        var count: usize = 0;
        for (self.params) |param| {
            if (param.classification == .query_param) count += 1;
        }
        return count;
    }
    
    /// Get count of service parameters
    pub fn getServiceCount(self: HandlerAnalysis) usize {
        var count: usize = 0;
        for (self.params) |param| {
            if (param.classification == .service) count += 1;
        }
        return count;
    }
    
    /// Get count of body parameters
    pub fn getBodyParamCount(self: HandlerAnalysis) usize {
        var count: usize = 0;
        for (self.params) |param| {
            if (param.classification == .body_param) count += 1;
        }
        return count;
    }
};

/// Core handler analyzer with compile-time introspection
pub const HandlerAnalyzer = struct {
    
    /// Analyze a handler function signature at compile time
    pub fn analyzeFunction(comptime handler: anytype) HandlerAnalysis {
        const handler_type = @TypeOf(handler);
        const type_info = @typeInfo(handler_type);
        
        // Validate that this is a function or function pointer
        const fn_info = switch (type_info) {
            .@"fn" => type_info.@"fn",
            .pointer => |ptr_info| blk: {
                const child_info = @typeInfo(ptr_info.child);
                if (child_info != .@"fn") {
                    return HandlerAnalysis{
                        .param_count = 0,
                        .params = &[_]ParameterInfo{},
                        .return_type_name = @typeName(void),
                        .return_is_error_union = false,
                        .return_is_void = true,
                        .has_services = false,
                        .has_extractors = false,
                        .is_valid = false,
                        .error_message = "Handler must be a function or function pointer",
                    };
                }
                break :blk child_info.@"fn";
            },
            else => {
                return HandlerAnalysis{
                    .param_count = 0,
                    .params = &[_]ParameterInfo{},
                    .return_type_name = @typeName(void),
                    .return_is_error_union = false,
                    .return_is_void = true,
                    .has_services = false,
                    .has_extractors = false,
                    .is_valid = false,
                    .error_message = "Handler must be a function or function pointer",
                };
            },
        };
        
        // Analyze parameters
        const param_count = fn_info.params.len;
        var param_infos: [fn_info.params.len]ParameterInfo = undefined;
        var has_services = false;
        var has_extractors = false;
        
        inline for (fn_info.params, 0..) |param, i| {
            if (param.type) |param_type| {
                const param_info = ParameterInfo.init(i, param_type);
                param_infos[i] = param_info;
                
                if (param_info.classification == .service) {
                    has_services = true;
                } else if (param_info.classification != .unknown) {
                    has_extractors = true;
                }
            } else {
                // Generic parameters - not supported yet
                return HandlerAnalysis{
                    .param_count = 0,
                    .params = &[_]ParameterInfo{},
                    .return_type_name = @typeName(void),
                    .return_is_error_union = false,
                    .return_is_void = true,
                    .has_services = false,
                    .has_extractors = false,
                    .is_valid = false,
                    .error_message = "Generic parameters not supported yet",
                };
            }
        }
        
        // Analyze return type
        const return_type = fn_info.return_type orelse void;
        const return_type_info = @typeInfo(return_type);
        const return_is_error_union = return_type_info == .error_union;
        const return_is_void = return_type == void or 
            (return_is_error_union and return_type_info.error_union.payload == void);
        
        // Create final parameter slice
        const params_slice = param_infos[0..param_count];
        
        return HandlerAnalysis{
            .param_count = param_count,
            .params = params_slice,
            .return_type_name = @typeName(return_type),
            .return_is_error_union = return_is_error_union,
            .return_is_void = return_is_void,
            .has_services = has_services,
            .has_extractors = has_extractors,
            .is_valid = true,
            .error_message = null,
        };
    }
    
    /// Validate that a handler signature is supported
    pub fn validateHandler(comptime handler: anytype) bool {
        const analysis = analyzeFunction(handler);
        return analysis.is_valid;
    }
    
    /// Get a human-readable signature description
    pub fn describeHandler(comptime handler: anytype) []const u8 {
        const analysis = analyzeFunction(handler);
        
        if (!analysis.is_valid) {
            return analysis.error_message orelse "Invalid handler";
        }
        
        // For now, return a simple description
        // In the future, we could generate a more detailed description
        return std.fmt.comptimePrint("Handler with {} parameters", .{analysis.param_count});
    }
};

/// Classify a parameter type to determine extraction strategy
pub fn classifyParameterType(comptime T: type) ParameterClassification {
    const type_info = @typeInfo(T);
    
    switch (type_info) {
        .pointer => |ptr_info| {
            // Single-item pointers are likely services to be injected
            if (ptr_info.size == .one) {
                // Check if it's a service-like type (struct, opaque, or custom type)
                const child_info = @typeInfo(ptr_info.child);
                switch (child_info) {
                    .@"struct", .@"opaque" => return .service,
                    // Arrays or slices might be string parameters
                    .array => return .query_param,
                    else => return .service, // Default to service for other pointer types
                }
            }
            // Multi-item pointers (slices) are likely string parameters
            else if (ptr_info.size == .slice) {
                return .query_param;
            }
            // Other pointer types
            return .unknown;
        },
        .optional => |opt_info| {
            // Recursively classify the underlying type
            const underlying_classification = classifyParameterType(opt_info.child);
            return underlying_classification;
        },
        .int => {
            // Integer types are likely path parameters (e.g., :id -> u32)
            return .path_param;
        },
        .@"struct" => {
            // Struct types are likely JSON body parameters
            return .body_param;
        },
        .@"enum" => {
            // Enum types could be path or query parameters
            return .path_param;
        },
        .bool => {
            // Boolean types are likely query parameters
            return .query_param;
        },
        else => {
            return .unknown;
        }
    }
}

/// Check if a type is a service (should be dependency injected)
pub fn isServiceType(comptime T: type) bool {
    return classifyParameterType(T) == .service;
}

/// Check if a type is an extractor (should be extracted from request)
pub fn isExtractorType(comptime T: type) bool {
    const classification = classifyParameterType(T);
    return classification == .path_param or 
           classification == .query_param or 
           classification == .header_param or 
           classification == .body_param;
}

/// Basic wrapper generation (prototype - generates function signature only)
pub fn generateWrapperSignature(comptime handler: anytype) []const u8 {
    _ = handler;
    
    // For the prototype, return a simple static wrapper
    return "fn generatedWrapper(event: *H3Event) !void {\n" ++
           "    // TODO: Extract parameters\n" ++
           "    // TODO: Call original handler\n" ++
           "    // TODO: Handle return value\n" ++
           "}";
}

// Tests for the compile-time analysis system
test "HandlerAnalyzer basic function analysis" {
    const TestHandler1 = struct {
        fn handler() void {}
    };
    
    const TestHandler2 = struct {
        fn handler(id: u32) void {
            _ = id;
        }
    };
    
    const TestHandler3 = struct {
        fn handler(name: []const u8, age: ?u32) !void {
            _ = name;
            _ = age;
        }
    };
    
    // Test no parameters
    const analysis1 = HandlerAnalyzer.analyzeFunction(TestHandler1.handler);
    try std.testing.expect(analysis1.is_valid);
    try std.testing.expectEqual(@as(usize, 0), analysis1.param_count);
    try std.testing.expect(!analysis1.has_services);
    try std.testing.expect(!analysis1.has_extractors);
    
    // Test single integer parameter
    const analysis2 = HandlerAnalyzer.analyzeFunction(TestHandler2.handler);
    try std.testing.expect(analysis2.is_valid);
    try std.testing.expectEqual(@as(usize, 1), analysis2.param_count);
    try std.testing.expectEqual(ParameterClassification.path_param, analysis2.params[0].classification);
    
    // Test multiple parameters with different types
    const analysis3 = HandlerAnalyzer.analyzeFunction(TestHandler3.handler);
    try std.testing.expect(analysis3.is_valid);
    try std.testing.expectEqual(@as(usize, 2), analysis3.param_count);
    try std.testing.expectEqual(ParameterClassification.query_param, analysis3.params[0].classification);
    try std.testing.expectEqual(ParameterClassification.path_param, analysis3.params[1].classification);
    try std.testing.expect(analysis3.params[1].is_optional);
}

test "Parameter type classification" {
    // Test integer classification
    try std.testing.expectEqual(ParameterClassification.path_param, classifyParameterType(u32));
    try std.testing.expectEqual(ParameterClassification.path_param, classifyParameterType(i64));
    
    // Test string classification
    try std.testing.expectEqual(ParameterClassification.query_param, classifyParameterType([]const u8));
    
    // Test boolean classification
    try std.testing.expectEqual(ParameterClassification.query_param, classifyParameterType(bool));
    
    // Test optional types
    try std.testing.expectEqual(ParameterClassification.path_param, classifyParameterType(?u32));
    try std.testing.expectEqual(ParameterClassification.query_param, classifyParameterType(?[]const u8));
    
    // Test struct classification (body param)
    const TestStruct = struct { name: []const u8, age: u32 };
    try std.testing.expectEqual(ParameterClassification.body_param, classifyParameterType(TestStruct));
    
    // Test service types (pointers to structs)
    const TestService = struct { data: []const u8 };
    try std.testing.expectEqual(ParameterClassification.service, classifyParameterType(*TestService));
}

test "Service and extractor type detection" {
    const TestService = struct { data: []const u8 };
    
    // Services (dependency injection)
    try std.testing.expect(isServiceType(*TestService));
    try std.testing.expect(!isExtractorType(*TestService));
    
    // Extractors (from request)
    try std.testing.expect(!isServiceType(u32));
    try std.testing.expect(isExtractorType(u32));
    
    try std.testing.expect(!isServiceType([]const u8));
    try std.testing.expect(isExtractorType([]const u8));
    
    try std.testing.expect(!isServiceType(bool));
    try std.testing.expect(isExtractorType(bool));
}

test "Complex handler analysis" {
    const TestService = struct { data: []const u8 };
    const TestBody = struct { message: []const u8, count: u32 };
    
    const ComplexHandler = struct {
        fn handler(id: u32, name: ?[]const u8, active: bool, body: TestBody, service: *TestService) !TestBody {
            _ = id;
            _ = name;
            _ = active;
            _ = body;
            _ = service;
            return TestBody{ .message = "test", .count = 1 };
        }
    };
    
    const analysis = HandlerAnalyzer.analyzeFunction(ComplexHandler.handler);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 5), analysis.param_count);
    try std.testing.expect(analysis.has_services);
    try std.testing.expect(analysis.has_extractors);
    try std.testing.expect(analysis.return_is_error_union);
    try std.testing.expect(!analysis.return_is_void);
    
    try std.testing.expectEqual(@as(usize, 1), analysis.getPathParamCount());     // id: u32
    try std.testing.expectEqual(@as(usize, 2), analysis.getQueryParamCount());    // name: ?[]const u8, active: bool
    try std.testing.expectEqual(@as(usize, 1), analysis.getBodyParamCount());     // body: TestBody
    try std.testing.expectEqual(@as(usize, 1), analysis.getServiceCount());       // service: *TestService
}

test "Wrapper signature generation" {
    const SimpleHandler = struct {
        fn handler(id: u32, name: []const u8) void {
            _ = id;
            _ = name;
        }
    };
    
    const signature = generateWrapperSignature(SimpleHandler.handler);
    
    // Basic validation that signature contains expected elements
    try std.testing.expect(std.mem.indexOf(u8, signature, "generatedWrapper") != null);
    try std.testing.expect(std.mem.indexOf(u8, signature, "H3Event") != null);
    try std.testing.expect(std.mem.indexOf(u8, signature, "TODO") != null);
}