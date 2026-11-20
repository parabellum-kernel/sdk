const EventKind = @import("EventKind.zig").EventKind;
const JobItem = @import("JobItem.zig").JobItem;
const JobBatch = @import("JobBatch.zig").JobBatch;
const StatusQuery = @import("StatusQuery.zig").StatusQuery;
const ShutdownRequest = @import("ShutdownRequest.zig").ShutdownRequest;
const CustomEvent = @import("CustomEvent.zig").CustomEvent;

pub const EventPayload = union(EventKind) {
    job: JobItem,
    status: StatusQuery,
    shutdown: ShutdownRequest,
    custom: CustomEvent,
    job_batch: JobBatch,
};
