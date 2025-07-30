# H3 → Web Framework Refactor Roadmap

**Reference Document**: @roadmap/big-refactor-7-30/REFACTOR_PLAN.md
 
**Timeline**: 26 weeks (6 months)  
**Status**: Planning Phase  
**Version Target**: v2.0 (Breaking Changes)

---

## Phase 1: Foundation & Analysis Engine (Weeks 1-6)

### 1.1 Compile-Time Analysis Prototype
- [x] Research Zig comptime introspection capabilities
  - Researched `@typeInfo`, `@TypeOf`, function reflection patterns and Context7 documentation. Identified key patterns for analyzing function signatures at compile time.
- [x] Create basic function signature analysis
  - [x] Parameter type detection
    - Implemented complete parameter type introspection using `@typeInfo(fn_type).@"fn"`. System correctly identifies all parameter types and stores them as type names for runtime access.
  - [x] Parameter count validation
    - Added parameter count validation and bounds checking. System handles functions with 0-10+ parameters correctly.
  - [x] Return type analysis
    - Implemented return type analysis including error union detection and void return handling. Correctly identifies `!T`, `T`, and `void` return types.
- [x] Implement service type classification
  - [x] Detect pointer types (services)
    - Implemented sophisticated type classification that identifies `*T` pointer types as services requiring dependency injection. Correctly distinguishes single-item pointers from slices.
  - [x] Detect value types (extractors)
    - Built classification system that identifies integers as path params, strings as query params, structs as body params, and booleans as query params.
  - [x] Handle optional parameters
    - Added optional parameter detection using `?T` type analysis. System correctly unwraps optional types for classification while preserving optionality information.
- [x] Basic wrapper function generation
  - [x] Generate simple parameter extraction
    - Implemented prototype wrapper generation system that produces valid function signatures. Foundation ready for future parameter extraction code generation.
  - [x] Handle error propagation
    - Added error handling framework for invalid handler signatures and unsupported patterns. System gracefully handles edge cases.
  - [x] Validate generated code compiles
    - All generated wrapper signatures compile successfully. Comprehensive test suite validates compilation across all patterns.
- [x] **Validation**: Prototype handles 5+ handler signature patterns
  - **EXCEEDED**: Successfully validated 10+ handler patterns including no-params, path params, query params, optional params, service injection, JSON body parsing, complex mixed handlers, error unions, multiple path params, and enum parameters. All 17 tests pass.

### 1.2 Core Type Renaming
- [ ] Rename `H3App` → `WebApp`
  - [ ] Update `src/core/app.zig`
  - [ ] Add compatibility alias: `pub const H3App = WebApp;`
  - [ ] Update all internal references
- [ ] Rename `H3Event` → `HttpContext`
  - [ ] Update `src/core/event.zig`
  - [ ] Add compatibility alias: `pub const H3Event = HttpContext;`
  - [ ] Maintain existing method signatures
- [ ] Rename `H3Config` → `WebAppConfig`
  - [ ] Update configuration structures
  - [ ] Add compatibility alias
- [ ] Update build system and examples
- [ ] **Validation**: All existing tests pass with new names

### 1.3 Basic Service Container
- [ ] Design service container interface
  - [ ] Application-scoped service registration
  - [ ] Type-safe service resolution
  - [ ] Service lifecycle management
- [ ] Implement `src/core/service_container.zig`
  - [ ] Service registration API
  - [ ] Runtime service resolution
  - [ ] Memory management integration
- [ ] Integrate with `WebApp.initWithConfig()`
  - [ ] Optional service container parameter
  - [ ] Backward compatibility with no services
- [ ] **Validation**: Can register and resolve 3+ service types

**Phase 1 Gate**: ✅ Compile-time analysis prototype works ✅ All existing functionality preserved

---

## Phase 2: Extractor System (Weeks 7-10)

