# H3Z Codebase Cleanup Implementation Workflow

## Overview
This workflow guides the systematic cleanup of the H3Z codebase to remove redundancies, consolidate duplicate functionality, and simplify the architecture while maintaining all existing functionality.

**Estimated Timeline**: 2-3 weeks  
**Complexity**: Medium-High  
**Risk Level**: Medium (extensive refactoring of core systems)

## Phase 1: Router System Consolidation (Week 1, Days 1-3)

### Objective
Reduce router complexity by ~40% through consolidation and removal of unused features.

### Tasks

#### 1.1 Remove Compile-Time Router (2 hours)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Low (completely unused)

```bash
# Actions:
1. Delete src/core/compile_time_router.zig
2. Remove any references (grep shows none exist)
3. Update build.zig if referenced
```

#### 1.2 Consolidate Trie Router (4 hours)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Medium (core functionality)

```zig
// Steps:
1. Copy TrieNode and TrieRouter from trie_router.zig to router.zig
2. Make them private structs within router.zig
3. Update all imports and references
4. Run tests to ensure functionality preserved
5. Delete trie_router.zig
```

#### 1.3 Remove Router Compilation Features (3 hours)
**Persona**: Backend Developer  
**Priority**: Medium  
**Risk**: Medium

```zig
// Remove from router.zig:
- CompiledPattern struct and all methods
- Route.compiled_pattern field
- Route.compile() method
- enable_route_compilation config option
- All compilation-related logic in addRoute()
```

#### 1.4 Remove Legacy Routing (2 hours)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Low

```zig
// Remove from router.zig:
- findRouteLegacy() method
- matchPatternSimple() method
- enable_trie config (make Trie default)
- Legacy fallback in findRoute()
```

#### 1.5 Unify Router Configuration (1 hour)
**Persona**: Architect  
**Priority**: Medium  
**Risk**: Low

```zig
// Actions:
1. Remove Router.RouterConfig struct
2. Update RouterComponent to use config.RouterConfig directly
3. Remove configuration translation logic
```

### Validation
- [ ] All router tests pass
- [ ] Performance benchmarks show no regression
- [ ] Example applications work correctly

## Phase 2: Middleware System Unification (Week 1, Days 3-4)

### Objective
Standardize on fast middleware system, removing traditional middleware and renaming for clarity.

### Tasks

#### 2.1 Update App to Use Fast Middleware Only (3 hours)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Medium

```zig
// In app.zig:
1. Remove middlewares field (traditional)
2. Remove use() method for traditional middleware
3. Update handle() to only use fast_middlewares
4. Remove executeMiddlewareAtIndex()
5. Update imports to prepare for rename
```

#### 2.2 Remove Traditional Middleware (1 hour)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Low

```bash
# Actions:
1. Delete src/core/middleware.zig
2. Update all imports to use fast_middleware.zig
3. Update h3.zig exports
```

#### 2.3 Rename Fast Middleware (1 hour)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Medium

```bash
# Commands:
mv src/core/fast_middleware.zig src/core/middleware.zig

# Update all imports:
# From: const fast_middleware = @import("fast_middleware.zig");
# To:   const middleware = @import("middleware.zig");
```

#### 2.4 Update All References (2 hours)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Medium

```zig
// Files to update:
1. src/h3.zig:
   - pub const Middleware = @import("core/middleware.zig").Middleware;
   - pub const MiddlewareChain = @import("core/middleware.zig").MiddlewareChain;
   - Remove FastMiddleware exports
   - Update fastMiddleware namespace to middleware

2. src/core/app.zig:
   - const FastMiddlewareChain = @import("middleware.zig").MiddlewareChain;
   - Rename fast_middlewares field to middlewares
   - Update useFast() to just use()
   - Remove use_fast_middleware config option

3. Update any other files importing fast_middleware
```

#### 2.5 Update Type Names (1 hour)
**Persona**: Backend Developer  
**Priority**: Medium  
**Risk**: Low

```zig
// In the renamed middleware.zig:
1. Rename FastMiddleware to Middleware
2. Rename FastMiddlewareChain to MiddlewareChain
3. Update CommonMiddleware references
4. Update all internal references
```

#### 2.6 Update Documentation (1 hour)
**Persona**: Technical Writer  
**Priority**: Low  
**Risk**: None

```markdown
// Update:
1. README.md examples
2. API documentation
3. Remove references to "fast" vs "traditional" middleware
4. Update CLAUDE.md
```

### Updated File Structure After Phase 2
```
src/core/
├── app.zig (updated to use single middleware system)
├── middleware.zig (renamed from fast_middleware.zig)
├── ... (other core files)
```

### Validation
- [ ] All middleware tests pass
- [ ] No references to "fast_middleware" remain
- [ ] No references to old middleware system remain
- [ ] Example applications work with new naming
- [ ] Performance benchmarks still pass

### Search and Replace Commands
```bash
# Find all references to fast_middleware
grep -r "fast_middleware" src/

# Find all references to FastMiddleware
grep -r "FastMiddleware" src/

# Find config references
grep -r "use_fast_middleware" src/

# Update imports (careful with sed or use your editor)
# From: @import("fast_middleware.zig")
# To:   @import("middleware.zig")
```

