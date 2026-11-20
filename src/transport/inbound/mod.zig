pub const envelope = @import("envelope.zig");
pub const transport = @import("transport.zig");
pub const vtables = @import("vtables.zig");

pub const InboundRequest = envelope.InboundRequest;
pub const InboundResponse = envelope.InboundResponse;
pub const ScalarEnvelope = envelope.ScalarEnvelope;
pub const RecordEnvelope = envelope.RecordEnvelope;
pub const TableEnvelope = envelope.TableEnvelope;
pub const TreeNode = envelope.TreeNode;
pub const TreeEnvelope = envelope.TreeEnvelope;
pub const DocumentEnvelope = envelope.DocumentEnvelope;

pub const HostDispatcher = transport.HostDispatcher;
pub const fetchCapabilityCatalog = transport.fetchCapabilityCatalog;
pub const defineInboundTransport = transport.defineInboundTransport;

pub const EventFilterVTable = vtables.EventFilterVTable;
pub const RendererVTable = vtables.RendererVTable;
pub const KeymapEntry = vtables.KeymapEntry;

test {
    _ = transport;
}
