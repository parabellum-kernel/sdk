const std = @import("std");
const event = @import("../event/mod.zig");

pub const KeyValue = event.KeyValue;

pub const FieldType = enum {
    int64,
    uint64,
    float64,
    bool,
    text,
    bytes,
    timestamp,
    json,
    enum_type,
    file_path,
    dir_path,
    secret,
};

pub const FieldSpec = struct {
    name: []const u8,
    label: ?[]const u8 = null,
    description: ?[]const u8 = null,
    field_type: FieldType = .text,
    required: bool = true,
    default_value: ?[]const u8 = null,
    enum_values: []const []const u8 = &.{},
    min_value: ?f64 = null,
    max_value: ?f64 = null,
    pattern: ?[]const u8 = null,
};

pub const ExecutionMode = enum {
    sync_fast,
    async_job,
    stream,
};

pub const OutputKind = enum {
    none,
    scalar,
    record,
    table,
    tree,
    document,
    media_blob,
    log_stream,
};

pub const OutputSpec = struct {
    kind: OutputKind = .none,
    mime_type: ?[]const u8 = null,
    mime_field: ?[]const u8 = null,
    fields: []const FieldSpec = &.{},
};

pub const ActionParamMap = struct {
    target_input: []const u8,
    source_field: []const u8,
};

pub const ActionLink = struct {
    label: []const u8,
    capability_id: []const u8,
    condition_field: ?[]const u8 = null,
    condition_equals: ?[]const u8 = null,
    param_map: []const ActionParamMap = &.{},
};

pub const CapabilityTargetKind = enum {
    pipeline,
    command,
    daemon_event,
};

pub const CapabilitySpec = struct {
    id: []const u8,
    group: []const u8 = "default",
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    target_kind: CapabilityTargetKind = .pipeline,
    /// Pipeline name (`JobItem.pipeline`), custom command name, or `DaemonEvent` name.
    target: ?[]const u8 = null,
    execution_mode: ExecutionMode = .sync_fast,
    accepts_batch: bool = false,
    input_stream: bool = false,
    inputs: []const FieldSpec = &.{},
    output: OutputSpec = .{},
    actions: []const ActionLink = &.{},
    hints: []const KeyValue = &.{},
};

pub const EventSpec = struct {
    topic: []const u8,
    description: ?[]const u8 = null,
    fields: []const FieldSpec = &.{},
};

pub const CapabilityCatalog = struct {
    id: []const u8,
    name: []const u8,
    version: []const u8 = "0.1.0",
    description: ?[]const u8 = null,
    capabilities: []const CapabilitySpec = &.{},
    events: []const EventSpec = &.{},
    hints: []const KeyValue = &.{},

    pub fn getCapability(self: CapabilityCatalog, id: []const u8) ?CapabilitySpec {
        for (self.capabilities) |cap| {
            if (std.mem.eql(u8, cap.id, id)) return cap;
        }
        return null;
    }

    pub fn getEvent(self: CapabilityCatalog, topic: []const u8) ?EventSpec {
        for (self.events) |ev| {
            if (std.mem.eql(u8, ev.topic, topic)) return ev;
        }
        return null;
    }
};

/// Serializes a `CapabilityCatalog` into compact JSON.
pub fn toJson(alloc: std.mem.Allocator, catalog: CapabilityCatalog) ![]u8 {
    return try std.json.Stringify.valueAlloc(alloc, catalog, .{
        .emit_null_optional_fields = false,
    });
}

/// Parses a `CapabilityCatalog` from JSON, ignoring unknown fields for forward compatibility.
pub fn fromJson(alloc: std.mem.Allocator, json_bytes: []const u8) !std.json.Parsed(CapabilityCatalog) {
    return try std.json.parseFromSlice(CapabilityCatalog, alloc, json_bytes, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

test "CapabilityCatalog JSON round-trip preserves fields, target, actions and ignores unknown fields" {
    const alloc = std.testing.allocator;

    const catalog = CapabilityCatalog{
        .id = "vault",
        .name = "Parabellum Vault",
        .version = "0.2.0",
        .description = "Encrypted VFS over cloud drives",
        .capabilities = &.{
            .{
                .id = "vfs.list",
                .group = "vfs",
                .title = "List Directory",
                .target_kind = .pipeline,
                .target = "ls",
                .execution_mode = .sync_fast,
                .inputs = &.{
                    .{
                        .name = "path",
                        .field_type = .dir_path,
                        .required = false,
                        .default_value = "/",
                    },
                },
                .output = .{
                    .kind = .tree,
                    .fields = &.{
                        .{ .name = "node_id", .field_type = .text },
                        .{ .name = "name", .field_type = .text },
                    },
                },
                .actions = &.{
                    .{
                        .label = "Read File",
                        .capability_id = "vfs.read",
                        .condition_field = "kind",
                        .condition_equals = "file",
                        .param_map = &.{
                            .{ .target_input = "node_id", .source_field = "node_id" },
                        },
                    },
                },
                .hints = &.{
                    .{ .key = "http.method", .value = "GET" },
                },
            },
        },
        .events = &.{
            .{
                .topic = "job.progress",
                .description = "Progress update for async jobs",
                .fields = &.{
                    .{ .name = "percent", .field_type = .uint64 },
                },
            },
        },
    };

    const json_bytes = try toJson(alloc, catalog);
    defer alloc.free(json_bytes);

    var parsed = try fromJson(alloc, json_bytes);
    defer parsed.deinit();

    const rt = parsed.value;
    try std.testing.expectEqualStrings("vault", rt.id);
    try std.testing.expectEqualStrings("0.2.0", rt.version);
    const cap = rt.getCapability("vfs.list").?;
    try std.testing.expectEqual(CapabilityTargetKind.pipeline, cap.target_kind);
    try std.testing.expectEqualStrings("ls", cap.target.?);
    try std.testing.expectEqual(OutputKind.tree, cap.output.kind);
    try std.testing.expectEqual(@as(usize, 1), cap.actions.len);
    try std.testing.expectEqualStrings("vfs.read", cap.actions[0].capability_id);
    try std.testing.expectEqualStrings("node_id", cap.actions[0].param_map[0].target_input);
    try std.testing.expect(rt.getEvent("job.progress") != null);

    // Unknown fields must be ignored cleanly
    const with_extra =
        \\{"id":"x","name":"X","future_field":123,"capabilities":[{"id":"c","future_nested":{"a":1}}]}
    ;
    var parsed_extra = try fromJson(alloc, with_extra);
    defer parsed_extra.deinit();
    try std.testing.expectEqualStrings("x", parsed_extra.value.id);
    try std.testing.expectEqualStrings("c", parsed_extra.value.capabilities[0].id);
}
