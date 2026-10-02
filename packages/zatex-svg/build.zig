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

    // The installed distribution libraries ship ReleaseSmall, like the
    // core: this is what hosts that only lay out stop paying by not
    // linking SVG.
    const dist_mod = b.addModule("zatex_svg_dist", .{
        .root_source_file = b.path("src/zatex_svg.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });
    dist_mod.addOptions("build_options", opts);
    dist_mod.addImport("zatex", zatex_dep.module("zatex"));
    dist_mod.addImport("otmath", zatex_dep.module("otmath"));
    dist_mod.addImport("fontstack", zatex_dep.module("fontstack"));
    dist_mod.addImport("cff", zatex_dep.module("cff"));

    const lib = b.addLibrary(.{
        .name = "zatex_svg",
        .root_module = dist_mod,
        .linkage = .static,
    });
    // Windows ships both the static archive and the DLL import
    // library as `zatex_svg.lib` (core precedent in
    // `packages/zatex/build.zig`), so the static archive takes the
    // `_static` suffix there; the classic name holds everywhere else.
    if (target.result.os.tag == .windows) {
        const install_lib = b.addInstallArtifact(lib, .{ .dest_sub_path = "zatex_svg_static.lib" });
        b.getInstallStep().dependOn(&install_lib.step);
    } else {
        b.installArtifact(lib);
    }

    const dylib = b.addLibrary(.{
        .name = "zatex_svg",
        .root_module = dist_mod,
        .linkage = .dynamic,
    });
    b.installArtifact(dylib);

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
