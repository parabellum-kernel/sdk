/// Extensible event kind for daemon-level inbound communication.
pub const EventKind = enum(u32) {
    job = 0,
    status = 1,
    shutdown = 2,
    custom = 3,
};
