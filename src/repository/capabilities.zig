/// Universal storage repository capability flags.
pub const StorageCapabilities = struct {
    transactions: bool = false,
    savepoints: bool = false,
    partial_update: bool = false,
    filter_pushdown: bool = false,
    order_pushdown: bool = false,
    relational_constraints: bool = false,
    schema_ddl: bool = false,
    streaming: bool = false,
    streaming_write: bool = false,
};
