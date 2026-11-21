const std = @import("std");
const core = @import("../core/mod.zig");
const PayloadHandle = core.PayloadHandle;

/// Streaming row iterator returned by `Repository.readStream()`.
pub const RowIterator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        next: *const fn (ctx: *anyopaque) anyerror!?PayloadHandle,
        deinit: *const fn (ctx: *anyopaque) void,
        estimatedCount: ?*const fn (ctx: *const anyopaque) ?usize = null,
    };

    pub fn next(self: RowIterator) !?PayloadHandle {
        return self.vtable.next(self.ptr);
    }

    pub fn deinit(self: RowIterator) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn estimatedCount(self: RowIterator) ?usize {
        const f = self.vtable.estimatedCount orelse return null;
        return f(self.ptr);
    }

    pub fn collectAll(self: RowIterator, allocator: std.mem.Allocator) !std.ArrayListUnmanaged(PayloadHandle) {
        var list: std.ArrayListUnmanaged(PayloadHandle) = .empty;
        errdefer list.deinit(allocator);
        while (try self.next()) |row| {
            try list.append(allocator, row);
        }
        return list;
    }
};
