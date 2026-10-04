const std = @import("std");

// zatex-svg: LaTeX math -> standalone SVG (outlined glyph paths).
// Thin geometric walker over the core's box tree — no layout math,
// no measuring. The core never depends back: its dist lib stays
// SVG-free.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zatex_dep = b.dependency("zatex", .{
        .target = target,
        .optimize = optimize,
        // This package owns no C entry this PR, but a host linking
        // libzatex.a + libzatex_svg.a must not see duplicated core
        // exports (mathml precedent).
        .cabi = false,
    });

    const opts = b.addOptions();
    // Absolute fixture-font path for tests (`@embedFile` cannot leave
    // the package, and the test runner makes no CWD promise, so tests
    // read the vendored fixture through this build-provided path).
    const fixture_font = std.fs.path.join(b.allocator, &.{
        b.build_root.path orelse ".",
        "..",
        "zatex",
        "fixtures",
        "fonts",
        "latinmodern-math.otf",
    }) catch @panic("oom joining fixture path");
    opts.addOption([]const u8, "fixture_font", fixture_font);

    const mod = b.addModule("zatex_svg", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addOptions("build_options", opts);
    mod.addImport("zatex", zatex_dep.module("zatex"));
    mod.addImport("otmath", zatex_dep.module("otmath"));
    mod.addImport("fontstack", zatex_dep.module("fontstack"));
    mod.addImport("cff", zatex_dep.module("cff"));

    const exe = b.addExecutable(.{
        .name = "zatex-svg",
        .root_module = mod,
    });
    b.installArtifact(exe);

    // No installed libraries: this package exposes no C ABI (pure
    // Zig module — `zatex_svg.zig` has no `export`ed symbols, so a
    // `libzatex_svg` archive would be a hollow shell with nothing to
    // link). Zig consumers take the module via path dependency (see
    // README.md); binary consumers take the `zatex-svg` CLI above.
    // The `libzatex_svg-*` release assets shipped by mistake in
    // v0.0.0 were empty shells with no linkable symbols and have
    // been withdrawn from the release.

    const test_mod = b.addModule("zatex_svg_tests", .{
        .root_source_file = b.path("src/zatex_svg.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addOptions("build_options", opts);
    test_mod.addImport("zatex", zatex_dep.module("zatex"));
    test_mod.addImport("otmath", zatex_dep.module("otmath"));
    test_mod.addImport("fontstack", zatex_dep.module("fontstack"));
    test_mod.addImport("cff", zatex_dep.module("cff"));

    const mod_tests = b.addTest(.{ .root_module = test_mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
