const std = @import("std");

/// Shared lifecycle status for asynchronous daemon jobs across engine, extensions, and clients.
pub const JobStatus = enum(u32) {
    queued = 0,
    running = 1,
    completed = 2,
    failed = 3,

    pub fn isTerminal(self: JobStatus) bool {
        return self == .completed or self == .failed;
    }

    pub fn fromString(s: []const u8) ?JobStatus {
        if (std.mem.eql(u8, s, "queued")) return .queued;
        if (std.mem.eql(u8, s, "running")) return .running;
        if (std.mem.eql(u8, s, "completed")) return .completed;
        if (std.mem.eql(u8, s, "failed")) return .failed;
        return null;
    }
};
