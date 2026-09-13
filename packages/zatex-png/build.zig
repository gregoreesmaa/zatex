const std = @import("std");

// zatex-png: LaTeX -> PNG screenshots. One backend per OS (see
// src/backend.zig); CoreGraphics serves macOS, and the layout core
// stays portable. See README.md.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Only Apple targets need system frameworks; other backends link
    // whatever their OS requires (declared alongside the backend).
    const apple = target.result.os.tag == .macos or target.result.os.tag == .ios;

    const zatex_dep = b.dependency("zatex", .{
        .target = target,
        .optimize = optimize,
        .profile = @as([]const u8, "full"),
    });

    const mod = b.addModule("zatex_png", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("zatex", zatex_dep.module("zatex"));
    mod.addImport("otmath", zatex_dep.module("otmath"));
    if (apple) {
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
    render_mod.addImport("zatex", zatex_dep.module("zatex"));
    render_mod.addImport("otmath", zatex_dep.module("otmath"));
    if (apple) {
        render_mod.linkFramework("CoreGraphics", .{});
        render_mod.linkFramework("CoreText", .{});
        render_mod.linkFramework("ImageIO", .{});
        render_mod.linkFramework("CoreFoundation", .{});
    }
    const render_tests = b.addTest(.{ .root_module = render_mod });
    test_step.dependOn(&b.addRunArtifact(render_tests).step);
}
