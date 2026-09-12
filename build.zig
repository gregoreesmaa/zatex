const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Build profile: `subset` compiles the embeddable core only (what
    // `read` will one day link — budgeted at <= 8 KB host __TEXT);
    // `full` compiles the complete KaTeX-compatible engine.
    const profile = b.option(
        []const u8,
        "profile",
        "Build profile: subset (embeddable) or full (default)",
    ) orelse "full";

    const options = b.addOptions();
    options.addOption([]const u8, "profile", profile);

    const mod = b.addModule("zatex", .{
        .root_source_file = b.path("src/zatex.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);

    const lib = b.addLibrary(.{
        .name = "zatex",
        .root_module = mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Host-side OpenType reader tests (metrics tooling, not the core).
    const otmath_mod = b.addModule("otmath", .{
        .root_source_file = b.path("src/otmath.zig"),
        .target = target,
        .optimize = optimize,
    });
    const otmath_tests = b.addTest(.{ .root_module = otmath_mod });
    const run_otmath_tests = b.addRunArtifact(otmath_tests);
    test_step.dependOn(&run_otmath_tests.step);

    // Reference-host probes: core driven by the real font (test-only).
    const refhost_mod = b.addModule("refhost", .{
        .root_source_file = b.path("src/refhost.zig"),
        .target = target,
        .optimize = optimize,
    });
    refhost_mod.addImport("zatex", mod);
    const otm = b.addModule("otmath_link", .{
        .root_source_file = b.path("src/otmath.zig"),
        .target = target,
        .optimize = optimize,
    });
    refhost_mod.addImport("otmath", otm);
    const refhost_tests = b.addTest(.{ .root_module = refhost_mod });
    const run_refhost_tests = b.addRunArtifact(refhost_tests);
    test_step.dependOn(&run_refhost_tests.step);

    // Differential parity against the pinned-KaTeX sweep goldens.
    const parity_mod = b.addModule("parity", .{
        .root_source_file = b.path("src/parity.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_mod.addImport("zatex", mod);
    const parity_tests = b.addTest(.{ .root_module = parity_mod });
    const run_parity_tests = b.addRunArtifact(parity_tests);
    run_parity_tests.setCwd(b.path("."));
    test_step.dependOn(&run_parity_tests.step);
}
