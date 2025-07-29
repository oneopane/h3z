# H3Z Project Index

**A comprehensive navigation guide to the H3 Zig HTTP Framework**

---

## 📋 Quick Navigation

- [Project Overview](#project-overview)
- [Architecture & Core Components](#architecture--core-components)
- [API Reference](#api-reference)
- [Examples & Usage](#examples--usage)
- [Development & Testing](#development--testing)
- [Documentation](#documentation)
- [Build System](#build-system)

---

## Project Overview

**H3Z** is a minimal, fast, and composable HTTP server framework for Zig, inspired by H3.js. It provides zero-dependency HTTP server capabilities with performance optimizations and type safety.

### Key Features
- ⚡ **Minimal & Fast**: Small core with low latency and minimal memory footprint
- 🔧 **Composable**: Modular design with tree-shakeable utilities
- 🛡️ **Type Safe**: Leverages Zig's compile-time type safety
- 📦 **Zero Dependencies**: Only uses Zig standard library and libxev for async I/O
- 🔒 **Memory Safe**: Built with Zig's memory safety guarantees
- 📡 **SSE Support**: Real-time Server-Sent Events streaming

### Project Status
**⚠️ UNSTABLE DEVELOPMENT PROJECT**
- Breaking changes are expected and acceptable
- Legacy code is actively being removed
- Focus on clean, modern implementation over compatibility
- No stability guarantees - APIs may change without notice

---

## Architecture & Core Components

### 🏗️ Core Architecture (`src/core/`)

| Component | File | Purpose | Status |
|-----------|------|---------|---------|
| **H3App** | [`app.zig`](src/core/app.zig) | Component-based application architecture | ✅ Active |
| **H3Event** | [`event.zig`](src/core/event.zig) | Central request/response context object | ✅ Active |
| **Router** | [`router.zig`](src/core/router.zig) | High-performance trie-based pattern matching | ✅ Active |
| **Configuration** | [`config.zig`](src/core/config.zig) | Hierarchical configuration system | ✅ Active |
| **Component System** | [`component.zig`](src/core/component.zig) | Registry-based component architecture | ✅ Active |

### 🚀 Performance Optimizations

| Component | File | Purpose | Performance Gain |
|-----------|------|---------|------------------|
| **EventPool** | [`event_pool.zig`](src/core/event_pool.zig) | Object pooling for H3Event instances | ~30% allocation reduction |
| **RouteCache** | [`route_cache.zig`](src/core/route_cache.zig) | LRU cache for frequently accessed routes | ~40% route lookup speedup |
| **FastMiddleware** | [`fast_middleware.zig`](src/core/fast_middleware.zig) | Optimized middleware for performance-critical paths | ~25% middleware overhead reduction |
| **MemoryManager** | [`memory_manager.zig`](src/core/memory_manager.zig) | Centralized memory management with monitoring | Memory leak detection |

### 🌐 HTTP Layer (`src/http/`)

| Component | File | Purpose |
|-----------|------|---------|
| **Methods** | [`method.zig`](src/http/method.zig) | HTTP method definitions and parsing |
| **Status Codes** | [`status.zig`](src/http/status.zig) | HTTP status code management |
| **Request** | [`request.zig`](src/http/request.zig) | Request parsing and utilities |
| **Response** | [`response.zig`](src/http/response.zig) | Response building and sending |
| **Headers** | [`headers.zig`](src/http/headers.zig) | Header management and utilities |
| **SSE** | [`sse.zig`](src/http/sse.zig) | Server-Sent Events implementation |

### 🔧 Server Adapters (`src/server/`)

| Component | File | Purpose | Use Case |
|-----------|------|---------|----------|
| **libxev Adapter** | [`adapters/libxev.zig`](src/server/adapters/libxev.zig) | High-performance async I/O | Production, high-load |
| **std Adapter** | [`adapters/std.zig`](src/server/adapters/std.zig) | Standard library implementation | Development, simple deployments |
| **SSE Connection** | [`sse_connection.zig`](src/server/sse_connection.zig) | Connection abstraction for SSE | Real-time streaming |
| **Server Config** | [`config.zig`](src/server/config.zig) | Server-level configuration | Server setup |

### 🛠️ Utilities (`src/utils/`)

| Component | File | Purpose |
|-----------|------|---------|
| **Request Utils** | [`request.zig`](src/utils/request.zig) | Request parsing and helper functions |
| **Response Utils** | [`response.zig`](src/utils/response.zig) | Response building and helper functions |
| **Security** | [`security.zig`](src/utils/security.zig) | Security headers and utilities |
| **Cookie** | [`cookie.zig`](src/utils/cookie.zig) | Cookie parsing and management |
| **Body Parser** | [`body.zig`](src/utils/body.zig) | Request body parsing utilities |
| **Middleware Utils** | [`middleware.zig`](src/utils/middleware.zig) | Common middleware implementations |
| **Proxy** | [`proxy.zig`](src/utils/proxy.zig) | Proxy and forwarding utilities |

---

## API Reference

### 🎯 Quick Start

```zig
const std = @import("std");
const h3 = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // H3App
    var app = try h3.createApp(allocator);
    defer app.deinit();

    // Routes
    _ = try app.get("/", homeHandler);
    _ = try app.post("/api/users", createUserHandler);

    // Start server
    try h3.serve(&app, .{ .port = 3000 });
}
```

### 📚 Core APIs

#### Application Creation
- `h3.createApp(allocator)` - Standard H3App with component architecture
- `h3.createProductionApp(allocator)` - Production-ready with optimizations
- `h3.createDevApp(allocator)` - Development configuration

#### HTTP Methods
- `app.get(pattern, handler)` - GET routes
- `app.post(pattern, handler)` - POST routes
- `app.put(pattern, handler)` - PUT routes
- `app.delete(pattern, handler)` - DELETE routes
- `app.patch(pattern, handler)` - PATCH routes
- `app.all(pattern, handler)` - All methods

#### Request Handling
- `h3.getParam(event, "name")` - URL parameters
- `h3.getQuery(event, "name")` - Query parameters
- `h3.getHeader(event, "name")` - Request headers
- `h3.readBody(event)` - Raw request body
- `h3.readJson(event, Type)` - Parse JSON body

#### Response Helpers
- `h3.sendText(event, text)` - Send plain text
- `h3.sendJson(event, data)` - Send JSON response
- `h3.sendHtml(event, html)` - Send HTML response
- `h3.response.ok(event, data)` - 200 OK with JSON
- `h3.response.created(event, data)` - 201 Created
- `h3.response.badRequest(event, msg)` - 400 Bad Request

#### SSE (Server-Sent Events)
- `event.startSSE()` - Start SSE stream
- `writer.writeEvent(sse_event)` - Send SSE event
- `writer.writeData(data)` - Send data event
- `writer.writeComment(comment)` - Send comment

---

## Examples & Usage

### 📁 Examples Directory (`examples/`)

| Example | File | Purpose | Complexity |
|---------|------|---------|------------|
| **Simple Server** | [`simple_server.zig`](examples/simple_server.zig) | Basic HTTP server | Beginner |
| **HTTP Server** | [`http_server.zig`](examples/http_server.zig) | Full-featured HTTP server | Intermediate |
| **REST API** | [`rest_api.zig`](examples/rest_api.zig) | RESTful API example | Intermediate |
| **Architecture Demo** | [`architecture_demo.zig`](examples/architecture_demo.zig) | Component architecture showcase | Advanced |
| **Optimized Server** | [`optimized_server.zig`](examples/optimized_server.zig) | Performance optimizations | Advanced |

### 📡 SSE Examples

| Example | File | Purpose | Use Case |
|---------|------|---------|----------|
| **SSE Minimal** | [`sse_minimal.zig`](examples/sse_minimal.zig) | Basic SSE implementation | Learning |
| **SSE Counter** | [`sse_counter.zig`](examples/sse_counter.zig) | Real-time counter updates | Live data |
| **SSE Chat** | [`sse_chat.zig`](examples/sse_chat.zig) | Chat application | Real-time messaging |
| **SSE Callback** | [`sse_callback.zig`](examples/sse_callback.zig) | Callback-based streaming | Complex flows |
| **SSE Text** | [`sse_text.zig`](examples/sse_text.zig) | Text streaming | LLM responses |

### 🔐 Advanced Examples

| Example | File | Purpose |
|---------|------|---------|
| **Auth API** | [`auth_api.zig`](examples/auth_api.zig) | Authentication and authorization |
| **File Upload** | [`file_upload.zig`](examples/file_upload.zig) | File upload handling |
| **WebSocket Chat** | [`websocket_chat.zig`](examples/websocket_chat.zig) | WebSocket implementation |

---

## Development & Testing

### 🧪 Test Structure (`tests/`)

#### Unit Tests (`tests/unit/`)
- [`simple_test.zig`](tests/unit/simple_test.zig) - Basic functionality tests
- [`basic_test.zig`](tests/unit/basic_test.zig) - Core framework tests
- [`core_test.zig`](tests/unit/core_test.zig) - Core component tests
- [`http_test.zig`](tests/unit/http_test.zig) - HTTP layer tests
- [`router_test.zig`](tests/unit/router_test.zig) - Router functionality tests
- [`server_test.zig`](tests/unit/server_test.zig) - Server adapter tests

#### Integration Tests (`tests/integration/`)
- [`routing_test.zig`](tests/integration/routing_test.zig) - End-to-end routing tests
- [`middleware_test.zig`](tests/integration/middleware_test.zig) - Middleware chain tests
- [`performance_test.zig`](tests/integration/performance_test.zig) - Performance validation
- [`sse_test.zig`](tests/integration/sse_test.zig) - SSE functionality tests

#### Performance Tests (`tests/performance/`)
- [`benchmark.zig`](tests/performance/benchmark.zig) - Core performance benchmarks
- [`sse_benchmark.zig`](tests/performance/sse_benchmark.zig) - SSE streaming benchmarks

### 🚀 Build Commands

#### Building
```bash
zig build                    # Build the project
zig build -Doptimize=ReleaseFast  # Production build
```

#### Testing
```bash
zig build test              # Run library unit tests
zig build test-all          # Show test status and run verification
zig build test-simple       # Simple functionality tests
zig build test-basic        # Basic framework tests
zig build test-unit         # Core unit tests
zig build test-integration  # Integration tests
zig build test-performance  # Performance tests
zig build test-sse          # SSE integration tests
```

#### Benchmarking
```bash
zig build benchmark         # Core performance benchmarks
zig build benchmark-sse     # SSE performance benchmarks
```

#### Running Examples
```bash
zig build run               # Default example
zig build run-sse_counter   # SSE counter example
```

### 🔧 Build Configuration

#### Logging Options
- `--log-level=debug|info|warn|err` - Set log level (default: debug)
- `--log-connection=true|false` - Enable connection logs (default: true)
- `--log-request=true|false` - Enable request logs (default: true)
- `--log-performance=true|false` - Enable performance logs (default: true)

---

## Documentation

### 📖 Documentation (`docs/`)

| Document | Purpose | Audience |
|----------|---------|----------|
| [`framework-guide.md`](docs/framework-guide.md) | Comprehensive framework guide | All users |
| [`getting-started.md`](docs/getting-started.md) | Quick start guide | Beginners |
| [`sse-streaming-guide.md`](docs/sse-streaming-guide.md) | SSE implementation guide | SSE users |
| [`arena-allocator-lesson.md`](docs/arena-allocator-lesson.md) | Memory management lessons | Advanced |
| [`header-memory-issue.md`](docs/header-memory-issue.md) | Memory issue analysis | Advanced |

### 🗺️ Roadmap (`roadmap/`)

#### SSE Implementation (`roadmap/sse-implementation/`)
- [`README.md`](roadmap/sse-implementation/README.md) - SSE implementation overview
- [`phase-checklist.md`](roadmap/sse-implementation/phase-checklist.md) - Implementation phases

#### Redundancy Refactor (`roadmap/redundancy-refactor/`)
- [`README.md`](roadmap/redundancy-refactor/README.md) - Refactoring overview
- [`redundancy-analysis.md`](roadmap/redundancy-refactor/redundancy-analysis.md) - Code analysis
- [`cleanup-redundancies.md`](roadmap/redundancy-refactor/cleanup-redundancies.md) - Cleanup strategy
- [`phase-checklist.md`](roadmap/redundancy-refactor/phase-checklist.md) - Refactoring phases

### 📋 Project Documents

- [`README.md`](README.md) - Project overview and quick start
- [`OVERVIEW.md`](OVERVIEW.md) - Detailed project overview
- [`HTTP_SERVER.md`](HTTP_SERVER.md) - HTTP server documentation
- [`WEBSITE_SETUP.md`](WEBSITE_SETUP.md) - Website setup guide
- [`CLAUDE.md`](CLAUDE.md) - Claude Code assistant instructions

---

## Build System

### 📦 Build Configuration

#### Main Build File
- [`build.zig`](build.zig) - Primary build configuration and targets
- [`build.zig.zon`](build.zig.zon) - Dependency manifest

#### Dependencies
- **libxev** - High-performance event loop for async I/O
- **Zig Standard Library** - Core language features

#### Build Targets
- **Library** (`libh3.a`) - Static library for embedding
- **Examples** - Runnable example applications  
- **Tests** - Unit, integration, and performance tests
- **Benchmarks** - Performance measurement tools

---

## Cross-References & Relationships

### 🔗 Component Dependencies

```
H3App
├── ComponentRegistry ──→ Component management
├── RouterComponent ────→ Request routing
├── MemoryManager ─────→ Memory monitoring
└── H3Config ──────────→ Configuration

H3Event (Core Context)
├── Request ───────────→ Input processing
├── Response ──────────→ Output generation
├── SSEWriter ─────────→ Streaming responses
└── Router ────────────→ Parameter extraction
```

### 🔄 Request Flow

```
1. Connection ──→ Server Adapter (libxev/std)
2. HTTP Parsing ──→ H3Event creation
3. Routing ──→ Pattern matching & parameter extraction
4. Middleware ──→ Request processing chain
5. Handler ──→ Business logic execution
6. Response ──→ Output formatting & sending
7. Cleanup ──→ Resource deallocation
```

### 📊 Performance Optimization Stack

```
Application Level:
├── H3Config.development() ──→ Optimized for dev
├── H3Config.production() ───→ Optimized for prod
└── createProductionApp() ───→ All optimizations

Framework Level:
├── EventPool ───────────────→ Object reuse
├── RouteCache ──────────────→ Lookup optimization
├── FastMiddleware ──────────→ Processing optimization
└── MemoryManager ───────────→ Allocation tracking

System Level:
├── libxev adapter ──────────→ Async I/O
├── Connection pooling ──────→ Resource efficiency
└── Zero-copy operations ────→ Memory efficiency
```

---

## File Organization Summary

```
h3z/
├── 📁 src/                     # Source code
│   ├── 📁 core/                # Core framework components
│   ├── 📁 http/                # HTTP layer implementation
│   ├── 📁 server/              # Server adapters and configuration
│   ├── 📁 utils/               # Utility functions and helpers
│   ├── 📁 internal/            # Internal utilities (URL, MIME, patterns)
│   └── 📄 root.zig             # Main library entry point
├── 📁 examples/                # Usage examples and demos
├── 📁 tests/                   # Test suite (unit, integration, performance)
├── 📁 docs/                    # Documentation and guides
├── 📁 roadmap/                 # Development roadmap and planning
├── 📄 build.zig                # Build configuration
├── 📄 build.zig.zon            # Dependency manifest
├── 📄 README.md                # Project overview
├── 📄 CLAUDE.md                # Development assistant instructions
└── 📄 PROJECT_INDEX.md         # This comprehensive index
```

**Total Files**: ~80 source files across all directories

---

## Quick Command Reference

```bash
# Development workflow
zig build test-all              # Verify all tests pass
zig build run-sse_counter       # Run SSE example
zig build benchmark             # Performance testing

# Production deployment
zig build -Doptimize=ReleaseFast -Dlog-level=info

# Development with detailed logging
zig build -Dlog-level=debug -Dlog-performance=true

# Testing specific components
zig build test-sse              # SSE functionality
zig build test-integration      # End-to-end tests
```

---

*Last updated: January 2025 | Framework Version: 0.1.0 | Zig Version: 0.14.0+*