pub const ShutdownRequest = struct {
    reason: []const u8 = "",
    graceful: bool = true,
};
