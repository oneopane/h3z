# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

IMPORTANT: This repo uses Jujutse (jj) for version control. You MUST use jj. You MUST NOT use git.

## Project Overview

H3 is a minimal, fast, and composable HTTP server framework for Zig, inspired by H3.js. It features:
- Zero external dependencies (only uses Zig standard library and libxev for async I/O)
- Type-safe API with compile-time checks
- Memory-safe design leveraging Zig's safety guarantees
- High-performance async I/O using libxev event loop
- Component-based architecture for modularity

## Key Commands

### Building
```bash
# Build the project
zig build

# Build in release mode for production
zig build -Doptimize=ReleaseFast

# Build with custom log level and options
zig build -Dlog-level=info -Dlog-connection=false -Dlog-request=true
```

### Testing
```bash
# Run all tests
zig build test

# Run specific test categories
zig build test-simple      # Simple functionality tests
zig build test-basic       # Basic framework tests
zig build test-unit        # Core unit tests
zig build test-integration # Integration tests
zig build test-performance # Performance tests

# Run test suite overview
zig build test-all

# Run performance benchmarks
zig build benchmark
```

### Running Examples
```bash
# Run the default example server
zig build run

# Run specific examples
zig build run-http_server
zig build run-simple_server
zig build run-optimized_server
```

## Architecture Overview

### Core Components

1. **Event-Driven Core** (`src/core/`)
   - `app.zig`: Main application class with two variants:
     - `H3`: Legacy API for backward compatibility
     - `H3App`: Modern component-based architecture
   - `event.zig`: Central H3Event context object for request/response handling
   - `router.zig`: High-performance router with trie-based pattern matching
   - `middleware.zig`: Traditional middleware system
   - `fast_middleware.zig`: Optimized middleware for performance-critical paths

2. **Performance Optimizations**
   - `event_pool.zig`: Object pooling for H3Event instances to reduce allocations
   - `route_cache.zig`: LRU cache for frequently accessed routes
   - `memory_manager.zig`: Centralized memory management with monitoring
   - `compile_time_router.zig`: Compile-time route optimization

3. **Server Adapters** (`src/server/adapters/`)
   - `libxev.zig`: High-performance async I/O using libxev event loop
   - `std.zig`: Standard library-based adapter for simpler deployments

4. **HTTP Layer** (`src/http/`)
   - Type-safe HTTP methods, status codes, headers, and request/response handling
   - Idiomatic Zig patterns using tagged unions and compile-time features

### Request Flow

1. **Connection Handling**: Server adapter (libxev/std) accepts incoming connections
2. **Event Creation**: H3Event object created (from pool if enabled) with request context
3. **Routing**: Trie-based router matches URL patterns and extracts parameters
4. **Middleware Chain**: Request passes through middleware (fast or traditional)
5. **Handler Execution**: Route handler processes request and generates response
6. **Response Writing**: Response sent back through server adapter
7. **Cleanup**: Event returned to pool or deallocated

### Key Design Patterns

- **Component Architecture**: Modular design with registry-based component system
- **Zero-Copy Operations**: Minimize data copying for performance
- **Compile-Time Safety**: Extensive use of Zig's comptime features
- **Resource Pooling**: Object pools for frequently allocated resources
- **Async I/O**: Non-blocking operations using libxev event loop

## Development Guidelines

### Memory Management
- Always use the allocator passed to your component
- Return pooled objects (H3Event) properly to avoid leaks
- Use defer for cleanup operations
- Monitor memory usage through MemoryManager stats

### Error Handling
- Use Zig's error unions for fallible operations
- Provide meaningful error messages
- Handle connection errors gracefully without crashing

### Testing Approach
- Write tests using the test_utils module for consistency
- Use TestAllocator to detect memory leaks
- Test both success and error paths
- Include performance benchmarks for critical paths

### Performance Considerations
- Enable event pooling in production (`use_event_pool: true`)
- Use fast middleware for performance-critical operations
- Consider route compilation for static routes
- Monitor with built-in performance logging options

## Configuration System

The framework uses a hierarchical configuration system:
- `H3Config`: Application-level configuration
- `MemoryConfig`: Memory management settings
- `RouterConfig`: Routing behavior options
- `SecurityConfig`: Security headers and policies

Use `ConfigBuilder` for fluent configuration setup.
