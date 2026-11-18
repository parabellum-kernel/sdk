const std = @import("std");
const job_mod = @import("job.zig");

pub const KeyValue = struct {
    key: []const u8,
    value: []const u8,
};

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

pub const StatusQuery = struct {
    job_id: ?u64 = null,
};

pub const ShutdownRequest = struct {
    reason: []const u8 = "",
    graceful: bool = true,
};

pub const CustomEvent = struct {
    name: []const u8,
    data_json: []const u8 = "{}",
    fields: []const KeyValue = &.{},
};

/// Extensible event kind for daemon-level inbound communication.
pub const EventKind = enum(u32) {
    job = 0,
    status = 1,
    shutdown = 2,
    custom = 3,
};

pub const EventPayload = union(EventKind) {
    job: JobItem,
    status: StatusQuery,
    shutdown: ShutdownRequest,
    custom: CustomEvent,
};

/// Unified event envelope emitted by inbound extensions (HTTP, CLI, gRPC, FS diff)
/// toward the Engine Daemon. Supports typed built-in events (`job`, `status`, `shutdown`)
/// as well as extensible `custom` events with variable key-value fields or JSON data.
pub const DaemonEvent = struct {
    source: []const u8 = "unknown",
    timestamp_ns: u64 = 0,
    payload: EventPayload,

    pub fn fromJob(source: []const u8, item: JobItem) DaemonEvent {
        return .{ .source = source, .payload = .{ .job = item } };
    }

    pub fn statusQuery(source: []const u8, job_id: ?u64) DaemonEvent {
        return .{ .source = source, .payload = .{ .status = .{ .job_id = job_id } } };
    }

    pub fn shutdown(source: []const u8, reason: []const u8) DaemonEvent {
        return .{ .source = source, .payload = .{ .shutdown = .{ .reason = reason } } };
    }

    pub fn custom(source: []const u8, name: []const u8, data_json: []const u8, fields: []const KeyValue) DaemonEvent {
        return .{
            .source = source,
            .payload = .{ .custom = .{ .name = name, .data_json = data_json, .fields = fields } },
        };
    }

    pub fn kind(self: DaemonEvent) EventKind {
        return std.meta.activeTag(self.payload);
    }
};

pub const JobStatus = job_mod.JobStatus;
pub const JobRecord = job_mod.JobRecord;
