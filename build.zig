const std = @import("std");

pub const PluginOptions = struct {
    name: []const u8,
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode = .dynamic,
    link_libc: bool = true,
};

fn buildPluginLib(
    b: *std.Build,
    sdk_dep: *std.Build.Dependency,
    opts: PluginOptions,
    lib_name: []const u8,
    dynamic_symbol: []const u8,
    static_symbol: []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .root_source_file = opts.root_source_file,
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libc = opts.link_libc,
    });
    mod.addImport("parabellum_sdk", sdk_dep.module("parabellum_sdk"));

    const po = b.addOptions();
    po.addOption(bool, "static_archive", opts.linkage == .static);
    po.addOption([]const u8, "manifest_symbol", if (opts.linkage == .static) static_symbol else dynamic_symbol);
    mod.addOptions("plugin_options", po);

    const lib = b.addLibrary(.{
        .linkage = opts.linkage,
        .name = lib_name,
        .root_module = mod,
    });
    if (opts.linkage == .static) {
        lib.bundle_compiler_rt = false;
    }
    return lib;
}

/// Helper for building a Task Catalog plugin (`lib<name>.so` or `.a`) against `parabellum_sdk`.
pub fn addTaskPlugin(b: *std.Build, sdk_dep: *std.Build.Dependency, opts: PluginOptions) *std.Build.Step.Compile {
    return buildPluginLib(
        b,
        sdk_dep,
        opts,
        opts.name,
        "parabellum_module_manifest",
        b.fmt("parabellum_module_{s}_manifest", .{opts.name}),
    );
}

/// Helper for building a Datasource Driver plugin (`libdriver_<name>.so` or `.a`) against `parabellum_sdk`.
pub fn addDriverPlugin(b: *std.Build, sdk_dep: *std.Build.Dependency, opts: PluginOptions) *std.Build.Step.Compile {
    return buildPluginLib(
        b,
        sdk_dep,
        opts,
        b.fmt("driver_{s}", .{opts.name}),
        "parabellum_driver_manifest",
        b.fmt("parabellum_driver_{s}_manifest", .{opts.name}),
    );
}

/// Helper for building a Kernel Extension plugin (`libext_<name>.so` or `.a`) against `parabellum_sdk`.
pub fn addExtensionPlugin(b: *std.Build, sdk_dep: *std.Build.Dependency, opts: PluginOptions) *std.Build.Step.Compile {
    return buildPluginLib(
        b,
        sdk_dep,
        opts,
        b.fmt("ext_{s}", .{opts.name}),
        "parabellum_extension_manifest",
        b.fmt("parabellum_extension_{s}_manifest", .{opts.name}),
    );
}

pub const LinkHostOptions = struct {
    lib_dir: ?std.Build.LazyPath = null,
    lib_name: []const u8 = "parabellum_host",
};

/// Links a compile step (e.g. an integration test binary using `parabellum_sdk.host.TestEngine`)
/// against a precompiled `libparabellum_host` shared library.
pub fn linkPrecompiledTestEngine(compile: *std.Build.Step.Compile, opts: LinkHostOptions) void {
    compile.root_module.link_libc = true;
    if (opts.lib_dir) |dir| {
        compile.root_module.addLibraryPath(dir);
        compile.root_module.addRPath(dir);
    }
    compile.root_module.linkSystemLibrary(opts.lib_name, .{});
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdk_mod = b.addModule("parabellum_sdk", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const run_tests = b.addRunArtifact(b.addTest(.{ .root_module = test_mod }));
    const test_step = b.step("test", "Run parabellum-sdk unit tests");
    test_step.dependOn(&run_tests.step);
    _ = sdk_mod;
}
