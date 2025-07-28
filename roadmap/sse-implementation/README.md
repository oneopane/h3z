# SSE Implementation Roadmap

This roadmap outlines the implementation of Server-Sent Events (SSE) support in H3Z, enabling real-time streaming capabilities for LLM chat and other use cases.

## Overview

The implementation is divided into 6 phases:
1. **Core SSE Types** ✅ - Basic data structures and formatting (COMPLETED)
2. **SSE Connection Abstraction** ✅ - Unified interface with streaming support (COMPLETED)
3. **Adapter SSE Support** ✅ - Enhanced libxev and std adapters for SSE (COMPLETED)
4. **H3Event SSE API** ✅ - SSE support via `event.startSSE()` (COMPLETED)
5. **Adapter-Event Integration** - Connect adapters to H3Event for full SSE flow
6. **Testing & Examples** - Comprehensive testing with performance validation

## Recent Enhancements (2025-07-28)

The roadmap has been significantly enhanced with:
- **Concrete API signatures** and error types for all interfaces
- **Specific implementation details** for Connection abstraction layer
- **Detailed adapter modifications** with exact struct definitions
- **Performance metrics** with measurable targets (10K events/sec, <10ms p99 latency)
- **Edge case handling** for disconnections, backpressure, and resource limits
- **Comprehensive test scenarios** with specific test names and validation criteria

## Key Goals

- ✅ Enable server-to-client streaming over HTTP
- ✅ Support LLM token streaming use case
- ✅ Maintain backward compatibility
- ✅ Zero-allocation design where possible
- ✅ Work with both libxev and std adapters

## Timeline

Estimated completion: 3-4 days
- Phase 1: 2-3 hours ✅
- Phase 2: 3-4 hours ✅
- Phase 3: 6-8 hours ✅
- Phase 4: 2-3 hours ✅
- Phase 5: 2-3 hours (Adapter-Event Integration)
- Phase 6: 4-6 hours (Testing & Examples)

## Success Criteria

- [ ] SSE endpoints can stream for 1+ hours without degradation
- [ ] Memory usage remains stable (<16KB per connection)
- [ ] Performance exceeds 10K events/second per connection
- [ ] p99 latency < 10ms from send to client receive
- [ ] Examples demonstrate LLM chat streaming with JSON payloads
- [ ] All tests pass on both adapters with zero memory leaks
- [ ] Graceful handling of 1000+ concurrent connections
- [ ] Proper error recovery for all disconnection scenarios

## Files to be Modified/Created

### New Files
- `src/http/sse.zig` - SSE types and utilities
- `src/server/sse_connection.zig` - SSE connection abstraction
- `examples/sse_chat.zig` - LLM streaming example
- `examples/sse_basic.zig` - Basic SSE example
- `tests/integration/sse_test.zig` - SSE tests

### Modified Files
- `src/core/event.zig` - Add startSSE method
- `src/server/adapters/libxev.zig` - Streaming support
- `src/server/adapters/std.zig` - Streaming support
- `src/http/headers.zig` - Add SSE headers

## Next Steps

See [phase-checklist.md](./phase-checklist.md) for detailed implementation steps.