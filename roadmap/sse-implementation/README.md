# SSE Implementation Roadmap

This roadmap outlines the implementation of Server-Sent Events (SSE) support in H3Z, enabling real-time streaming capabilities for LLM chat and other use cases.

## Overview

The implementation is divided into 5 phases:
1. **Core SSE Types** - Basic data structures and formatting
2. **Connection Abstraction** - Unified interface for adapters
3. **Adapter Integration** - Modify libxev and std adapters
4. **API Integration** - Add SSE to H3Event
5. **Testing & Examples** - Comprehensive testing and documentation

## Key Goals

- ✅ Enable server-to-client streaming over HTTP
- ✅ Support LLM token streaming use case
- ✅ Maintain backward compatibility
- ✅ Zero-allocation design where possible
- ✅ Work with both libxev and std adapters

## Timeline

Estimated completion: 2-3 days
- Phase 1: 2-3 hours
- Phase 2: 3-4 hours
- Phase 3: 6-8 hours
- Phase 4: 2-3 hours
- Phase 5: 4-6 hours

## Success Criteria

- [ ] SSE endpoints can stream for extended periods
- [ ] Memory usage remains stable during streaming
- [ ] Performance meets or exceeds 10K events/second
- [ ] Examples demonstrate LLM chat streaming
- [ ] All tests pass on both adapters

## Files to be Modified/Created

### New Files
- `src/http/sse.zig` - SSE types and utilities
- `src/server/connection.zig` - Connection abstraction
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