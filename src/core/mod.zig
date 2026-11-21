const std = @import("std");
const abi_common = @import("../abi/common.zig");

/// Fundamental ecosystem primitives shared across SDK modules (`repository`, `driver`, `task`, `extension`).
pub const Slice_ABI = abi_common.Slice_ABI;
pub const HostError_ABI = abi_common.HostError_ABI;
pub const SemVer_ABI = abi_common.SemVer_ABI;
pub const RowView_ABI = abi_common.RowView_ABI;
pub const NamedField_ABI = abi_common.NamedField_ABI;
pub const SDK_VERSION = abi_common.SDK_VERSION;

/// Generic key-value configuration parameter used by repositories, drivers, and extensions.
pub const ConfigParam = struct {
    key: []const u8,
    value: []const u8,
};

/// Opaque handle for stream-backed payloads (e.g., out-of-core or piece-table streams)
/// whose concrete implementation lives inside the closed-source engine.
pub const StreamBackingHandle = *const anyopaque;

pub const payload = @import("payload.zig");
pub const PayloadHandle = payload.PayloadHandle;
pub const PayloadRepr = payload.PayloadRepr;
pub const ReflectedValue = payload.ReflectedValue;
pub const ReflectFn = payload.ReflectFn;
pub const ContextualReflectFn = payload.ContextualReflectFn;
pub const OpaqueReflectAbiFn = payload.OpaqueReflectAbiFn;
pub const OpaqueReflectedValueAbi = payload.OpaqueReflectedValueAbi;

test {
    _ = std.testing.refAllDecls(@This());
}
