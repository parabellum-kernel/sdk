const std = @import("std");
const abi = @import("../../abi/mod.zig");
const capabilities = @import("../../capabilities/mod.zig");
const envelope = @import("envelope.zig");

pub const InboundRequest = envelope.InboundRequest;
pub const InboundResponse = envelope.InboundResponse;

/// Ergonomic Zig wrapper around the host's C-ABI `HostDispatchFn_ABI`.
pub const HostDispatcher = struct {
    ptr: *anyopaque,
    dispatch_fn: abi.extension.HostDispatchFn_ABI,

    pub fn dispatch(self: HostDispatcher, req: InboundRequest) !InboundResponse {
        const abi_req = abi.InboundRequest_ABI{
            .command_or_route = abi.Slice_ABI.from(req.command_or_route),
            .pipeline_yaml_path = abi.Slice_ABI.from(req.pipeline_yaml_path),
            .payload = abi.Slice_ABI.from(req.payload),
            .args_json = abi.Slice_ABI.from(req.args_json),
        };
        var abi_resp = abi.InboundResponse_ABI{
            .status_code = 500,
            .body = abi.Slice_ABI.empty,
        };
        const err_code = self.dispatch_fn(self.ptr, &abi_req, &abi_resp);
        if (err_code != .ok) {
            return error.HostDispatchFailed;
        }
        return .{
            .status_code = @intCast(abi_resp.status_code),
            .body = abi_resp.body.toSlice(),
        };
    }
};

/// Fetches and parses the host's `CapabilityCatalog` via `KernelApiVTable_ABI.get_capability_catalog_json`.
/// Returns `null` if the host does not expose capability introspection.
pub fn fetchCapabilityCatalog(
    alloc: std.mem.Allocator,
    kernel: *abi.extension.KernelHandle_ABI,
    api: *const abi.KernelApiVTable_ABI,
) !?std.json.Parsed(capabilities.CapabilityCatalog) {
    const get_fn = api.get_capability_catalog_json orelse return null;

    const Capture = struct {
        alloc: std.mem.Allocator,
        json_copy: ?[]u8 = null,
        oom: bool = false,

        fn onJson(raw_ctx: ?*anyopaque, slice: abi.Slice_ABI) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(raw_ctx.?));
            self.json_copy = self.alloc.dupe(u8, slice.toSlice()) catch {
                self.oom = true;
                return;
            };
        }
    };

    var cap = Capture{ .alloc = alloc };
    const rc = get_fn(kernel, &cap, Capture.onJson);
    if (cap.oom) return error.OutOfMemory;
    defer if (cap.json_copy) |buf| alloc.free(buf);
    if (rc != .ok) return error.HostError;

    const json_bytes = cap.json_copy orelse return null;
    return try capabilities.fromJson(alloc, json_bytes);
}

/// Comptime builder that wraps a Zig inbound transport struct `T` into an `abi.InboundTransportVTable_ABI`.
/// `T` must define:
/// - `pub fn serve(self: *T, listen_addr: []const u8, pipeline_path: []const u8, dispatcher: HostDispatcher) anyerror!void`
/// - `pub fn deinit(self: *T) void`
/// Optional:
/// - `pub fn serveArgs(self: *T, argv: []const []const u8, dispatcher: HostDispatcher) anyerror!void`
pub fn defineInboundTransport(comptime T: type) abi.InboundTransportVTable_ABI {
    const Trampoline = struct {
        fn serve(
            ctx: *abi.extension.TransportCtx_ABI,
            listen_addr: abi.Slice_ABI,
            pipeline_path: abi.Slice_ABI,
            host_dispatcher: *anyopaque,
            dispatch_fn: abi.extension.HostDispatchFn_ABI,
        ) callconv(.c) abi.HostError_ABI {
            const self: *T = @ptrCast(@alignCast(ctx));
            const dispatcher = HostDispatcher{
                .ptr = host_dispatcher,
                .dispatch_fn = dispatch_fn,
            };
            self.serve(listen_addr.toSlice(), pipeline_path.toSlice(), dispatcher) catch return .internal_error;
            return .ok;
        }

        fn deinit(ctx: *abi.extension.TransportCtx_ABI) callconv(.c) void {
            const self: *T = @ptrCast(@alignCast(ctx));
            self.deinit();
        }

        fn serveArgs(
            ctx: *abi.extension.TransportCtx_ABI,
            argv_ptr: [*]const abi.Slice_ABI,
            argc: usize,
            host_dispatcher: *anyopaque,
            dispatch_fn: abi.extension.HostDispatchFn_ABI,
        ) callconv(.c) abi.HostError_ABI {
            const self: *T = @ptrCast(@alignCast(ctx));
            const dispatcher = HostDispatcher{
                .ptr = host_dispatcher,
                .dispatch_fn = dispatch_fn,
            };
            var stack_buf: [64][]const u8 = undefined;
            const n = @min(argc, stack_buf.len);
            for (0..n) |i| {
                stack_buf[i] = argv_ptr[i].toSlice();
            }
            self.serveArgs(stack_buf[0..n], dispatcher) catch return .internal_error;
            return .ok;
        }
    };

    return .{
        .serve = Trampoline.serve,
        .deinit = Trampoline.deinit,
        .serve_args = if (@hasDecl(T, "serveArgs")) Trampoline.serveArgs else null,
    };
}

test "defineInboundTransport and HostDispatcher bridge Zig types over C-ABI" {
    const DummyTransport = struct {
        last_addr: []const u8 = "",
        last_status: i32 = 0,
        deinit_called: bool = false,

        pub fn serve(self: *@This(), listen_addr: []const u8, _: []const u8, dispatcher: HostDispatcher) !void {
            self.last_addr = listen_addr;
            const resp = try dispatcher.dispatch(.{ .command_or_route = "ping" });
            self.last_status = resp.status_code;
        }

        pub fn deinit(self: *@This()) void {
            self.deinit_called = true;
        }
    };

    const MockHost = struct {
        fn dispatch(_: *anyopaque, req: *const abi.InboundRequest_ABI, out_resp: *abi.InboundResponse_ABI) callconv(.c) abi.HostError_ABI {
            if (std.mem.eql(u8, req.command_or_route.toSlice(), "ping")) {
                out_resp.* = .{ .status_code = 200, .body = abi.Slice_ABI.from("pong") };
                return .ok;
            }
            return .invalid_argument;
        }
    };

    const vtable = defineInboundTransport(DummyTransport);
    var inst = DummyTransport{};
    var dummy_ctx: u8 = 0;

    const rc = vtable.serve(
        @ptrCast(&inst),
        abi.Slice_ABI.from("127.0.0.1:8080"),
        abi.Slice_ABI.empty,
        @ptrCast(&dummy_ctx),
        MockHost.dispatch,
    );
    try std.testing.expectEqual(abi.HostError_ABI.ok, rc);
    try std.testing.expectEqualStrings("127.0.0.1:8080", inst.last_addr);
    try std.testing.expectEqual(@as(i32, 200), inst.last_status);

    vtable.deinit(@ptrCast(&inst));
    try std.testing.expect(inst.deinit_called);
}
