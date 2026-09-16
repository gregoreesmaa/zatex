const std = @import("std");

// zatex-png: LaTeX -> PNG screenshots. One backend per OS (see
// src/backend.zig): CoreGraphics on Apple OSes, the portable software
// rasterizer everywhere else. The layout core stays portable.
// See README.md.
//
// -Dbackend=auto|cg|software|native selects the backend (default
// auto: CoreGraphics on Apple OSes, software elsewhere; `native`
// selects the per-OS native rasterizer — CoreGraphics on Apple,
// GDI on Windows, fontconfig/FreeType on Linux — and stays opt-in
// so the deterministic software backend remains the default).
// Link requirements per OS (declared next to the backend choice):
//   macOS/iOS + cg ....... CoreGraphics, CoreText, ImageIO,
//                          CoreFoundation (system frameworks; iOS needs
//                          the Xcode iOS SDK at compile time).
//   macOS/iOS + software . libc only (already linked below).
//   windows + native ..... + gdi32 (system DLL, cross-linkable via
//                          bundled mingw import libs — no SDK).
//   linux + native ....... no new link requirements: fontconfig and
//                          FreeType load at RUNTIME via dlopen, so
//                          cross-compiles still link without a sysroot
//                          and machines without the libraries keep
//                          working (native load fails honestly).
//   linux/windows/android + software: libc only (already linked
//                          below) — zero host dependencies, which is
//                          what makes cross-compiles from any host
//                          link without an SDK or sysroot.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const backend_opt = b.option([]const u8, "backend", "rendering backend: auto|cg|software|native (default auto)") orelse "auto";

    const tag = target.result.os.tag;
    const apple = tag == .macos or tag == .ios;
    const backend_is_cg = std.mem.eql(u8, backend_opt, "cg") or
        (std.mem.eql(u8, backend_opt, "auto") and apple) or
        (std.mem.eql(u8, backend_opt, "native") and apple);
    const backend_is_win_native = std.mem.eql(u8, backend_opt, "native") and tag == .windows;

    const zatex_dep = b.dependency("zatex", .{
        .target = target,
        .optimize = optimize,
        .profile = @as([]const u8, "full"),
    });

    const opts = b.addOptions();
    opts.addOption([]const u8, "backend", backend_opt);
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

    const mod = b.addModule("zatex_png", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addOptions("build_options", opts);
    mod.addImport("zatex", zatex_dep.module("zatex"));
    mod.addImport("otmath", zatex_dep.module("otmath"));
    mod.addImport("fontstack", zatex_dep.module("fontstack"));
    if (backend_is_cg) {
        mod.linkFramework("CoreGraphics", .{});
        mod.linkFramework("CoreText", .{});
        mod.linkFramework("ImageIO", .{});
        mod.linkFramework("CoreFoundation", .{});
    }
    if (backend_is_win_native) mod.linkSystemLibrary("gdi32", .{});

    const exe = b.addExecutable(.{
        .name = "zatex-png",
        .root_module = mod,
    });
    b.installArtifact(exe);

    // Portable-CLI unit tests (main.zig root): separate module from the
    // exe's `mod` so Apple test binaries can link the system frameworks
    // the exe itself must NOT take (macOS/iOS + software stays libc-only
    // so cross-compiles link without an SDK). Needed whatever `-Dbackend`
    // selects: the import chain always reaches sw_backend.zig, whose
    // CoreText cross-check test emits CoreGraphics symbols on Apple
    // hosts (same rule as sw_mod/nmod).
    const mod_test_mod = b.addModule("zatex_png_mod_tests", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod_test_mod.addOptions("build_options", opts);
    mod_test_mod.addImport("zatex", zatex_dep.module("zatex"));
    mod_test_mod.addImport("otmath", zatex_dep.module("otmath"));
    mod_test_mod.addImport("fontstack", zatex_dep.module("fontstack"));
    if (apple) {
        mod_test_mod.linkFramework("CoreGraphics", .{});
        mod_test_mod.linkFramework("CoreText", .{});
        mod_test_mod.linkFramework("ImageIO", .{});
        mod_test_mod.linkFramework("CoreFoundation", .{});
    }
    if (backend_is_win_native) mod_test_mod.linkSystemLibrary("gdi32", .{});
    const mod_tests = b.addTest(.{ .root_module = mod_test_mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests (pure logic; rendering is exercised via the CLI)");
    test_step.dependOn(&run_mod_tests.step);

    // Coordinate-mapping tests for the portable mapping in
    // `render.zig`. Separate root (per core convention) so they run
    // under the same `test` step; needs the same frameworks to link.
    const render_mod = b.addModule("zatex_png_render", .{
        .root_source_file = b.path("src/render.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    render_mod.addOptions("build_options", opts);
    render_mod.addImport("zatex", zatex_dep.module("zatex"));
    render_mod.addImport("otmath", zatex_dep.module("otmath"));
    render_mod.addImport("fontstack", zatex_dep.module("fontstack"));
    if (backend_is_cg) {
        render_mod.linkFramework("CoreGraphics", .{});
        render_mod.linkFramework("CoreText", .{});
        render_mod.linkFramework("ImageIO", .{});
        render_mod.linkFramework("CoreFoundation", .{});
    }
    if (backend_is_win_native) render_mod.linkSystemLibrary("gdi32", .{});
    const render_tests = b.addTest(.{ .root_module = render_mod });
    test_step.dependOn(&b.addRunArtifact(render_tests).step);

    // Software-backend unit tests (CFF interpreter, rasterizer, PNG,
    // CoreText cross-check): run under every `-Dbackend` setting so the
    // rasterizer is covered even on CoreGraphics-default hosts. The
    // module is backend-agnostic (it never imports backend.zig); the
    // CoreText cross-check inside prunes itself off-Apple at comptime.
    const sw_mod = b.addModule("zatex_png_sw", .{
        .root_source_file = b.path("src/sw_backend.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sw_mod.addOptions("build_options", opts);
    if (apple) {
        sw_mod.linkFramework("CoreGraphics", .{});
        sw_mod.linkFramework("CoreText", .{});
        sw_mod.linkFramework("ImageIO", .{});
        sw_mod.linkFramework("CoreFoundation", .{});
    }
    const sw_tests = b.addTest(.{ .root_module = sw_mod });
    test_step.dependOn(&b.addRunArtifact(sw_tests).step);

    // Native-backend unit tests (issues #64/#65): the OS files are
    // only *linked* into their OS builds, but their pure-logic tests
    // (name-table parse, dlopen probing, graceful degradation) run on
    // every host; OS-gated tests skip themselves elsewhere. The files
    // import build_options + sibling backends only, so the roots below
    // stay link-clean on all hosts (Windows-only GDI calls prune at
    // comptime; FreeType/fontconfig bind at runtime via dlopen).
    for ([_]struct { name: []const u8, file: []const u8 }{
        .{ .name = "zatex_png_win", .file = "src/windows_backend.zig" },
        .{ .name = "zatex_png_linux", .file = "src/linux_backend.zig" },
    }) |m| {
        const nmod = b.addModule(m.name, .{
            .root_source_file = b.path(m.file),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        nmod.addOptions("build_options", opts);
        nmod.addImport("zatex", zatex_dep.module("zatex"));
        nmod.addImport("otmath", zatex_dep.module("otmath"));
        // Sibling-backend imports reference CoreGraphics on Apple
        // hosts whatever `-Dbackend` selects (same rule as sw_mod).
        if (apple) {
            nmod.linkFramework("CoreGraphics", .{});
            nmod.linkFramework("CoreText", .{});
            nmod.linkFramework("ImageIO", .{});
            nmod.linkFramework("CoreFoundation", .{});
        }
        if (backend_is_win_native) nmod.linkSystemLibrary("gdi32", .{});
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = nmod })).step);
    }
}
