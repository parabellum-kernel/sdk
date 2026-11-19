const EventKind = @import("EventKind.zig").EventKind;
const JobItem = @import("JobItem.zig").JobItem;
const StatusQuery = @import("StatusQuery.zig").StatusQuery;
const ShutdownRequest = @import("ShutdownRequest.zig").ShutdownRequest;
const CustomEvent = @import("CustomEvent.zig").CustomEvent;

pub const EventPayload = union(EventKind) {
    job: JobItem,
    status: StatusQuery,
    shutdown: ShutdownRequest,
    custom: CustomEvent,
};
