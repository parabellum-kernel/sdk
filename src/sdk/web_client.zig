const std = @import("std");
const Allocator = std.mem.Allocator;
const abi = @import("../abi/mod.zig");
const task_abi = @import("parabellum_abi");

pub const WebClientError = error{
    RepositoryNotSupported,
    DatasourceNotFound,
    ReadNotSupported,
    WriteNotSupported,
    HostIoError,
    MissingResponseData,
    MissingWriteResult,
} || Allocator.Error;

/// Ergonomic comptime-typed client over `(RepoHandle_ABI, *const StorageRepositoryVTable_ABI)`
/// for both typed REST APIs and schemaless HTML/binary scraping.
pub const WebClient = struct {
    handle: *abi.driver.RepoHandle_ABI,
    vtable: *const abi.driver.StorageRepositoryVTable_ABI,

    /// Resolves a datasource by ID from `TaskContext` across the C-ABI boundary.
    pub fn fromContext(ctx: task_abi.TaskContext, datasource_id: [*:0]const u8) WebClientError!WebClient {
        const get_repo = ctx.raw.host.get_repository orelse return error.RepositoryNotSupported;
        var raw_handle: ?*anyopaque = null;
        var raw_vtable: ?*const anyopaque = null;
        if (get_repo(ctx.raw, datasource_id, &raw_handle, &raw_vtable) != .ok) {
            return error.DatasourceNotFound;
        }
        return .{
            .handle = @ptrCast(@alignCast(raw_handle orelse return error.DatasourceNotFound)),
            .vtable = @ptrCast(@alignCast(raw_vtable orelse return error.DatasourceNotFound)),
        };
    }

    /// Executes a read endpoint and returns the raw response body (`body` / `data` field) as an owned slice.
    pub fn fetchBytes(
        self: WebClient,
        allocator: Allocator,
        endpoint: []const u8,
        params: anytype,
    ) ![]u8 {
        const read_stream = self.vtable.read_stream orelse return error.ReadNotSupported;

        var filter_buf = std.ArrayList(u8).empty;
        defer filter_buf.deinit(allocator);
        var offset: u64 = 0;
        var limit: u64 = 0;
        try buildReadParams(allocator, params, &filter_buf, &offset, &limit);

        const spec = abi.ReadSpec_ABI{
            .table = abi.Slice_ABI.from(endpoint),
            .limit = limit,
            .offset = offset,
            .filter_sql_or_expr = abi.Slice_ABI.from(filter_buf.items),
        };

        var iter: abi.driver.RowIterator_ABI = undefined;
        if (read_stream(self.handle, &spec, &iter) != .ok) {
            return error.HostIoError;
        }
        defer iter.vtable.deinit(iter.handle);

        var row: abi.RowView_ABI = undefined;
        const rc = iter.vtable.next(iter.handle, &row);
        if (rc == .end_of_stream) return error.MissingResponseData;
        if (rc != .ok) return error.HostIoError;

        const fields = if (row.fields_len > 0 and row.fields_ptr != null)
            row.fields_ptr.?[0..row.fields_len]
        else
            &.{};

        for (fields) |nf| {
            const name = std.mem.span(nf.name);
            if ((std.mem.eql(u8, name, "data") or std.mem.eql(u8, name, "body")) and nf.value.tag == .bytes_val) {
                return allocator.dupe(u8, nf.value.payload.bytes.toSlice());
            }
        }
        for (fields) |nf| {
            if (nf.value.tag == .bytes_val) {
                return allocator.dupe(u8, nf.value.payload.bytes.toSlice());
            }
        }
        return error.MissingResponseData;
    }

    /// Alias for `fetchBytes` returning the raw UTF-8 HTML/text document for scraping tasks.
    pub fn fetchText(
        self: WebClient,
        allocator: Allocator,
        endpoint: []const u8,
        params: anytype,
    ) ![]u8 {
        return self.fetchBytes(allocator, endpoint, params);
    }

    /// Executes a read endpoint and decodes the first returned row into comptime struct `T`.
    pub fn fetchOne(
        self: WebClient,
        comptime T: type,
        allocator: Allocator,
        endpoint: []const u8,
        params: anytype,
    ) !?T {
        const read_stream = self.vtable.read_stream orelse return error.ReadNotSupported;

        var filter_buf = std.ArrayList(u8).empty;
        defer filter_buf.deinit(allocator);
        var offset: u64 = 0;
        var limit: u64 = 0;
        try buildReadParams(allocator, params, &filter_buf, &offset, &limit);

        const spec = abi.ReadSpec_ABI{
            .table = abi.Slice_ABI.from(endpoint),
            .limit = limit,
            .offset = offset,
            .filter_sql_or_expr = abi.Slice_ABI.from(filter_buf.items),
        };

        var iter: abi.driver.RowIterator_ABI = undefined;
        if (read_stream(self.handle, &spec, &iter) != .ok) {
            return error.HostIoError;
        }
        defer iter.vtable.deinit(iter.handle);

        var row: abi.RowView_ABI = undefined;
        const rc = iter.vtable.next(iter.handle, &row);
        if (rc == .end_of_stream) return null;
        if (rc != .ok) return error.HostIoError;

        return try decodeRowInto(T, allocator, row);
    }

    /// Executes a read endpoint (including paginated endpoints) and collects all rows into `[]T`.
    pub fn fetchAll(
        self: WebClient,
        comptime T: type,
        allocator: Allocator,
        endpoint: []const u8,
        params: anytype,
    ) ![]T {
        const read_stream = self.vtable.read_stream orelse return error.ReadNotSupported;

        var filter_buf = std.ArrayList(u8).empty;
        defer filter_buf.deinit(allocator);
        var offset: u64 = 0;
        var limit: u64 = 0;
        try buildReadParams(allocator, params, &filter_buf, &offset, &limit);

        const spec = abi.ReadSpec_ABI{
            .table = abi.Slice_ABI.from(endpoint),
            .limit = limit,
            .offset = offset,
            .filter_sql_or_expr = abi.Slice_ABI.from(filter_buf.items),
        };

        var iter: abi.driver.RowIterator_ABI = undefined;
        if (read_stream(self.handle, &spec, &iter) != .ok) {
            return error.HostIoError;
        }
        defer iter.vtable.deinit(iter.handle);

        var list = std.ArrayList(T).empty;
        errdefer list.deinit(allocator);

        var row: abi.RowView_ABI = undefined;
        while (true) {
            const rc = iter.vtable.next(iter.handle, &row);
            if (rc == .end_of_stream) break;
            if (rc != .ok) return error.HostIoError;
            try list.append(allocator, try decodeRowInto(T, allocator, row));
        }
        return list.toOwnedSlice(allocator);
    }

    /// Executes a write/mutation endpoint (`POST`/`PUT`/`PATCH`/`DELETE`) with `params` struct/tuple
    /// and optional `raw_bytes`, automatically reading `last_put_result` when `RespT != void`.
    pub fn send(
        self: WebClient,
        comptime RespT: type,
        allocator: Allocator,
        endpoint: []const u8,
        params: anytype,
        raw_bytes: []const u8,
    ) !RespT {
        const write_row = self.vtable.write_row orelse return error.WriteNotSupported;

        const T = @TypeOf(params);
        const info = @typeInfo(T);
        if (info != .@"struct") @compileError("params must be a struct or tuple");

        const s_info = info.@"struct";
        var abi_fields: [s_info.field_names.len]abi.NamedField_ABI = undefined;
        var count: usize = 0;

        inline for (s_info.field_names) |fname| {
            const val = @field(params, fname);
            if (toAbiValue(val)) |av| {
                abi_fields[count] = .{
                    .name = fname.ptr,
                    .value = av,
                };
                count += 1;
            }
        }

        const ws = abi.driver.WriteSpec_ABI{
            .table = abi.Slice_ABI.from(endpoint),
            .mode = .insert,
            .fields_ptr = if (count > 0) &abi_fields else null,
            .fields_len = count,
            .raw_bytes = abi.Slice_ABI.from(raw_bytes),
        };

        if (write_row(self.handle, &ws) != .ok) {
            return error.HostIoError;
        }

        if (RespT == void) return;
        return (try self.fetchOne(RespT, allocator, "last_put_result", .{})) orelse error.MissingWriteResult;
    }
};

