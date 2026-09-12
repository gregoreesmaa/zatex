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

    const mod = b.addModule("matex", .{
        .root_source_file = b.path("src/matex.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);

    const lib = b.addLibrary(.{
        .name = "matex",
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
    refhost_mod.addImport("matex", mod);
    const otm = b.addModule("otmath_link", .{
        .root_source_file = b.path("src/otmath.zig"),
        .target = target,
        .optimize = optimize,
    });
    refhost_mod.addImport("otmath", otm);
    const refhost_tests = b.addTest(.{ .root_module = refhost_mod });
    const run_refhost_tests = b.addRunArtifact(refhost_tests);
    test_step.dependOn(&run_refhost_tests.step);
}
