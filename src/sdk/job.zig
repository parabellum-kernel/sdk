const std = @import("std");
const Allocator = std.mem.Allocator;

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

/// Shared job state record for daemon job tracking and client/extension inspection.
pub const JobRecord = struct {
    id: u64 = 0,
    pipeline: []const u8 = "",
    status: JobStatus = .queued,
    progress_bytes: u64 = 0,
    total_bytes: u64 = 0,
    steps_executed: usize = 0,
    routers_evaluated: usize = 0,
    halted_early: bool = false,
    final_pipeline: []const u8 = "",
    output_json: ?[]const u8 = null,
    err_msg: ?[]const u8 = null,

    pub fn deinit(self: *JobRecord, allocator: Allocator) void {
        if (self.pipeline.len > 0) allocator.free(self.pipeline);
        if (self.final_pipeline.len > 0) allocator.free(self.final_pipeline);
        if (self.output_json) |o| allocator.free(o);
        if (self.err_msg) |e| allocator.free(e);
    }
};
