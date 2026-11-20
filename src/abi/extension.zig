const std = @import("std");
const common = @import("common.zig");

pub const Slice_ABI = common.Slice_ABI;
pub const HostError_ABI = common.HostError_ABI;
pub const SemVer_ABI = common.SemVer_ABI;

pub const EXTENSION_MANIFEST_SYMBOL_NAME = "parabellum_extension_manifest";
pub const EXTENSION_ABI_VERSION: u32 = 1;

pub const KernelHandle_ABI = opaque {};
pub const SubscriberCtx_ABI = opaque {};
pub const TransportCtx_ABI = opaque {};
pub const CommandCtx_ABI = opaque {};
pub const InboundStreamCtx_ABI = opaque {};
pub const InboundStreamHandle_ABI = opaque {};

pub const TelemetryEventKind_ABI = enum(u32) {
    pipeline_start = 1,
    pipeline_end = 2,
    step_start = 3,
    step_end = 4,
    filter_evaluated = 5,
    router_decision = 6,
    task_log = 7,
    outbound_exchange = 8,
    outbound_wire_packet = 9,
    job_started = 10,
    job_progress = 11,
    job_completed = 12,
    job_failed = 13,
    artifact_ready = 14,
    vfs_changed = 15,
    input_required = 16,
};

pub const TelemetryEvent_ABI = extern struct {
    kind: TelemetryEventKind_ABI,
    trace_id: [16]u8,
    span_id: [8]u8,
    parent_span_id: [8]u8,
    timestamp_ns: u64,
    duration_ns: u64,
    primary_name: Slice_ABI,
    secondary_name: Slice_ABI,
    tertiary_name: Slice_ABI,
    count_a: u64,
    count_b: u64,
    flags: u32,
    payload: Slice_ABI,
};

pub const TelemetrySubscriberVTable_ABI = extern struct {
    on_event: *const fn (ctx: *SubscriberCtx_ABI, event: *const TelemetryEvent_ABI) callconv(.c) void,
    flush: ?*const fn (ctx: *SubscriberCtx_ABI) callconv(.c) HostError_ABI = null,
    deinit: ?*const fn (ctx: *SubscriberCtx_ABI) callconv(.c) void = null,
};

/// Pull-based inbound stream VTable for large/chunked request bodies (O(1) RAM).
pub const InboundStreamVTable_ABI = extern struct {
    /// Returns bytes read (> 0), 0 on EOF, or < 0 on error.
    read: *const fn (ctx: *InboundStreamCtx_ABI, buf_ptr: [*]u8, buf_len: usize) callconv(.c) isize,
    close: ?*const fn (ctx: *InboundStreamCtx_ABI) callconv(.c) void = null,
};

pub const InboundRequest_ABI = extern struct {
    command_or_route: Slice_ABI,
    pipeline_yaml_path: Slice_ABI,
    payload: Slice_ABI,
    args_json: Slice_ABI,
    stream_ctx: ?*InboundStreamCtx_ABI = null,
    stream_vtable: ?*const InboundStreamVTable_ABI = null,
};

pub const InboundResponse_ABI = extern struct {
    status_code: c_int,
    body: Slice_ABI,
};

pub const HostDispatchFn_ABI = *const fn (
    host_dispatcher: *anyopaque,
    req: *const InboundRequest_ABI,
    out_resp: *InboundResponse_ABI,
) callconv(.c) HostError_ABI;

pub const InboundTransportVTable_ABI = extern struct {
    serve: *const fn (
        ctx: *TransportCtx_ABI,
        listen_addr: Slice_ABI,
        pipeline_path: Slice_ABI,
        host_dispatcher: *anyopaque,
        dispatch_fn: HostDispatchFn_ABI,
    ) callconv(.c) HostError_ABI,
    deinit: *const fn (ctx: *TransportCtx_ABI) callconv(.c) void,
    serve_args: ?*const fn (
        ctx: *TransportCtx_ABI,
        argv: [*]const Slice_ABI,
        argc: usize,
        host_dispatcher: *anyopaque,
        dispatch_fn: HostDispatchFn_ABI,
    ) callconv(.c) HostError_ABI = null,
};

pub const KernelApiVTable_ABI = extern struct {
    subscribe_telemetry: *const fn (
        kernel: *KernelHandle_ABI,
        ctx: *SubscriberCtx_ABI,
        vtable: *const TelemetrySubscriberVTable_ABI,
    ) callconv(.c) HostError_ABI,

    register_inbound_transport: *const fn (
        kernel: *KernelHandle_ABI,
        transport_name: [*:0]const u8,
        ctx: *TransportCtx_ABI,
        vtable: *const InboundTransportVTable_ABI,
    ) callconv(.c) HostError_ABI,

    register_cli_command: *const fn (
        kernel: *KernelHandle_ABI,
        cmd_name: [*:0]const u8,
        help_text: [*:0]const u8,
        ctx: *CommandCtx_ABI,
        exec_fn: *const fn (
            ctx: *CommandCtx_ABI,
            argv: [*]const Slice_ABI,
            argc: usize,
            out_resp: *InboundResponse_ABI,
        ) callconv(.c) HostError_ABI,
    ) callconv(.c) HostError_ABI,

    emit_log: *const fn (
        kernel: *KernelHandle_ABI,
        level: u32,
        msg: Slice_ABI,
    ) callconv(.c) HostError_ABI,

    /// Cold-path capability catalog exchange (`044A`). Host owns the JSON buffer and frees it
    /// after `on_json` returns, avoiding cross-`.so` allocator mismatches.
    get_capability_catalog_json: ?*const fn (
        kernel: *KernelHandle_ABI,
        ctx: ?*anyopaque,
        on_json: *const fn (ctx: ?*anyopaque, json: Slice_ABI) callconv(.c) void,
    ) callconv(.c) HostError_ABI = null,

    /// Non-blocking async command dispatch returning a `trace_id` immediately (`044A`/`044B`).
    async_dispatch_command: ?*const fn (
        kernel: *KernelHandle_ABI,
        req: *const InboundRequest_ABI,
        out_trace_id: *[16]u8,
    ) callconv(.c) HostError_ABI = null,

    /// Push-based inbound stream slots for WebSocket / WebView / continuous feeds (`044A`/`044B`).
    open_inbound_stream: ?*const fn (
        kernel: *KernelHandle_ABI,
        req: *const InboundRequest_ABI,
        out_handle: *?*InboundStreamHandle_ABI,
    ) callconv(.c) HostError_ABI = null,
    push_stream_chunk: ?*const fn (
        kernel: *KernelHandle_ABI,
        handle: *InboundStreamHandle_ABI,
        chunk: Slice_ABI,
    ) callconv(.c) HostError_ABI = null,
    close_inbound_stream: ?*const fn (
        kernel: *KernelHandle_ABI,
        handle: *InboundStreamHandle_ABI,
    ) callconv(.c) HostError_ABI = null,
};

pub const ExtensionManifest_ABI = extern struct {
    abi_version: u32 = EXTENSION_ABI_VERSION,
    min_engine_version: SemVer_ABI = common.SDK_VERSION,
    extension_name: [*:0]const u8,
    extension_version: SemVer_ABI,
    register: *const fn (
        kernel: *KernelHandle_ABI,
        api: *const KernelApiVTable_ABI,
        out_ext_ctx: *?*anyopaque,
    ) callconv(.c) HostError_ABI,
    deinit: ?*const fn (ext_ctx: *anyopaque) callconv(.c) void = null,

    pub fn nameSlice(self: ExtensionManifest_ABI) []const u8 {
        return std.mem.span(self.extension_name);
    }
};

