const std = @import("std");
const event = @import("../../event/mod.zig");

pub const KeyValue = event.KeyValue;

/// Idiomatic Zig request passed from an `InboundTransport` to the host dispatcher.
pub const InboundRequest = struct {
    command_or_route: []const u8,
    pipeline_yaml_path: []const u8 = "",
    payload: []const u8 = "",
    args_json: []const u8 = "{}",
};

/// Idiomatic Zig response returned by the host dispatcher.
pub const InboundResponse = struct {
    status_code: i32,
    body: []const u8,
};

/// Standard JSON result envelope for `OutputKind.scalar`.
pub const ScalarEnvelope = struct {
    value: std.json.Value,
};

/// Standard JSON result envelope for `OutputKind.record`.
pub const RecordEnvelope = struct {
    fields: []const KeyValue,
};

/// Standard JSON result envelope for `OutputKind.table`.
pub const TableEnvelope = struct {
    columns: []const []const u8,
    rows: []const []const []const u8,
};

/// Recursive node for `OutputKind.tree` results; `fields` map directly to `ActionLink.param_map`.
pub const TreeNode = struct {
    id: []const u8,
    label: []const u8,
    fields: []const KeyValue = &.{},
    children: []const TreeNode = &.{},
};

/// Standard JSON result envelope for `OutputKind.tree`.
pub const TreeEnvelope = struct {
    nodes: []const TreeNode,
};

/// Standard JSON result envelope for `OutputKind.document`.
pub const DocumentEnvelope = struct {
    mime_type: []const u8 = "text/plain",
    content: []const u8,
};
