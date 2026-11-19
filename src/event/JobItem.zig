const std = @import("std");
const KeyValue = @import("KeyValue.zig").KeyValue;

pub const JobItem = struct {
    id: []const u8 = "",
    pipeline: []const u8 = "",
    async: bool = false,
    payload_json: []const u8 = "{}",
    params: []const KeyValue = &.{},

    pub fn getParam(self: JobItem, key: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, key, "id")) return self.id;
        if (std.mem.eql(u8, key, "pipeline")) return self.pipeline;
        for (self.params) |p| {
            if (std.mem.eql(u8, p.key, key)) return p.value;
        }
        return null;
    }
};