## Phase 3: Directory Structure Consolidation (Week 1, Day 5)

### Objective
Merge util/ into utils/ for consistent organization.

### Tasks

#### 3.1 Move Logger to Utils (1 hour)
**Persona**: Backend Developer  
**Priority**: Medium  
**Risk**: Low

```bash
# Commands:
mv src/util/logger.zig src/utils/logger.zig
rm -rf src/util/
```

#### 3.2 Update Logger Imports (30 minutes)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Low

```zig
// Update in libxev.zig:
const logger = @import("../../utils/logger.zig");
```

#### 3.3 Standardize Logging Approach (2 hours)
**Persona**: Backend Developer  
**Priority**: Medium  
**Risk**: Low

```zig
// Decision: Use std.log with scoped loggers
1. Update all files using custom logger
2. Remove custom logger categories
3. Use scoped loggers for categorization
```

### Validation
- [ ] Build succeeds
- [ ] Logging still works in all components
- [ ] No import errors

## Phase 4: Server Adapter Deduplication (Week 2, Days 1-3)

### Objective
Extract common HTTP handling code from server adapters.

### Tasks

#### 4.1 Create Shared Protocol Module (4 hours)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Medium

```zig
// Create src/server/protocol.zig:
pub const HttpProtocol = struct {
    pub fn parseHttpRequest(event: *H3Event, data: []const u8) !void { }
    pub fn formatHttpResponse(event: *H3Event) ![]u8 { }
    pub fn handleKeepAlive(event: *H3Event) bool { }
};
```

#### 4.2 Update Server Adapters (3 hours)
**Persona**: Backend Developer  
**Priority**: High  
**Risk**: Medium

```zig
// In both std.zig and libxev.zig:
1. Remove parseHttpRequest()
2. Remove sendHttpResponse()
3. Import and use protocol.HttpProtocol
4. Remove duplicate keep-alive logic
```

#### 4.3 Remove Unused Configurations (2 hours)
**Persona**: Backend Developer  
**Priority**: Medium  
**Risk**: Low

```zig
// In config.zig, remove:
- SSLConfig (mark as future)
- CompressionConfig (mark as future)
- RateLimitConfig (mark as future)
- Unused libxev options
```

### Validation
- [ ] Both adapters still work
- [ ] HTTP parsing is consistent
- [ ] No performance regression

## Phase 5: Configuration and Utilities Cleanup (Week 2, Days 4-5)

### Objective
Consolidate duplicate utilities and remove unused code.

### Tasks

#### 5.1 Consolidate URL Encoding/Decoding (2 hours)
**Persona**: Backend Developer  
**Priority**: Medium  
**Risk**: Low

```zig
// Actions:
1. Keep internal/url.zig as single source
2. Update utils/body.zig to import from internal/url
3. Update utils/cookie.zig to import from internal/url
4. Remove duplicate implementations
```

#### 5.2 Consolidate Content Type Handling (2 hours)
**Persona**: Backend Developer  
**Priority**: Medium  
**Risk**: Low

```zig
// Create unified content type module:
1. Merge MimeType enum from internal/mime.zig
2. Merge ContentType from utils/body.zig
3. Merge MimeTypes from http/headers.zig
4. Create single utils/content_type.zig
```

#### 5.3 Remove Unused Internal Utilities (1 hour)
**Persona**: Backend Developer  
**Priority**: Low  
**Risk**: Low

```zig
// From internal/patterns.zig, remove:
- Unused pattern compilation code
- Complex matching not used by router

// From internal/url.zig, remove:
- parseScheme()
- parseHost()
- parsePort()
```

### Validation
- [ ] All imports updated
- [ ] No duplicate code remains
- [ ] Tests still pass

## Testing Strategy

### Unit Testing
- Run existing test suite after each phase
- Add tests for new shared modules
- Ensure 100% compatibility

### Integration Testing
- Test all example applications
- Run performance benchmarks
- Validate HTTP compliance

### Regression Testing
- Compare before/after behavior
- Check memory usage patterns
- Validate error handling

## Rollback Plan

### Version Control
- Create feature branch: `cleanup/remove-redundancies`
- Commit after each phase completion
- Tag stable points

### Rollback Triggers
- Test failures that can't be fixed quickly
- Performance regression >10%
- Breaking API changes discovered

## Success Metrics

### Code Reduction
- [ ] Router code reduced by ~40%
- [ ] Server adapter duplication removed (~25% reduction)
- [ ] Single middleware system
- [ ] No duplicate utilities

### Quality Improvements
- [ ] Clearer architecture
- [ ] Better maintainability score
- [ ] Reduced cognitive complexity
- [ ] Improved test coverage

### Performance
- [ ] No performance regression
- [ ] Potential improvements from removed abstractions
- [ ] Reduced memory footprint

## Post-Cleanup Tasks

1. **Documentation Update**
   - Update architecture diagrams
   - Revise API documentation
   - Create migration guide

2. **Communication**
   - Announce breaking changes
   - Provide upgrade path
   - Document benefits

3. **Future Planning**
   - Plan SSL/TLS implementation
   - Design compression strategy
   - Consider further optimizations