const std = @import("std");

/// Lightweight ephemeral view of a field value extracted via compile-time reflection.
/// Allows zero-copy inspection of native Zig structs for filtering and serialization.
pub const ReflectedValue = union(enum) {
    none: void,
    int: i64,
    uint: u64,
    float: f64,
    boolean: bool,
    string: []const u8,
    bytes: []const u8,
    unsupported: void,

    pub fn fromInt(v: anytype) ReflectedValue {
        const info = @typeInfo(@TypeOf(v));
        if (info == .int and info.int.signedness == .unsigned) {
            return .{ .uint = @intCast(v) };
        }
        return .{ .int = @intCast(v) };
    }

    pub fn fromFloat(v: anytype) ReflectedValue {
        return .{ .float = @floatCast(v) };
    }

    pub fn fromBool(v: bool) ReflectedValue {
        return .{ .boolean = v };
    }

    pub fn fromString(v: []const u8) ReflectedValue {
        return .{ .string = v };
    }

    pub fn asFloat(self: ReflectedValue) ?f64 {
        return switch (self) {
            .float => |v| v,
            .int => |v| @floatFromInt(v),
            .uint => |v| @floatFromInt(v),
            else => null,
        };
    }

    pub fn asInt(self: ReflectedValue) ?i64 {
        return switch (self) {
            .int => |v| v,
            .uint => |v| @intCast(v),
            else => null,
        };
    }

    pub fn asString(self: ReflectedValue) ?[]const u8 {
        return switch (self) {
            .string => |v| v,
            .bytes => |v| v,
            else => null,
        };
    }

    pub fn asBool(self: ReflectedValue) ?bool {
        return switch (self) {
            .boolean => |v| v,
            .int => |v| v != 0,
            .uint => |v| v != 0,
            else => null,
        };
    }

    pub fn isTruthy(self: ReflectedValue) bool {
        return switch (self) {
            .none => false,
            .int => |v| v != 0,
            .uint => |v| v != 0,
            .float => |v| v != 0.0,
            .boolean => |v| v,
            .string => |v| v.len > 0,
            .bytes => |v| v.len > 0,
            .unsupported => false,
        };
    }

    pub fn equals(self: ReflectedValue, other: ReflectedValue) bool {
        return switch (self) {
            .none => other == .none,
            .int => |v| switch (other) {
                .int => |ov| v == ov,
                .uint => |ov| v >= 0 and @as(u64, @intCast(v)) == ov,
                .float => |ov| @as(f64, @floatFromInt(v)) == ov,
                else => false,
            },
            .uint => |v| switch (other) {
                .uint => |ov| v == ov,
                .int => |ov| ov >= 0 and v == @as(u64, @intCast(ov)),
                .float => |ov| @as(f64, @floatFromInt(v)) == ov,
                else => false,
            },
            .float => |v| switch (other) {
                .float => |ov| v == ov,
                .int => |ov| v == @as(f64, @floatFromInt(ov)),
                .uint => |ov| v == @as(f64, @floatFromInt(ov)),
                else => false,
            },
            .boolean => |v| switch (other) {
                .boolean => |ov| v == ov,
                else => false,
            },
            .string => |v| switch (other) {
                .string => |ov| std.mem.eql(u8, v, ov),
                .bytes => |ov| std.mem.eql(u8, v, ov),
                else => false,
            },
            .bytes => |v| switch (other) {
                .string => |ov| std.mem.eql(u8, v, ov),
                .bytes => |ov| std.mem.eql(u8, v, ov),
                else => false,
            },
            .unsupported => false,
        };
    }
};

pub const ReflectFn = *const fn (ptr: *const anyopaque, field_name: []const u8) ?ReflectedValue;
pub const ContextualReflectFn = *const fn (ctx: *const anyopaque, ptr: *const anyopaque, field_name: []const u8) ?ReflectedValue;
pub const OpaqueReflectAbiFn = *const fn (ptr: *const anyopaque, field_ptr: [*]const u8, field_len: usize) callconv(.c) OpaqueReflectedValueAbi;

