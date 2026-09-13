const std = @import("std");

// zatex-png: LaTeX -> PNG screenshots. One backend per OS (see
// src/backend.zig): CoreGraphics on Apple OSes, the portable software
// rasterizer everywhere else. The layout core stays portable.
// See README.md.
//
// -Dbackend=auto|cg|software selects the backend (default auto).
// Link requirements per OS (declared next to the backend choice):
//   macOS/iOS + cg ....... CoreGraphics, CoreText, ImageIO,
//                          CoreFoundation (system frameworks; iOS needs
//                          the Xcode iOS SDK at compile time).
//   macOS/iOS + software . libc only (already linked below).
//   linux/windows/android  libc only (already linked below) — the
//                          software backend has zero host dependencies,
//                          which is what makes cross-compiles from any
//                          host link without an SDK or sysroot.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const backend_opt = b.option([]const u8, "backend", "rendering backend: auto|cg|software (default auto)") orelse "auto";

    const tag = target.result.os.tag;
    const apple = tag == .macos or tag == .ios;
    const backend_is_cg = std.mem.eql(u8, backend_opt, "cg") or
        (std.mem.eql(u8, backend_opt, "auto") and apple);

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
    if (backend_is_cg) {
        mod.linkFramework("CoreGraphics", .{});
        mod.linkFramework("CoreText", .{});
        mod.linkFramework("ImageIO", .{});
        mod.linkFramework("CoreFoundation", .{});
    }

    const exe = b.addExecutable(.{
        .name = "zatex-png",
        .root_module = mod,
    });
    b.installArtifact(exe);

    const mod_tests = b.addTest(.{ .root_module = mod });
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
    if (backend_is_cg) {
        render_mod.linkFramework("CoreGraphics", .{});
        render_mod.linkFramework("CoreText", .{});
        render_mod.linkFramework("ImageIO", .{});
        render_mod.linkFramework("CoreFoundation", .{});
    }
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
}