fn toAbiValue(val: anytype) ?abi.Value_ABI {
    const T = @TypeOf(val);
    switch (@typeInfo(T)) {
        .optional => {
            if (val) |inner| return toAbiValue(inner);
            return .{ .tag = .null_val, .payload = .{ .i = 0 } };
        },
        .bool => return .{ .tag = .bool_val, .payload = .{ .b = val } },
        .int, .comptime_int => {
            if (val < 0) return .{ .tag = .int_val, .payload = .{ .i = @intCast(val) } };
            return .{ .tag = .uint_val, .payload = .{ .u = @intCast(val) } };
        },
        .float, .comptime_float => return .{ .tag = .float_val, .payload = .{ .f = @floatCast(val) } },
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                return .{ .tag = .bytes_val, .payload = .{ .bytes = abi.Slice_ABI.from(val) } };
            }
            if (p.size == .one and @typeInfo(p.child) == .array and @typeInfo(p.child).array.child == u8) {
                const s: []const u8 = val;
                return .{ .tag = .bytes_val, .payload = .{ .bytes = abi.Slice_ABI.from(s) } };
            }
        },
        else => {},
    }
    return null;
}

fn buildReadParams(
    allocator: Allocator,
    params: anytype,
    out_filter: *std.ArrayList(u8),
    out_offset: *u64,
    out_limit: *u64,
) !void {
    const T = @TypeOf(params);
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("params must be a struct or tuple");

    var first = true;
    const s_info = info.@"struct";
    inline for (s_info.field_names, 0..) |fname, i| {
        const ftype = s_info.field_types[i];
        const val = @field(params, fname);
        if (comptime std.mem.eql(u8, fname, "offset")) {
            out_offset.* = @intCast(val);
        } else if (comptime std.mem.eql(u8, fname, "limit")) {
            out_limit.* = @intCast(val);
        } else {
            const maybe_str: ?[]const u8 = switch (@typeInfo(ftype)) {
                .optional => if (val) |inner| fieldValToStr(inner) else null,
                else => fieldValToStr(val),
            };
            if (maybe_str) |s| {
                if (!first) try out_filter.appendSlice(allocator, " AND ");
                first = false;
                try out_filter.appendSlice(allocator, fname);
                try out_filter.appendSlice(allocator, "='");
                try out_filter.appendSlice(allocator, s);
                try out_filter.append(allocator, '\'');
            } else if (@typeInfo(ftype) == .int or @typeInfo(ftype) == .comptime_int) {
                if (!first) try out_filter.appendSlice(allocator, " AND ");
                first = false;
                try out_filter.appendSlice(allocator, fname);
                try out_filter.appendSlice(allocator, "='");
                const num_str = try std.fmt.allocPrint(allocator, "{d}", .{val});
                defer allocator.free(num_str);
                try out_filter.appendSlice(allocator, num_str);
                try out_filter.append(allocator, '\'');
            }
        }
    }
}