pub const OpaqueReflectedValueAbi = extern struct {
    tag: u32 = 0,
    int_val: i64 = 0,
    float_val: f64 = 0.0,
    str_ptr: ?[*]const u8 = null,
    str_len: usize = 0,
};

pub const PayloadRepr = enum(u8) {
    bytes = 0,
    typed = 1,
    dynamic = 2,
};

/// Zero-copy type-erased fat pointer for transporting native Zig structs or streams
/// across pipeline task and repository boundaries without allocating dynamic wrappers.
pub const PayloadHandle = struct {
    ptr: *const anyopaque,
    len: usize, // 1 if scalar, N if slice/stream
    is_stream: bool,
    type_name: []const u8,
    element_size: usize,
    element_align: u29,
    reflect_fn: ?ReflectFn = null,
    reflect_ctx: ?*const anyopaque = null,
    reflect_ctx_fn: ?ContextualReflectFn = null,
    abi_reflect_fn: ?OpaqueReflectAbiFn = null,
    repr: PayloadRepr = .bytes,
    schema_id: u64 = 0,
    field_names: []const [*:0]const u8 = &.{},
    /// Opaque pointer to engine-internal stream backing (e.g. out-of-core / piece-table).
    stream_backing: ?*const anyopaque = null,

    pub fn empty() PayloadHandle {
        return .{
            .ptr = &.{},
            .len = 0,
            .is_stream = true,
            .type_name = "empty",
            .element_size = 0,
            .element_align = 1,
            .repr = .bytes,
        };
    }

    fn reflectValue(comptime V: type, val: V) ReflectedValue {
        const info = @typeInfo(V);
        switch (info) {
            .bool => return .{ .boolean = val },
            .int => |ii| return if (ii.signedness == .unsigned)
                .{ .uint = @intCast(val) }
            else
                .{ .int = @intCast(val) },
            .float => return .{ .float = @floatCast(val) },
            .@"enum" => return .{ .string = @tagName(val) },
            .pointer => |p| {
                if (p.size == .slice and p.child == u8) {
                    return .{ .string = val };
                }
                return .unsupported;
            },
            .optional => |opt| {
                if (val) |inner| return reflectValue(opt.child, inner);
                return .none;
            },
            else => return .unsupported,
        }
    }

    fn makeReflectFn(comptime T: type) ?ReflectFn {
        if (@typeInfo(T) != .@"struct") return null;
        const S = struct {
            fn reflect(raw_ptr: *const anyopaque, field_name: []const u8) ?ReflectedValue {
                const typed_ptr: *const T = @ptrCast(@alignCast(raw_ptr));
                if (@hasDecl(T, "getReflected")) {
                    return typed_ptr.getReflected(field_name);
                }
                const s = @typeInfo(T).@"struct";
                inline for (s.field_names, s.field_types) |f_name, f_type| {
                    if (std.mem.eql(u8, f_name, field_name)) {
                        return reflectValue(f_type, @field(typed_ptr, f_name));
                    }
                }
                if (@hasDecl(T, "getParam")) {
                    if (typed_ptr.getParam(field_name)) |val| {
                        return .{ .string = val };
                    }
                }
                return null;
            }
        };
        return S.reflect;
    }

    fn makeAbiReflectFn(comptime T: type) ?OpaqueReflectAbiFn {
        if (@typeInfo(T) != .@"struct") return null;
        const S = struct {
            fn reflectAbi(raw_ptr: *const anyopaque, field_ptr: [*]const u8, field_len: usize) callconv(.c) OpaqueReflectedValueAbi {
                const rf = comptime makeReflectFn(T).?;
                const val = rf(raw_ptr, field_ptr[0..field_len]) orelse return .{};
                return switch (val) {
                    .none, .unsupported => .{},
                    .int => |iv| .{ .tag = 1, .int_val = iv },
                    .uint => |uv| .{ .tag = 2, .int_val = @bitCast(uv) },
                    .float => |fv| .{ .tag = 3, .float_val = fv },
                    .boolean => |bv| .{ .tag = 4, .int_val = if (bv) 1 else 0 },
                    .string => |sv| .{ .tag = 5, .str_ptr = sv.ptr, .str_len = sv.len },
                    .bytes => |bv| .{ .tag = 5, .str_ptr = bv.ptr, .str_len = bv.len },
                };
            }
        };
        return S.reflectAbi;
    }

    pub fn fromSlice(comptime T: type, items: []const T) PayloadHandle {
        return .{
            .ptr = if (items.len > 0) @ptrCast(items.ptr) else &.{},
            .len = items.len,
            .is_stream = true,
            .type_name = @typeName(T),
            .element_size = @sizeOf(T),
            .element_align = @alignOf(T),
            .reflect_fn = makeReflectFn(T),
            .abi_reflect_fn = makeAbiReflectFn(T),
            .repr = if (T == u8) .bytes else .typed,
        };
    }

    pub fn fromScalar(comptime T: type, item: *const T) PayloadHandle {
        return .{
            .ptr = @ptrCast(item),
            .len = 1,
            .is_stream = false,
            .type_name = @typeName(T),
            .element_size = @sizeOf(T),
            .element_align = @alignOf(T),
            .reflect_fn = makeReflectFn(T),
            .abi_reflect_fn = makeAbiReflectFn(T),
            .repr = if (T == u8) .bytes else .typed,
        };
    }

    pub fn getReflected(self: PayloadHandle, field_name: []const u8) ?ReflectedValue {
        return self.getReflectedAt(0, field_name);
    }

    pub fn getReflectedPath(self: PayloadHandle, path: []const u8) ?ReflectedValue {
        return self.getReflected(path);
    }

    pub fn getReflectedAt(self: PayloadHandle, idx: usize, field_name: []const u8) ?ReflectedValue {
        if (idx >= self.len) return null;
        const elem_ptr: *const anyopaque = if (idx == 0)
            self.ptr
        else
            @ptrFromInt(@intFromPtr(self.ptr) + idx * self.element_size);

        if (self.reflect_fn) |rf| {
            return rf(elem_ptr, field_name);
        }
        if (self.reflect_ctx_fn) |rf_ctx| {
            if (self.reflect_ctx) |ctx| {
                return rf_ctx(ctx, elem_ptr, field_name);
            }
        }
        return null;
    }

    pub fn asSlice(self: PayloadHandle, comptime T: type) []const T {
        if (self.len == 0) return &.{};
        const typed_ptr: [*]const T = @ptrCast(@alignCast(self.ptr));
        return typed_ptr[0..self.len];
    }

    pub fn asScalar(self: PayloadHandle, comptime T: type) *const T {
        return @ptrCast(@alignCast(self.ptr));
    }

    pub fn fromOpaqueStream(backing: *const anyopaque, len_u64: u64) PayloadHandle {
        return .{
            .ptr = backing,
            .len = @intCast(@min(len_u64, std.math.maxInt(usize))),
            .is_stream = true,
            .type_name = "u8",
            .element_size = 1,
            .element_align = 1,
            .repr = .bytes,
            .stream_backing = backing,
        };
    }

    pub fn elementAt(self: PayloadHandle, index: usize) ?PayloadHandle {
        if (!self.is_stream or self.repr == .bytes or self.element_size == 0) {
            return if (index == 0 and self.len > 0) self else null;
        }
        if (index >= self.len) return null;
        const base: [*]const u8 = @ptrCast(self.ptr);
        const elem_ptr: *const anyopaque = @ptrCast(base + index * self.element_size);
        return .{
            .ptr = elem_ptr,
            .len = 1,
            .is_stream = false,
            .type_name = self.type_name,
            .element_size = self.element_size,
            .element_align = self.element_align,
            .reflect_fn = self.reflect_fn,
            .reflect_ctx = self.reflect_ctx,
            .reflect_ctx_fn = self.reflect_ctx_fn,
            .abi_reflect_fn = self.abi_reflect_fn,
            .repr = self.repr,
            .field_names = self.field_names,
            .schema_id = self.schema_id,
        };
    }
};
