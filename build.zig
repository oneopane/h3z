const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Logging options
    const log_level = b.option(
        std.log.Level,
        "log-level",
        "Set the log level (default: debug)",
    ) orelse .debug;

    const enable_connection_logs = b.option(
        bool,
        "log-connection",
        "Enable connection logs (default: true)",
    ) orelse true;

    const enable_request_logs = b.option(
        bool,
        "log-request",
        "Enable request logs (default: true)",
    ) orelse true;

    const enable_performance_logs = b.option(
        bool,
        "log-performance",
        "Enable performance logs (default: true)",
    ) orelse true;

    // Add libxev dependency
    const libxev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add logging options as build options
    const log_options = b.addOptions();
    log_options.addOption(std.log.Level, "log_level", log_level);
    log_options.addOption(bool, "enable_connection_logs", enable_connection_logs);
    log_options.addOption(bool, "enable_request_logs", enable_request_logs);
    log_options.addOption(bool, "enable_performance_logs", enable_performance_logs);

    // Add options to module
    lib_mod.addImport("log_options", log_options.createModule());

    // Add libxev module to our library
    lib_mod.addImport("xev", libxev_dep.module("xev"));

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "h3",
        .root_module = lib_mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Export the h3 module
    const h3_module = b.addModule("h3", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add libxev dependency to the exported module
    h3_module.addImport("xev", libxev_dep.module("xev"));

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    // Add log options to test build
    lib_unit_tests.root_module.addImport("log_options", log_options.createModule());

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // ===== H3 TEST SUITE =====

    // Main test runner
    const test_all = b.addExecutable(.{
        .name = "test_all",
        .root_source_file = b.path("tests/test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_all.root_module.addImport("h3", lib_mod);
    test_all.root_module.addImport("log_options", log_options.createModule());

    // Create test_utils module for test_all
    const test_utils_mod_all = b.addModule("test_utils_all", .{
        .root_source_file = b.path("tests/test_utils.zig"),
    });
    test_utils_mod_all.addImport("h3", lib_mod);
    test_all.root_module.addImport("test_utils", test_utils_mod_all);

    const run_test_all = b.addRunArtifact(test_all);
    const test_all_step = b.step("test-all", "Show H3 framework test status and run verification");
    test_all_step.dependOn(&run_test_all.step);

    // Individual test categories
    addTestCategory(b, lib_mod, target, optimize, "simple", "tests/unit/simple_test.zig");
    addTestCategory(b, lib_mod, target, optimize, "basic", "tests/unit/basic_test.zig");
    addTestCategory(b, lib_mod, target, optimize, "unit", "tests/unit/core_test.zig");
    addTestCategory(b, lib_mod, target, optimize, "integration", "tests/integration/routing_test.zig");
    addTestCategory(b, lib_mod, target, optimize, "performance", "tests/integration/performance_test.zig");
    
    // Add SSE integration test
    const sse_integration_test = b.addTest(.{
        .root_source_file = b.path("tests/integration/sse_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    sse_integration_test.root_module.addImport("h3z", lib_mod);
    const run_sse_integration_test = b.addRunArtifact(sse_integration_test);
    const sse_test_step = b.step("test-sse", "Run SSE integration tests");
    sse_test_step.dependOn(&run_sse_integration_test.step);
    
    // Add SSE performance benchmark
    const sse_benchmark = b.addTest(.{
        .root_source_file = b.path("tests/performance/sse_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast, // Use release mode for benchmarks
    });
    sse_benchmark.root_module.addImport("h3z", lib_mod);
    const run_sse_benchmark = b.addRunArtifact(sse_benchmark);
    const sse_benchmark_step = b.step("benchmark-sse", "Run SSE performance benchmarks");
    sse_benchmark_step.dependOn(&run_sse_benchmark.step);

    // Add examples
    // Legacy H3 examples (commented out - use H3App instead)
    // addExample(b, lib_mod, target, optimize, "http_server", "examples/http_server.zig");
    // addExample(b, lib_mod, target, optimize, "simple_server", "examples/simple_server.zig");
    // addExample(b, lib_mod, target, optimize, "optimized_server", "examples/optimized_server.zig");
    // addExample(b, lib_mod, target, optimize, "rest_api", "examples/rest_api.zig");
    // addExample(b, lib_mod, target, optimize, "sse_basic", "examples/sse_basic.zig");
    // addExample(b, lib_mod, target, optimize, "sse_chat", "examples/sse_chat.zig");
    // addExample(b, lib_mod, target, optimize, "sse_proxy", "examples/sse_proxy.zig");
    // addExample(b, lib_mod, target, optimize, "sse_text", "examples/sse_text.zig");
    // addExample(b, lib_mod, target, optimize, "sse_callback", "examples/sse_callback.zig");
    // addExample(b, lib_mod, target, optimize, "sse_minimal", "examples/sse_minimal.zig");
    
    // Modern H3App examples
    addExample(b, lib_mod, target, optimize, "sse_counter", "examples/sse_counter.zig");
    // addExample(b, lib_mod, target, optimize, "websocket_chat", "examples/websocket_chat.zig");

    // Performance benchmarks
    const benchmark_tests = b.addTest(.{
        .root_source_file = b.path("tests/performance/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    benchmark_tests.root_module.addImport("h3", lib_mod);
    benchmark_tests.root_module.addImport("log_options", log_options.createModule());

    const run_benchmarks = b.addRunArtifact(benchmark_tests);
    const benchmark_step = b.step("benchmark", "Run performance benchmarks");
    benchmark_step.dependOn(&run_benchmarks.step);
}

fn addExample(
    b: *std.Build,
    lib_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    path: []const u8,
) void {
    // Create log options for this example
    const example_log_options = b.addOptions();
    example_log_options.addOption(std.log.Level, "log_level", .debug);
    example_log_options.addOption(bool, "enable_connection_logs", true);
    example_log_options.addOption(bool, "enable_request_logs", true);
    example_log_options.addOption(bool, "enable_performance_logs", true);

    const example_exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });

    example_exe.root_module.addImport("h3", lib_mod);
    example_exe.root_module.addImport("log_options", example_log_options.createModule());
    b.installArtifact(example_exe);

    const run_cmd = b.addRunArtifact(example_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step_name = b.fmt("run-{s}", .{name});
    const run_step_desc = b.fmt("Run the {s} example", .{name});
    const run_step = b.step(run_step_name, run_step_desc);
    run_step.dependOn(&run_cmd.step);
}

fn addTestCategory(
    b: *std.Build,
    lib_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    category: []const u8,
    path: []const u8,
) void {
    // Create log options for this test category
    const test_log_options = b.addOptions();
    test_log_options.addOption(std.log.Level, "log_level", .debug);
    test_log_options.addOption(bool, "enable_connection_logs", true);
    test_log_options.addOption(bool, "enable_request_logs", true);
    test_log_options.addOption(bool, "enable_performance_logs", true);

    const test_exe = b.addTest(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    test_exe.root_module.addImport("h3", lib_mod);
    test_exe.root_module.addImport("log_options", test_log_options.createModule());

    // Create test_utils module with h3 dependency
    const test_utils_mod = b.addModule("test_utils", .{
        .root_source_file = b.path("tests/test_utils.zig"),
    });
    test_utils_mod.addImport("h3", lib_mod);

    // Add test_utils to test executable
    test_exe.root_module.addImport("test_utils", test_utils_mod);

    const run_test = b.addRunArtifact(test_exe);
    const test_step_name = b.fmt("test-{s}", .{category});
    const test_step_desc = b.fmt("Run {s} tests", .{category});
    const test_step = b.step(test_step_name, test_step_desc);
    test_step.dependOn(&run_test.step);
}