fn fieldValToStr(val: anytype) ?[]const u8 {
    const T = @TypeOf(val);
    return switch (@typeInfo(T)) {
        .pointer => |p| if (p.size == .slice and p.child == u8)
            val
        else if (p.size == .one and @typeInfo(p.child) == .array and @typeInfo(p.child).array.child == u8)
            @as([]const u8, val)
        else
            null,
        .bool => if (val) "true" else "false",
        else => null,
    };
}

fn decodeRowInto(comptime T: type, allocator: Allocator, row: abi.RowView_ABI) !T {
    var out: T = undefined;
    const s_info = @typeInfo(T).@"struct";
    const abi_fields = if (row.fields_len > 0 and row.fields_ptr != null)
        row.fields_ptr.?[0..row.fields_len]
    else
        &.{};

    inline for (s_info.field_names, 0..) |fname, i| {
        const ftype = s_info.field_types[i];
        var found: ?abi.Value_ABI = null;
        for (abi_fields) |af| {
            if (std.mem.eql(u8, std.mem.span(af.name), fname)) {
                found = af.value;
                break;
            }
        }

        if (found) |av| {
            @field(out, fname) = try decodeField(ftype, allocator, av);
        } else if (s_info.field_attrs[i].default_value_ptr) |def_ptr| {
            const typed_def: *const ftype = @ptrCast(@alignCast(def_ptr));
            @field(out, fname) = typed_def.*;
        } else if (@typeInfo(ftype) == .optional) {
            @field(out, fname) = null;
        } else {
            return error.MissingResponseData;
        }
    }
    return out;
}

