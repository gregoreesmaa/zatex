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
        // Shipped-artifact diet (issue #288, core precedent): strip the
        // debug info that otherwise rides the static archive.
        .strip = true,
    });
    dist_mod.addImport("zatex", zatex_dep.module("zatex"));

    const lib = b.addLibrary(.{
        .name = "zatex_mathml",
        .root_module = dist_mod,
        .linkage = .static,
    });
    // No LTO on the static dist lib (issue #288): same COFF/bitcode
    // measurement as the core — LTO grows archives, so strip (above)
    // is the static diet.
    // Windows ships both the static archive and the DLL import
    // library as `zatex_mathml.lib` (core precedent in
    // `packages/zatex/build.zig`), so the static archive takes the
    // `_static` suffix there; the classic name holds everywhere else.
    if (target.result.os.tag == .windows) {
        const install_lib = b.addInstallArtifact(lib, .{ .dest_sub_path = "zatex_mathml_static.lib" });
        b.getInstallStep().dependOn(&install_lib.step);
    } else {
        b.installArtifact(lib);
    }

    const dylib = b.addLibrary(.{
        .name = "zatex_mathml",
        .root_module = dist_mod,
        .linkage = .dynamic,
    });
    // Same diet as the static dist lib (issue #288). LTO only
    // where the linker supports it: Mach-O links without LLD by
    // default, so `-flto=full` errors there ("LTO requires using
    // LLD"); ELF/COFF go through LLD and link fine. Core precedent
    // in `packages/zatex/build.zig` (CI `test` job builds both dist
    // libs via `tools/check_dist_closure.sh`).
    if (target.result.os.tag != .macos) dylib.lto = .full;
    b.installArtifact(dylib);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
