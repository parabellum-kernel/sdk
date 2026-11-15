const std = @import("std");
const SemVer_ABI = @import("semver_abi.zig").SemVer_ABI;

pub const PluginKind_ABI = enum(u32) {
    driver = 0,
    extension = 1,
};

/// Declares a runtime driver or extension required by an application module.
pub const PluginRequirement_ABI = extern struct {
    kind: PluginKind_ABI = .driver,
    name: [*:0]const u8,
    min_version: SemVer_ABI = .{ .major = 1, .minor = 0, .patch = 0 },
    /// Optional custom release/package URI (null = official parabellum-kernel/{driver,extension} release).
    package_uri: ?[*:0]const u8 = null,

    pub fn nameSlice(self: PluginRequirement_ABI) []const u8 {
        return std.mem.span(self.name);
    }

    pub fn packageUriSlice(self: PluginRequirement_ABI) ?[]const u8 {
        if (self.package_uri) |uri| return std.mem.span(uri);
        return null;
    }
};
