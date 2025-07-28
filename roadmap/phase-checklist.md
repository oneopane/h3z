# H3Z Cleanup Phase Checklist

## Phase 1: Router System Consolidation ⬜

### Pre-Phase Checklist
- [ ] Create feature branch: `cleanup/remove-redundancies`
- [ ] Run all tests to establish baseline
- [ ] Document current performance metrics

### Implementation Tasks
- [ ] **1.1** Delete `src/core/compile_time_router.zig`
- [ ] **1.2** Copy TrieNode and TrieRouter to `router.zig`
- [ ] **1.2** Update imports from `trie_router` to `router`
- [ ] **1.2** Delete `src/core/trie_router.zig`
- [ ] **1.3** Remove CompiledPattern struct and methods
- [ ] **1.3** Remove route compilation features
- [ ] **1.4** Remove `findRouteLegacy()` method
- [ ] **1.4** Remove `matchPatternSimple()` method
- [ ] **1.5** Remove `Router.RouterConfig` struct
- [ ] **1.5** Update RouterComponent to use `config.RouterConfig`

### Validation
- [ ] All router tests pass
- [ ] Performance benchmarks show no regression
- [ ] Example applications work correctly
- [ ] No compilation errors
- [ ] Commit changes with descriptive message

## Phase 2: Middleware System Unification ⬜

### Pre-Phase Checklist
- [ ] Ensure Phase 1 is complete and stable
- [ ] Document middleware usage patterns

### Implementation Tasks
- [ ] **2.1** Remove traditional middleware from `app.zig`
- [ ] **2.1** Update `handle()` to use only fast middleware
- [ ] **2.2** Delete `src/core/middleware.zig`
- [ ] **2.3** Rename `fast_middleware.zig` to `middleware.zig`
- [ ] **2.4** Update all imports in `h3.zig`
- [ ] **2.4** Update all imports in `app.zig`
- [ ] **2.4** Search and update any other imports
- [ ] **2.5** Rename types (FastMiddleware → Middleware)
- [ ] **2.6** Update documentation and examples

### Validation
- [ ] All middleware tests pass
- [ ] No references to "fast_middleware" remain
- [ ] Example applications work
- [ ] Documentation is updated
- [ ] Commit changes

## Phase 3: Directory Structure Consolidation ⬜

### Pre-Phase Checklist
- [ ] Ensure Phase 2 is complete
- [ ] Check for any custom logger usage

### Implementation Tasks
- [ ] **3.1** Move `src/util/logger.zig` to `src/utils/logger.zig`
- [ ] **3.1** Delete `src/util/` directory
- [ ] **3.2** Update import in `libxev.zig`
- [ ] **3.3** Evaluate custom logger necessity
- [ ] **3.3** Standardize logging approach if needed

### Validation
- [ ] Build succeeds
- [ ] Logging works in all components
- [ ] No import errors
- [ ] Commit changes

## Phase 4: Server Adapter Deduplication ⬜

### Pre-Phase Checklist
- [ ] Ensure previous phases complete
- [ ] Analyze common code between adapters

### Implementation Tasks
- [ ] **4.1** Create `src/server/protocol.zig`
- [ ] **4.1** Implement shared HTTP parsing logic
- [ ] **4.2** Update `std.zig` to use shared protocol
- [ ] **4.2** Update `libxev.zig` to use shared protocol
- [ ] **4.3** Remove unused SSL configuration
- [ ] **4.3** Remove unused compression configuration
- [ ] **4.3** Remove unused rate limiting configuration

### Validation
- [ ] Both adapters still work
- [ ] HTTP parsing is consistent
- [ ] Tests pass for both adapters
- [ ] Commit changes

## Phase 5: Configuration and Utilities Cleanup ⬜

### Pre-Phase Checklist
- [ ] Ensure all previous phases complete
- [ ] Map utility usage across codebase

### Implementation Tasks
- [ ] **5.1** Consolidate URL encoding/decoding
- [ ] **5.1** Update `utils/body.zig` imports
- [ ] **5.1** Update `utils/cookie.zig` imports
- [ ] **5.2** Create unified content type module
- [ ] **5.2** Merge all MIME/content type handling
- [ ] **5.3** Remove unused pattern matching code
- [ ] **5.3** Remove unused URL parsing functions

### Validation
- [ ] All imports updated
- [ ] No duplicate code remains
- [ ] All tests pass
- [ ] Commit changes

## Final Validation ⬜

### Testing
- [ ] Run complete test suite
- [ ] Run performance benchmarks
- [ ] Test all example applications
- [ ] Check memory usage

### Documentation
- [ ] Update architecture diagrams
- [ ] Update API documentation
- [ ] Create migration guide
- [ ] Update CHANGELOG

### Code Quality
- [ ] Run linter
- [ ] Check test coverage
- [ ] Review all changes
- [ ] Ensure no TODOs added

### Release Preparation
- [ ] Merge feature branch
- [ ] Tag release
- [ ] Prepare release notes
- [ ] Notify users of breaking changes

## Notes Section

Use this section to track any issues, decisions, or observations during the cleanup:

```
Date: 
Phase: 
Notes:

```