fn decodeField(comptime F: type, allocator: Allocator, av: abi.Value_ABI) !F {
    switch (@typeInfo(F)) {
        .optional => |opt| {
            if (av.tag == .null_val) return null;
            return try decodeField(opt.child, allocator, av);
        },
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                return switch (av.tag) {
                    .bytes_val => try allocator.dupe(u8, av.payload.bytes.toSlice()),
                    .int_val => try std.fmt.allocPrint(allocator, "{d}", .{av.payload.i}),
                    .uint_val => try std.fmt.allocPrint(allocator, "{d}", .{av.payload.u}),
                    .float_val => try std.fmt.allocPrint(allocator, "{d}", .{av.payload.f}),
                    .bool_val => try allocator.dupe(u8, if (av.payload.b) "true" else "false"),
                    .null_val => try allocator.dupe(u8, ""),
                };
            }
            @compileError("Unsupported pointer field type in WebClient.decodeField: " ++ @typeName(F));
        },
        .int => |it| {
            return switch (av.tag) {
                .int_val => @intCast(av.payload.i),
                .uint_val => @intCast(av.payload.u),
                .bytes_val => if (it.signedness == .signed)
                    std.fmt.parseInt(F, av.payload.bytes.toSlice(), 10) catch 0
                else
                    std.fmt.parseInt(F, av.payload.bytes.toSlice(), 10) catch 0,
                else => 0,
            };
        },
        .float => {
            return switch (av.tag) {
                .float_val => @floatCast(av.payload.f),
                .int_val => @floatFromInt(av.payload.i),
                .uint_val => @floatFromInt(av.payload.u),
                .bytes_val => std.fmt.parseFloat(F, av.payload.bytes.toSlice()) catch 0.0,
                else => 0.0,
            };
        },
        .bool => {
            return switch (av.tag) {
                .bool_val => av.payload.b,
                .int_val => av.payload.i != 0,
                .uint_val => av.payload.u != 0,
                .bytes_val => std.ascii.eqlIgnoreCase(av.payload.bytes.toSlice(), "true"),
                else => false,
            };
        },
        else => @compileError("Unsupported field type in WebClient.decodeField: " ++ @typeName(F)),
    }
}

