const std = @import("std");
const EventKind = @import("EventKind.zig").EventKind;
const EventPayload = @import("EventPayload.zig").EventPayload;
const JobItem = @import("JobItem.zig").JobItem;
const JobBatch = @import("JobBatch.zig").JobBatch;
const KeyValue = @import("KeyValue.zig").KeyValue;

/// Unified event envelope emitted by inbound extensions (HTTP, CLI, gRPC, FS diff)
/// toward the Engine Daemon. Supports typed built-in events (`job`, `job_batch`, `status`, `shutdown`)
/// as well as extensible `custom` events with variable key-value fields or JSON data.
pub const DaemonEvent = struct {
    source: []const u8 = "unknown",
    timestamp_ns: u64 = 0,
    payload: EventPayload,

    pub fn fromJob(source: []const u8, item: JobItem) DaemonEvent {
        return .{ .source = source, .payload = .{ .job = item } };
    }

    pub fn fromJobBatch(source: []const u8, batch: JobBatch) DaemonEvent {
        return .{ .source = source, .payload = .{ .job_batch = batch } };
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
