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
}