test "WebClient fetchText, fetchBytes, fetchOne, fetchAll, and send" {
    const alloc = std.testing.allocator;

    const MockRepo = struct {
        var row_idx: usize = 0;
        var last_written_table: []const u8 = "";
        var last_written_bytes: []const u8 = "";

        fn getCaps(_: *const abi.driver.RepoHandle_ABI) callconv(.c) abi.DriverCapabilities_ABI {
            return .{ .read = true, .write = true, .streaming_read = true, .streaming_write = true };
        }
        fn recCount(_: *const abi.driver.RepoHandle_ABI, _: abi.Slice_ABI) callconv(.c) usize {
            return 0;
        }
        fn deinitRepo(_: *abi.driver.RepoHandle_ABI) callconv(.c) void {}

        const IterState = struct {
            mode: enum { html, quota, list, put_res },
            idx: usize = 0,
        };

        var iter_state: IterState = .{ .mode = .html };
        var fields_buf: [2]abi.NamedField_ABI = undefined;

        fn iterNext(handle: *abi.driver.RowIteratorHandle_ABI, out_row: *abi.RowView_ABI) callconv(.c) abi.HostError_ABI {
            const st: *IterState = @ptrCast(@alignCast(handle));
            switch (st.mode) {
                .html => {
                    if (st.idx > 0) return .end_of_stream;
                    st.idx += 1;
                    fields_buf[0] = .{ .name = "body", .value = .{ .tag = .bytes_val, .payload = .{ .bytes = abi.Slice_ABI.from("<html>ok</html>") } } };
                    out_row.* = .{ .fields_ptr = &fields_buf, .fields_len = 1 };
                    return .ok;
                },
                .quota => {
                    if (st.idx > 0) return .end_of_stream;
                    st.idx += 1;
                    fields_buf[0] = .{ .name = "limit_bytes", .value = .{ .tag = .uint_val, .payload = .{ .u = 1024 } } };
                    fields_buf[1] = .{ .name = "etag", .value = .{ .tag = .bytes_val, .payload = .{ .bytes = abi.Slice_ABI.from("\"e1\"") } } };
                    out_row.* = .{ .fields_ptr = &fields_buf, .fields_len = 2 };
                    return .ok;
                },
                .list => {
                    if (st.idx >= 2) return .end_of_stream;
                    const id_str = if (st.idx == 0) "item_1" else "item_2";
                    st.idx += 1;
                    fields_buf[0] = .{ .name = "id", .value = .{ .tag = .bytes_val, .payload = .{ .bytes = abi.Slice_ABI.from(id_str) } } };
                    out_row.* = .{ .fields_ptr = &fields_buf, .fields_len = 1 };
                    return .ok;
                },
                .put_res => {
                    if (st.idx > 0) return .end_of_stream;
                    st.idx += 1;
                    fields_buf[0] = .{ .name = "object_id", .value = .{ .tag = .bytes_val, .payload = .{ .bytes = abi.Slice_ABI.from("obj_77") } } };
                    out_row.* = .{ .fields_ptr = &fields_buf, .fields_len = 1 };
                    return .ok;
                },
            }
        }
        fn iterDeinit(_: *abi.driver.RowIteratorHandle_ABI) callconv(.c) void {}
        const iter_vt = abi.driver.RowIteratorVTable_ABI{
            .next = iterNext,
            .deinit = iterDeinit,
        };

        fn readStream(
            _: *abi.driver.RepoHandle_ABI,
            spec: *const abi.ReadSpec_ABI,
            out_iter: *abi.driver.RowIterator_ABI,
        ) callconv(.c) abi.HostError_ABI {
            const tbl = spec.table.toSlice();
            iter_state = .{
                .mode = if (std.mem.eql(u8, tbl, "scrape"))
                    .html
                else if (std.mem.eql(u8, tbl, "get_quota"))
                    .quota
                else if (std.mem.eql(u8, tbl, "list_items"))
                    .list
                else
                    .put_res,
                .idx = 0,
            };
            out_iter.* = .{
                .handle = @ptrCast(&iter_state),
                .vtable = &iter_vt,
            };
            return .ok;
        }

        fn writeRow(_: *abi.driver.RepoHandle_ABI, spec: *const abi.driver.WriteSpec_ABI) callconv(.c) abi.HostError_ABI {
            last_written_table = spec.table.toSlice();
            last_written_bytes = spec.raw_bytes.toSlice();
            return .ok;
        }

        var dummy_repo: u8 = 0;
        const vt = abi.driver.StorageRepositoryVTable_ABI{
            .get_capabilities = getCaps,
            .record_count = recCount,
            .deinit = deinitRepo,
            .write_row = writeRow,
            .read_stream = readStream,
        };
    };

    const client = WebClient{
        .handle = @ptrCast(&MockRepo.dummy_repo),
        .vtable = &MockRepo.vt,
    };

    // 1. fetchText / fetchBytes
    const html = try client.fetchText(alloc, "scrape", .{ .slug = "one-piece" });
    defer alloc.free(html);
    try std.testing.expectEqualStrings("<html>ok</html>", html);

    // 2. fetchOne
    const Quota = struct { limit_bytes: u64, etag: []const u8 };
    const q = (try client.fetchOne(Quota, alloc, "get_quota", .{})).?;
    defer alloc.free(q.etag);
    try std.testing.expectEqual(@as(u64, 1024), q.limit_bytes);
    try std.testing.expectEqualStrings("\"e1\"", q.etag);

    // 3. fetchAll
    const Item = struct { id: []const u8 };
    const items = try client.fetchAll(Item, alloc, "list_items", .{});
    defer {
        for (items) |it| alloc.free(it.id);
        alloc.free(items);
    }
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expectEqualStrings("item_1", items[0].id);
    try std.testing.expectEqualStrings("item_2", items[1].id);

    // 4. send + last_put_result
    const PutRes = struct { object_id: []const u8 };
    const put_res = try client.send(PutRes, alloc, "upload", .{ .name = "a.bin" }, "BIN_DATA");
    defer alloc.free(put_res.object_id);
    try std.testing.expectEqualStrings("upload", MockRepo.last_written_table);
    try std.testing.expectEqualStrings("BIN_DATA", MockRepo.last_written_bytes);
    try std.testing.expectEqualStrings("obj_77", put_res.object_id);
}
