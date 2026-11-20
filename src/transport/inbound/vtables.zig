const abi = @import("../../abi/mod.zig");

/// App-level event filter/projection VTable allowing applications to route or transform
/// `TelemetryEvent_ABI` into UI updates without reimplementing the inbound transport.
pub const EventFilterVTable = struct {
    ctx: ?*anyopaque = null,
    accept: *const fn (ctx: ?*anyopaque, ev: *const abi.TelemetryEvent_ABI) bool,
};

/// App-level custom renderer VTable keyed by `capability_id` or `mime_type` (for TUI / custom panels).
pub const RendererVTable = struct {
    ctx: ?*anyopaque = null,
    render: *const fn (ctx: ?*anyopaque, capability_id: []const u8, payload: []const u8) anyerror!void,
};

/// App-level keymap VTable binding custom shortcuts to capability IDs.
pub const KeymapEntry = struct {
    key: []const u8,
    capability_id: []const u8,
    description: []const u8 = "",
};