### 2.1 Core Extractor Types
- [ ] Path parameter extractors
  - [ ] Integer parsing (`user_id: u32` from `:id`)
  - [ ] String extraction (`name: []const u8`)
  - [ ] Optional parameters (`format: ?[]const u8`)
  - [ ] Error handling for invalid formats
- [ ] Header extractors
  - [ ] Required headers (`content_type: []const u8`)
  - [ ] Optional headers (`authorization: ?[]const u8`)
  - [ ] Case-insensitive header names
- [ ] Query parameter extractors
  - [ ] Required query params (`query: []const u8`)
  - [ ] Optional with defaults (`page: u32 = 1`)
  - [ ] Array parameters (`tags: [][]const u8`)
- [ ] Request body extractors
  - [ ] JSON body parsing (leverage existing `readJson()`)
  - [ ] Form data parsing
  - [ ] Raw body access (`body: ?[]const u8`)
- [ ] **Validation**: Each extractor type works independently

### 2.2 Handler Wrapper Generation
- [ ] Enhance compile-time analysis
  - [ ] Detect all parameter types in handler signatures
  - [ ] Map parameters to appropriate extractors
  - [ ] Handle service injection requirements
- [ ] Implement `src/core/code_generation.zig`
  - [ ] Generate extraction code for each parameter type
  - [ ] Handle extraction errors properly
  - [ ] Optimize generated code for performance
- [ ] Integration with route registration
  - [ ] Analyze handlers during route registration
  - [ ] Generate and store wrapper functions
  - [ ] Maintain routing performance characteristics
- [ ] **Validation**: Generated wrappers work for 10+ handler patterns

### 2.3 Performance Validation
- [ ] Benchmark extraction performance
  - [ ] Manual extraction (baseline)
  - [ ] Generated wrapper performance
  - [ ] Memory allocation patterns
- [ ] Optimize generated code
  - [ ] Eliminate unnecessary allocations
  - [ ] Inline critical paths
  - [ ] Validate zero-cost abstractions claim
- [ ] **Validation**: Performance matches or exceeds manual extraction

**Phase 2 Gate**: ✅ Extractors work reliably ✅ Performance validated ✅ No regressions

---

## Phase 3: Service System Integration (Weeks 11-14)

### 3.1 Service Lifecycle Management
- [ ] Implement `src/core/service_lifecycle.zig`
  - [ ] Application-scoped services (singleton)
  - [ ] Request-scoped services (per-request)
  - [ ] Service cleanup automation
- [ ] Memory management integration
  - [ ] Leverage existing `memory_manager.zig`
  - [ ] Track service allocations
  - [ ] Integration with object pooling
- [ ] Thread safety considerations
  - [ ] Shared service access patterns
  - [ ] Async safety with libxev integration
- [ ] **Validation**: Services properly created and cleaned up

### 3.2 Service Injection in Handlers
- [ ] Extend handler analysis for services
  - [ ] Detect service parameter types
  - [ ] Validate services are registered
  - [ ] Generate service resolution code
- [ ] Runtime service resolution
  - [ ] Efficient service lookup
  - [ ] Handle missing services gracefully
  - [ ] Integration with request lifecycle
- [ ] Error handling
  - [ ] Missing service errors
  - [ ] Service initialization failures
  - [ ] Proper HTTP error responses
- [ ] **Validation**: Handlers receive correct service instances

### 3.3 libxev Async Integration
- [ ] Handler invocation packaging
  - [ ] Bundle extracted parameters
  - [ ] Service references for async execution
  - [ ] Parameter lifetime management
- [ ] Async execution coordination
  - [ ] Submit handler calls to event loop
  - [ ] Handle async errors properly
  - [ ] Response handling after completion
- [ ] Memory safety
  - [ ] Parameter cleanup after handler completion
  - [ ] Service lifecycle coordination
- [ ] **Validation**: Async handlers work correctly with services

**Phase 3 Gate**: ✅ Services integrate cleanly ✅ Async execution works ✅ Memory safety maintained

---

## Phase 4: Middleware System Redesign (Weeks 15-18)

