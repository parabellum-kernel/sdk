const KeyValue = @import("KeyValue.zig").KeyValue;

pub const CustomEvent = struct {
    name: []const u8,
    data_json: []const u8 = "{}",
    fields: []const KeyValue = &.{},
};
