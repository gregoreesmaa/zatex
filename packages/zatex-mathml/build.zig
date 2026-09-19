const std = @import("std");

// zatex-mathml: parse tree -> MathML Core (KaTeX-compatible).
// Thin structural walker over the core's AST — no layout math, no
// measuring, no MetricsProvider (AGENTS.md §2). The core never
// depends back: its dist lib stays MathML-free.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Same profile switch as the core: `subset` keeps the bare MathML
    // envelope (reduced scope); `full` is the complete emitter.
    const profile = b.option(
        []const u8,
        "profile",
        "Build profile: subset (embeddable) or full (default)",
    ) orelse "full";

    const options = b.addOptions();
    options.addOption([]const u8, "profile", profile);
    // Marker: the core's own options step carries exactly `{profile}`,
    // so without this the two generated option files are byte-identical
    // and the build rejects the same file in two modules. The emitter
    // ignores it; profiles still agree via the forwarded `-Dprofile`.
    options.addOption(bool, "zatex_mathml_emitter", true);

    const zatex_dep = b.dependency("zatex", .{
        .target = target,
        .optimize = optimize,
        .profile = profile,
        // This package owns the MathML C entry; the core's exports
        // would duplicate across the two archives at link time.
        .cabi = false,
    });

    const mod = b.addModule("zatex_mathml", .{
        .root_source_file = b.path("src/zatex_mathml.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);
    mod.addImport("zatex", zatex_dep.module("zatex"));

    // The installed distribution libraries ship ReleaseSmall, like the
    // core: this is the ~55 KB the core sheds by not linking MathML.
    const dist_mod = b.addModule("zatex_mathml_dist", .{
        .root_source_file = b.path("src/zatex_mathml.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });
    dist_mod.addOptions("build_options", options);
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

    // Subset-profile envelope probe: the bare-envelope branch is
    // comptime-dead under `full`, so it gets its own test root compiled
    // with subset options (never linked into either library).
    const subset_options = b.addOptions();
    subset_options.addOption([]const u8, "profile", @as([]const u8, "subset"));
    const subset_lib_mod = b.addModule("zatex_mathml_subset_lib", .{
        .root_source_file = b.path("src/zatex_mathml.zig"),
        .target = target,
        .optimize = optimize,
    });
    subset_lib_mod.addOptions("build_options", subset_options);
    subset_lib_mod.addImport("zatex", zatex_dep.module("zatex"));
    const subset_test_mod = b.addModule("zatex_mathml_subset_tests", .{
        .root_source_file = b.path("src/subset_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    subset_test_mod.addImport("zatex_mathml", subset_lib_mod);
    subset_test_mod.addImport("zatex", zatex_dep.module("zatex"));
    const subset_tests = b.addTest(.{ .root_module = subset_test_mod });
    test_step.dependOn(&b.addRunArtifact(subset_tests).step);
}
