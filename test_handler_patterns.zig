//! Test file for Phase 1.1 - Handler Signature Pattern Validation
//! 
//! This file contains 5+ different handler signature patterns to validate
//! that the compile-time analysis system works correctly.

const std = @import("std");
const comptime_analysis = @import("src/core/comptime_analysis.zig");
const HandlerAnalyzer = comptime_analysis.HandlerAnalyzer;
const ParameterClassification = comptime_analysis.ParameterClassification;

// Test services for injection
const DatabaseService = struct {
    connection: []const u8,
    
    pub fn getUser(self: *DatabaseService, id: u32) ?[]const u8 {
        _ = self;
        _ = id;
        return "user_data";
    }
};

const LoggerService = struct {
    level: []const u8,
    
    pub fn log(self: *LoggerService, message: []const u8) void {
        _ = self;
        _ = message;
    }
};

// Test request/response types
const UserRequest = struct {
    name: []const u8,
    email: []const u8,
    age: u32,
};

const UserResponse = struct {
    id: u32,
    name: []const u8,
    created_at: []const u8,
};

/// Pattern 1: Simple handler with no parameters
/// Expected: No extractors, no services
const Pattern1Handler = struct {
    fn handle() void {
        // Simple handler that returns static content
    }
};

/// Pattern 2: Path parameter extraction
/// Expected: 1 path parameter (id: u32)
const Pattern2Handler = struct {
    fn handle(id: u32) void {
        _ = id;
        // Extract user ID from path like /users/:id
    }
};

/// Pattern 3: Query parameter extraction
/// Expected: 2 query parameters (name: []const u8, active: bool)
const Pattern3Handler = struct {
    fn handle(name: []const u8, active: bool) void {
        _ = name;
        _ = active;
        // Extract query parameters like ?name=john&active=true
    }
};

/// Pattern 4: Optional parameters
/// Expected: 2 parameters, 1 required path param, 1 optional query param
const Pattern4Handler = struct {
    fn handle(id: u32, filter: ?[]const u8) void {
        _ = id;
        _ = filter;
        // Required path parameter + optional query parameter
    }
};

/// Pattern 5: Service injection
/// Expected: 1 service parameter (db: *DatabaseService)
const Pattern5Handler = struct {
    fn handle(db: *DatabaseService) void {
        _ = db;
        // Service dependency injection
    }
};

/// Pattern 6: JSON body parsing
/// Expected: 1 body parameter (request: UserRequest)
const Pattern6Handler = struct {
    fn handle(request: UserRequest) void {
        _ = request;
        // Parse JSON request body into struct
    }
};

/// Pattern 7: Complex mixed handler
/// Expected: Mixed parameter types with extractors and services
const Pattern7Handler = struct {
    fn handle(id: u32, name: ?[]const u8, active: bool, request: UserRequest, db: *DatabaseService, logger: *LoggerService) !UserResponse {
        _ = id;
        _ = name;
        _ = active;
        _ = request;
        _ = db;
        _ = logger;
        return UserResponse{
            .id = 1,
            .name = "test",
            .created_at = "2024-01-01",
        };
    }
};

/// Pattern 8: Error union return type
/// Expected: Error union return, service injection
const Pattern8Handler = struct {
    const HandlerError = error{ValidationFailed};
    
    fn handle(db: *DatabaseService) HandlerError![]const u8 {
        _ = db;
        return "success";
    }
};

/// Pattern 9: Multiple path parameters
/// Expected: Multiple path parameters (organization_id, user_id)
const Pattern9Handler = struct {
    fn handle(organization_id: u32, user_id: u32) void {
        _ = organization_id;
        _ = user_id;
        // Handle /orgs/:org_id/users/:user_id
    }
};

/// Pattern 10: Enum parameter
/// Expected: Path parameter with enum type
const Pattern10Handler = struct {
    const UserRole = enum { admin, user, guest };
    
    fn handle(role: UserRole) void {
        _ = role;
        // Handle enum path parameter
    }
};

test "Pattern 1: No parameters" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern1Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 0), analysis.param_count);
    try std.testing.expect(!analysis.has_services);
    try std.testing.expect(!analysis.has_extractors);
    try std.testing.expect(analysis.return_is_void);
    try std.testing.expect(!analysis.return_is_error_union);
}

test "Pattern 2: Single path parameter" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern2Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 1), analysis.param_count);
    try std.testing.expect(!analysis.has_services);
    try std.testing.expect(analysis.has_extractors);
    try std.testing.expectEqual(@as(usize, 1), analysis.getPathParamCount());
    try std.testing.expectEqual(ParameterClassification.path_param, analysis.params[0].classification);
    try std.testing.expectEqualStrings("u32", analysis.params[0].type_name);
}

test "Pattern 3: Query parameters" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern3Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 2), analysis.param_count);
    try std.testing.expect(!analysis.has_services);
    try std.testing.expect(analysis.has_extractors);
    try std.testing.expectEqual(@as(usize, 2), analysis.getQueryParamCount());
    try std.testing.expectEqual(ParameterClassification.query_param, analysis.params[0].classification);
    try std.testing.expectEqual(ParameterClassification.query_param, analysis.params[1].classification);
}

