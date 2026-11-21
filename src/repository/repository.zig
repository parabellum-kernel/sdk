const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../core/mod.zig");
const PayloadHandle = core.PayloadHandle;
const ConfigParam = core.ConfigParam;
const specs = @import("specs.zig");
const capabilities = @import("capabilities.zig");
const RowIterator = @import("row_iterator.zig").RowIterator;

/// Polymorphic abstract interface for repositories (Memory, SQLite, FileStore, S3, REST, etc.).
/// Independent of transport and capabilitySpec.
pub const Repository = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        writePayload: *const fn (ctx: *anyopaque, channel_or_table: []const u8, payload: PayloadHandle) anyerror!void,
        readPayload: *const fn (ctx: *anyopaque, channel_or_table: []const u8) ?PayloadHandle,
        recordCount: *const fn (ctx: *anyopaque, channel_or_table: []const u8) usize,
        deinit: *const fn (ctx: *anyopaque) void,

        writePayloadWithParams: ?*const fn (ctx: *anyopaque, channel_or_table: []const u8, payload: PayloadHandle, params: []const ConfigParam) anyerror!void = null,
        getCapabilities: ?*const fn (ctx: *const anyopaque) capabilities.StorageCapabilities = null,
        ensureSchema: ?*const fn (ctx: *anyopaque, catalog: *const anyopaque) anyerror!void = null,
        write: ?*const fn (ctx: *anyopaque, spec: specs.WriteSpec) anyerror!void = null,
        read: ?*const fn (ctx: *anyopaque, allocator: Allocator, spec: specs.ReadSpec) anyerror!PayloadHandle = null,
        readStream: ?*const fn (ctx: *anyopaque, allocator: Allocator, spec: specs.ReadSpec) anyerror!RowIterator = null,

        beginTx: ?*const fn (ctx: *anyopaque) anyerror!void = null,
        commit: ?*const fn (ctx: *anyopaque) anyerror!void = null,
        rollback: ?*const fn (ctx: *anyopaque) anyerror!void = null,

        beginSavepoint: ?*const fn (ctx: *anyopaque, name: []const u8) anyerror!void = null,
        rollbackSavepoint: ?*const fn (ctx: *anyopaque, name: []const u8) anyerror!void = null,
        releaseSavepoint: ?*const fn (ctx: *anyopaque, name: []const u8) anyerror!void = null,
    };

    pub const RepositoryVTable = VTable;
    pub const StorageRepositoryVTable = VTable;

    pub fn writePayload(self: Repository, channel_or_table: []const u8, payload: PayloadHandle) !void {
        try self.vtable.writePayload(self.ptr, channel_or_table, payload);
    }

    pub fn writePayloadWithParams(
        self: Repository,
        channel_or_table: []const u8,
        payload: PayloadHandle,
        params: []const ConfigParam,
    ) !void {
        if (self.vtable.writePayloadWithParams) |write_fn| {
            try write_fn(self.ptr, channel_or_table, payload, params);
        } else {
            try self.vtable.writePayload(self.ptr, channel_or_table, payload);
        }
    }

    pub fn readPayload(self: Repository, channel_or_table: []const u8) ?PayloadHandle {
        return self.vtable.readPayload(self.ptr, channel_or_table);
    }

    pub fn recordCount(self: Repository, channel_or_table: []const u8) usize {
        return self.vtable.recordCount(self.ptr, channel_or_table);
    }

    pub fn deinit(self: Repository) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn getCapabilities(self: Repository) capabilities.StorageCapabilities {
        const f = self.vtable.getCapabilities orelse return .{};
        return f(self.ptr);
    }

    pub fn ensureSchema(self: Repository, catalog: *const anyopaque) !void {
        const f = self.vtable.ensureSchema orelse return;
        try f(self.ptr, catalog);
    }

    pub fn write(self: Repository, spec: specs.WriteSpec) !void {
        if (self.vtable.write) |f| {
            try f(self.ptr, spec);
        } else {
            try self.vtable.writePayload(self.ptr, spec.table, spec.payload);
        }
    }

    pub fn read(self: Repository, allocator: Allocator, spec: specs.ReadSpec) !PayloadHandle {
        if (self.vtable.read) |f| {
            return f(self.ptr, allocator, spec);
        }
        return self.vtable.readPayload(self.ptr, spec.table) orelse PayloadHandle.empty();
    }

    pub fn readStream(self: Repository, allocator: Allocator, spec: specs.ReadSpec) !RowIterator {
        const f = self.vtable.readStream orelse return error.StreamingNotSupported;
        return f(self.ptr, allocator, spec);
    }

    pub fn beginTx(self: Repository) !void {
        const f = self.vtable.beginTx orelse return error.TransactionsNotSupported;
        try f(self.ptr);
    }

    pub fn commit(self: Repository) !void {
        const f = self.vtable.commit orelse return error.TransactionsNotSupported;
        try f(self.ptr);
    }

    pub fn rollback(self: Repository) !void {
        const f = self.vtable.rollback orelse return error.TransactionsNotSupported;
        try f(self.ptr);
    }

    pub fn beginSavepoint(self: Repository, name: []const u8) !void {
        const f = self.vtable.beginSavepoint orelse return error.SavepointsNotSupported;
        try f(self.ptr, name);
    }

    pub fn rollbackSavepoint(self: Repository, name: []const u8) !void {
        const f = self.vtable.rollbackSavepoint orelse return error.SavepointsNotSupported;
        try f(self.ptr, name);
    }

    pub fn releaseSavepoint(self: Repository, name: []const u8) !void {
        const f = self.vtable.releaseSavepoint orelse return error.SavepointsNotSupported;
        try f(self.ptr, name);
    }
};

pub const StorageRepository = Repository;
pub const RepositoryVTable = Repository.VTable;
pub const StorageRepositoryVTable = Repository.VTable;
