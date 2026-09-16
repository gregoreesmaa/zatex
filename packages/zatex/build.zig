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

    // Dynamic plugin artifact (issue 12): hosts like `read` load the
    // subset profile at RUNTIME via dlopen (`libzatex.dylib` built with
    // `-Dprofile=subset`), never at link time — plugins live outside
    // host size budgets, and an absent dylib is a clean fallback.
    const dylib = b.addLibrary(.{
        .name = "zatex",
        .root_module = mod,
        .linkage = .dynamic,
    });
    b.installArtifact(dylib);

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

    // Shared layout-invariant helpers (test-only, never in the core).
    const invariants_mod = b.addModule("invariants", .{
        .root_source_file = b.path("src/invariants.zig"),
        .target = target,
        .optimize = optimize,
    });
    invariants_mod.addImport("zatex", mod);
    const invariants_tests = b.addTest(.{ .root_module = invariants_mod });
    const run_invariants_tests = b.addRunArtifact(invariants_tests);
    test_step.dependOn(&run_invariants_tests.step);

    // Reference-host probes: core driven by the real font (test-only).
    const refhost_mod = b.addModule("refhost", .{
        .root_source_file = b.path("src/refhost.zig"),
        .target = target,
        .optimize = optimize,
    });
    refhost_mod.addImport("zatex", mod);
    refhost_mod.addImport("invariants", invariants_mod);
    const otm = b.addModule("otmath_link", .{
        .root_source_file = b.path("src/otmath.zig"),
        .target = target,
        .optimize = optimize,
    });
    refhost_mod.addImport("otmath", otm);
    const refhost_tests = b.addTest(.{ .root_module = refhost_mod });
    const run_refhost_tests = b.addRunArtifact(refhost_tests);
    test_step.dependOn(&run_refhost_tests.step);

    // Speech strings + copy-as-LaTeX serializer (host-side walkers).
    const speech_mod = b.addModule("speech", .{
        .root_source_file = b.path("src/speech.zig"),
        .target = target,
        .optimize = optimize,
    });
    speech_mod.addImport("zatex", mod);
    const speech_tests = b.addTest(.{ .root_module = speech_mod });
    const run_speech_tests = b.addRunArtifact(speech_tests);
    test_step.dependOn(&run_speech_tests.step);
    const texser_mod = b.addModule("texser", .{
        .root_source_file = b.path("src/texser.zig"),
        .target = target,
        .optimize = optimize,
    });
    texser_mod.addImport("zatex", mod);
    const texser_tests = b.addTest(.{ .root_module = texser_mod });
    const run_texser_tests = b.addRunArtifact(texser_tests);
    test_step.dependOn(&run_texser_tests.step);

    // Fixed-seed grammar fuzzer (test-only, zero-dependency).
    const fuzz_mod = b.addModule("fuzz", .{
        .root_source_file = b.path("src/fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    fuzz_mod.addImport("zatex", mod);
    fuzz_mod.addImport("invariants", invariants_mod);
    const fuzz_tests = b.addTest(.{ .root_module = fuzz_mod });
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);
    test_step.dependOn(&run_fuzz_tests.step);

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

    // Gallery renderer (issue 13): corpus -> browsable MathML HTML.
    // Informational eyeball aid only, never a required gate.
    // Path is repo-root-relative: this build file lives in packages/zatex.
    const gallery_mod = b.addModule("gallery", .{
        .root_source_file = b.path("../../tools/gallery.zig"),
        .target = target,
        .optimize = optimize,
    });
    gallery_mod.addImport("zatex", mod);
    const gallery_exe = b.addExecutable(.{
        .name = "gallery",
        .root_module = gallery_mod,
    });
    const install_gallery = b.addInstallArtifact(gallery_exe, .{});
    const gallery_step = b.step("gallery", "Render the corpus gallery HTML (informational, never a gate)");
    gallery_step.dependOn(&install_gallery.step);

    // ---- QA coverage module (issues #40-48; test-only, appended) ----
    // `qa` (full profile) owns issues #40-48 plus the full half of the
    // #45 profile-equality probe; `qa_subset` (subset profile, separate
    // binary — one source file per module per compilation) owns the
    // subset half over the shared `goldens/qa_profile_ir.json`.
    const qa_mod = b.addModule("qa", .{
        .root_source_file = b.path("src/qa.zig"),
        .target = target,
        .optimize = optimize,
    });
    qa_mod.addImport("zatex", mod);
    qa_mod.addImport("invariants", invariants_mod);
    qa_mod.addImport("speech", speech_mod);
    qa_mod.addImport("texser", texser_mod);
    // Filtered to this module's own tests: the binary also links the
    // engine (full profile), whose suite runs in its own targets.
    const qa_tests = b.addTest(.{
        .root_module = qa_mod,
        .filters = &.{ "qa40", "qa41", "qa42", "qa43", "qa44", "qa45", "qa46", "qa47", "qa48", "qa49", "qa50", "qa51", "qa52", "qa53", "qa54", "qa55", "qa56", "qa57", "qa58", "qa59", "qa60", "qa61", "qa62", "qa63", "qa64", "qa65", "qa66", "qa67", "qa68", "qa69", "qa70", "qa71", "qa72", "qa73", "qa74", "qa75", "qa76", "qa77", "qa78", "qa79", "qa80", "qa81", "qa82", "qa83", "qa84", "qa dump" },
    });
    const run_qa_tests = b.addRunArtifact(qa_tests);
    run_qa_tests.setCwd(b.path("."));
    test_step.dependOn(&run_qa_tests.step);
    const qa_subset_options = b.addOptions();
    qa_subset_options.addOption([]const u8, "profile", @as([]const u8, "subset"));
    const qa_subset_mod = b.addModule("qa_subset", .{
        .root_source_file = b.path("src/qa_subset.zig"),
        .target = target,
        .optimize = optimize,
    });
    qa_subset_mod.addOptions("build_options", qa_subset_options);
    // Filtered to the subset probes: the binary links the engine
    // sources (subset profile), whose full-profile tests must NOT run
    // here (full-only constructs honestly fail under subset gates).
    const qa_subset_tests = b.addTest(.{
        .root_module = qa_subset_mod,
        .filters = &.{ "qa45s", "subset profile" },
    });
    const run_qa_subset_tests = b.addRunArtifact(qa_subset_tests);
    run_qa_subset_tests.setCwd(b.path("."));
    test_step.dependOn(&run_qa_subset_tests.step);
    // ---- end QA coverage module ----
}