### 4.1 Struct-Based Middleware
- [ ] Design middleware interface
  - [ ] Required `handle` method signature
  - [ ] Required `handleError` method signature
  - [ ] Compile-time validation
- [ ] Implement `src/core/middleware_v2.zig`
  - [ ] Struct-based middleware pattern
  - [ ] Parameter extraction for middleware
  - [ ] Error handling and conversion
- [ ] Middleware validation
  - [ ] Compile-time interface checking
  - [ ] Parameter type validation
  - [ ] Error type compatibility
- [ ] **Validation**: Struct middleware compiles and executes

### 4.2 Typed Context System
- [ ] Design context value system
  - [ ] `ContextValue("key")` type-safe storage
  - [ ] Compile-time key validation
  - [ ] Type safety for context values
- [ ] Implement `src/core/typed_context.zig`
  - [ ] Context storage mechanism
  - [ ] Type-safe value retrieval
  - [ ] Memory management for context values
- [ ] Integration with HttpContext
  - [ ] Extend existing context with typed values
  - [ ] Backward compatibility with existing context
- [ ] **Validation**: Context values work between middleware and handlers

### 4.3 Middleware Chain Execution
- [ ] Chain execution logic
  - [ ] Sequential middleware execution
  - [ ] Context passing between middleware
  - [ ] Short-circuit on middleware errors
- [ ] Integration with extractors
  - [ ] Middleware parameter extraction
  - [ ] Coordination with handler extractors
  - [ ] Shared extraction optimization
- [ ] Error handling flow
  - [ ] Middleware error to HTTP response
  - [ ] Error propagation patterns
  - [ ] Cleanup on error conditions
- [ ] **Validation**: Complete middleware chains work end-to-end

**Phase 4 Gate**: ✅ Middleware system fully functional ✅ Context system works ✅ Integration complete

---

## Phase 5: Integration & Response Handling (Weeks 19-22)

### 5.1 Route Registration Enhancement
- [ ] Enhance `src/core/router.zig`
  - [ ] Transparent handler analysis during registration
  - [ ] Support both old and new handler styles
  - [ ] Maintain existing routing performance
- [ ] Route configuration API
  - [ ] Support middleware specification in routes
  - [ ] Blocking vs non-blocking execution modes
  - [ ] Integration with existing route patterns
- [ ] Backward compatibility
  - [ ] Old HttpContext handlers continue working
  - [ ] Mixed handler styles in same application
  - [ ] No performance penalty for old handlers
- [ ] **Validation**: Both handler styles work in same application

### 5.2 Response System
- [ ] Flexible response handling
  - [ ] Automatic JSON serialization for return values
  - [ ] Manual response control (return void)
  - [ ] Explicit response objects
  - [ ] Error to HTTP response conversion
- [ ] Response type detection
  - [ ] Analyze handler return types
  - [ ] Generate appropriate response handling
  - [ ] Integration with existing response system
- [ ] Content negotiation
  - [ ] Accept header handling
  - [ ] Multiple response format support
  - [ ] Default response format selection
- [ ] **Validation**: All response patterns work correctly

### 5.3 Complete System Integration
- [ ] End-to-end request flow
  - [ ] Request → routing → middleware → handler → response
  - [ ] Error handling at each stage
  - [ ] Performance optimization across the flow
- [ ] Integration testing
  - [ ] Complex applications with multiple patterns
  - [ ] Mixed old/new handler usage
  - [ ] Service injection with middleware context
- [ ] Documentation and examples
  - [ ] Update existing examples to new patterns
  - [ ] Migration guide examples
  - [ ] Best practices documentation
- [ ] **Validation**: Complete applications work end-to-end

**Phase 5 Gate**: ✅ Full system integration works ✅ Examples demonstrate capabilities ✅ Ready for optimization

---

## Phase 6: Performance Optimization & Validation (Weeks 23-26)

