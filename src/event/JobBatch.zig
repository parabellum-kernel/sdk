const JobItem = @import("JobItem.zig").JobItem;

/// Bounded batch of `JobItem`s submitted together under a shared `batch_id`
/// for aggregated progress tracking and bulk cancellation.
pub const JobBatch = struct {
    batch_id: []const u8 = "",
    items: []const JobItem = &.{},
};
