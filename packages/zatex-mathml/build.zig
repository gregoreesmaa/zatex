const std = @import("std");

// zatex-mathml: parse tree -> MathML Core (KaTeX-compatible).
// Thin structural walker over the core's AST — no layout math, no
// measuring, no MetricsProvider (AGENTS.md §2). The core never
// depends back: its dist lib stays MathML-free.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zatex_dep = b.dependency("zatex", .{
        .target = target,
        .optimize = optimize,
        // This package owns the MathML C entry; the core's exports
        // would duplicate across the two archives at link time.
        .cabi = false,
    });

    const mod = b.addModule("zatex_mathml", .{
        .root_source_file = b.path("src/zatex_mathml.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("zatex", zatex_dep.module("zatex"));

    // The installed distribution libraries ship ReleaseSmall, like the
    // core: this is the ~55 KB the core sheds by not linking MathML.
    const dist_mod = b.addModule("zatex_mathml_dist", .{
        .root_source_file = b.path("src/zatex_mathml.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });
    dist_mod.addImport("zatex", zatex_dep.module("zatex"));

    const lib = b.addLibrary(.{
        .name = "zatex_mathml",
        .root_module = dist_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const dylib = b.addLibrary(.{
        .name = "zatex_mathml",
        .root_module = dist_mod,
        .linkage = .dynamic,
    });
    b.installArtifact(dylib);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