test "Pattern 4: Optional parameters" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern4Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 2), analysis.param_count);
    try std.testing.expect(analysis.has_extractors);
    try std.testing.expectEqual(@as(usize, 1), analysis.getPathParamCount());
    try std.testing.expectEqual(@as(usize, 1), analysis.getQueryParamCount());
    
    // First parameter should be required path param
    try std.testing.expectEqual(ParameterClassification.path_param, analysis.params[0].classification);
    try std.testing.expect(!analysis.params[0].is_optional);
    
    // Second parameter should be optional query param
    try std.testing.expectEqual(ParameterClassification.query_param, analysis.params[1].classification);
    try std.testing.expect(analysis.params[1].is_optional);
}

test "Pattern 5: Service injection" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern5Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 1), analysis.param_count);
    try std.testing.expect(analysis.has_services);
    try std.testing.expect(!analysis.has_extractors);
    try std.testing.expectEqual(@as(usize, 1), analysis.getServiceCount());
    try std.testing.expectEqual(ParameterClassification.service, analysis.params[0].classification);
    try std.testing.expect(analysis.params[0].is_pointer);
}

test "Pattern 6: JSON body parsing" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern6Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 1), analysis.param_count);
    try std.testing.expect(!analysis.has_services);
    try std.testing.expect(analysis.has_extractors);
    try std.testing.expectEqual(@as(usize, 1), analysis.getBodyParamCount());
    try std.testing.expectEqual(ParameterClassification.body_param, analysis.params[0].classification);
}

test "Pattern 7: Complex mixed handler" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern7Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 6), analysis.param_count);
    try std.testing.expect(analysis.has_services);
    try std.testing.expect(analysis.has_extractors);
    try std.testing.expect(analysis.return_is_error_union);
    try std.testing.expect(!analysis.return_is_void);
    
    // Check parameter counts
    try std.testing.expectEqual(@as(usize, 1), analysis.getPathParamCount());  // id: u32
    try std.testing.expectEqual(@as(usize, 2), analysis.getQueryParamCount()); // name: ?[]const u8, active: bool
    try std.testing.expectEqual(@as(usize, 1), analysis.getBodyParamCount());  // request: UserRequest
    try std.testing.expectEqual(@as(usize, 2), analysis.getServiceCount());    // db, logger services
    
    // Verify parameter classifications
    try std.testing.expectEqual(ParameterClassification.path_param, analysis.params[0].classification);   // id
    try std.testing.expectEqual(ParameterClassification.query_param, analysis.params[1].classification);  // name
    try std.testing.expectEqual(ParameterClassification.query_param, analysis.params[2].classification);  // active
    try std.testing.expectEqual(ParameterClassification.body_param, analysis.params[3].classification);   // request
    try std.testing.expectEqual(ParameterClassification.service, analysis.params[4].classification);      // db
    try std.testing.expectEqual(ParameterClassification.service, analysis.params[5].classification);      // logger
}

test "Pattern 8: Error union return" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern8Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 1), analysis.param_count);
    try std.testing.expect(analysis.has_services);
    try std.testing.expect(analysis.return_is_error_union);
    try std.testing.expect(!analysis.return_is_void);
}

test "Pattern 9: Multiple path parameters" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern9Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 2), analysis.param_count);
    try std.testing.expect(analysis.has_extractors);
    try std.testing.expectEqual(@as(usize, 2), analysis.getPathParamCount());
    try std.testing.expectEqual(ParameterClassification.path_param, analysis.params[0].classification);
    try std.testing.expectEqual(ParameterClassification.path_param, analysis.params[1].classification);
}

test "Pattern 10: Enum parameter" {
    const analysis = HandlerAnalyzer.analyzeFunction(Pattern10Handler.handle);
    
    try std.testing.expect(analysis.is_valid);
    try std.testing.expectEqual(@as(usize, 1), analysis.param_count);
    try std.testing.expect(analysis.has_extractors);
    try std.testing.expectEqual(@as(usize, 1), analysis.getPathParamCount());
    try std.testing.expectEqual(ParameterClassification.path_param, analysis.params[0].classification);
}

test "All patterns produce valid wrapper signatures" {
    // Test that all patterns can generate wrapper signatures without error
    _ = comptime_analysis.generateWrapperSignature(Pattern1Handler.handle);
    _ = comptime_analysis.generateWrapperSignature(Pattern2Handler.handle);
    _ = comptime_analysis.generateWrapperSignature(Pattern3Handler.handle);
    _ = comptime_analysis.generateWrapperSignature(Pattern4Handler.handle);
    _ = comptime_analysis.generateWrapperSignature(Pattern5Handler.handle);
    _ = comptime_analysis.generateWrapperSignature(Pattern6Handler.handle);
    _ = comptime_analysis.generateWrapperSignature(Pattern7Handler.handle);
    _ = comptime_analysis.generateWrapperSignature(Pattern8Handler.handle);
    _ = comptime_analysis.generateWrapperSignature(Pattern9Handler.handle);
    _ = comptime_analysis.generateWrapperSignature(Pattern10Handler.handle);
    
    // If we get here without panic, all patterns work
    try std.testing.expect(true);
}

test "Handler validation works correctly" {
    // Test that all patterns validate successfully
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern1Handler.handle));
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern2Handler.handle));
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern3Handler.handle));
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern4Handler.handle));
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern5Handler.handle));
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern6Handler.handle));
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern7Handler.handle));
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern8Handler.handle));
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern9Handler.handle));
    try std.testing.expect(HandlerAnalyzer.validateHandler(Pattern10Handler.handle));
}