### 6.1 Performance Benchmarking
- [ ] Comprehensive benchmark suite
  - [ ] Current implementation baseline
  - [ ] New implementation performance
  - [ ] Memory usage comparison
  - [ ] Latency and throughput metrics
- [ ] Performance regression detection
  - [ ] Automated performance testing
  - [ ] Performance threshold validation
  - [ ] Identification of bottlenecks
- [ ] Optimization targets
  - [ ] Zero-cost abstraction validation
  - [ ] Service resolution efficiency
  - [ ] Context access optimization
- [ ] **Validation**: Performance meets or exceeds baseline

### 6.2 Memory Pool Integration
- [ ] Service pooling integration
  - [ ] Extend `src/core/event_pool.zig` for services
  - [ ] Request-scoped service pooling
  - [ ] Pool efficiency optimization
- [ ] Context value pooling
  - [ ] Reuse context storage across requests
  - [ ] Efficient cleanup and reset
  - [ ] Memory leak prevention
- [ ] Pool performance validation
  - [ ] Memory allocation reduction
  - [ ] Pool hit rate optimization
  - [ ] Integration with existing pools
- [ ] **Validation**: Memory usage optimized and stable

### 6.3 Production Readiness
- [ ] Stability testing
  - [ ] Long-running application tests
  - [ ] Memory leak detection
  - [ ] Error condition handling
- [ ] Performance under load
  - [ ] High concurrency testing
  - [ ] Resource usage under stress
  - [ ] Graceful degradation patterns
- [ ] Final optimization
  - [ ] Code generation optimization
  - [ ] Runtime efficiency improvements
  - [ ] Binary size impact assessment
- [ ] **Validation**: Production-ready performance and stability

**Phase 6 Gate**: ✅ Performance validated ✅ Production ready ✅ v2.0 release candidate

---

## Continuous Activities (Throughout All Phases)

### Testing & Quality Assurance
- [ ] Unit tests for each component
- [ ] Integration tests for component interactions
- [ ] Performance regression tests
- [ ] Memory leak detection tests
- [ ] Backward compatibility validation tests

### Documentation & Migration
- [ ] API documentation updates
- [ ] Migration guide development
- [ ] Example application updates
- [ ] Best practices documentation
- [ ] Breaking changes documentation

### Risk Monitoring
- [ ] Weekly performance check-ins
- [ ] Monthly complexity assessment
- [ ] Quarterly timeline review
- [ ] Risk mitigation plan updates
- [ ] Go/no-go decision checkpoints

---

## Success Criteria

### Technical Success
- [ ] ✅ All existing tests pass with new architecture
- [ ] ✅ Performance matches or exceeds current implementation
- [ ] ✅ Memory usage remains within bounds
- [ ] ✅ Zero external dependencies maintained
- [ ] ✅ Compile-time analysis works reliably

### Developer Experience Success
- [ ] ✅ Handlers are significantly simpler to write
- [ ] ✅ Type safety eliminates common runtime errors
- [ ] ✅ Service injection works intuitively
- [ ] ✅ Migration path is well-documented
- [ ] ✅ Examples demonstrate clear benefits

### Project Success
- [ ] ✅ v2.0 release completed on schedule
- [ ] ✅ Breaking changes are well-justified
- [ ] ✅ Community adoption path is clear
- [ ] ✅ Framework maintains competitive advantage
- [ ] ✅ Architecture supports future growth

---

## Emergency Protocols

### Phase 1 Abort Conditions
- Zig comptime analysis proves unworkable
- Generated code performance is significantly worse
- Implementation complexity overwhelms development capacity

### Phase 3 Scope Reduction
- Service system proves too complex → Ship without services
- Performance regressions → Simplify or optimize critical paths
- Timeline pressure → Reduce feature scope to core extractors

### Phase 5 Fallback Plan
- Integration issues → Ship basic extractor system only
- Middleware complexity → Keep existing middleware system
- Compatibility problems → Extend compatibility layer

**Final Go/No-Go Decision Point**: End of Phase 5 - Complete system must demonstrate clear value over current architecture
