const core = @import("../core/mod.zig");
const PayloadHandle = core.PayloadHandle;

/// Write mode controlling how payload rows are merged with existing storage rows.
pub const WriteMode = enum {
    upsert,
    append,
    update,
    replace_all,
    delete,
};

/// Sort order for a single `ReadSpec` ordering column.
pub const SortOrder = enum { asc, desc };

/// One column in an `order_by` clause.
pub const OrderByColumn = struct {
    column: []const u8,
    order: SortOrder = .asc,
};

/// Projection mode for `ReadSpec`.
pub const ProjectionMode = union(enum) {
    all,
    include: []const []const u8,
    exclude: []const []const u8,
};

/// Engine-agnostic write specification.
pub const WriteSpec = struct {
    table: []const u8,
    mode: WriteMode = .upsert,
    payload: PayloadHandle,
    record_map: ?*const RecordMap = null,
};

/// Pre-compiled mapping from a payload struct's fields to target table columns.
pub const RecordMap = struct {
    type_name: []const u8,
    table_name: []const u8,
    columns: []const ColumnMapping,

    pub const ColumnMapping = struct {
        column: []const u8,
        byte_offset: ?usize,
        is_pk: bool = false,
        nullable: bool = false,
    };
};

/// Engine-agnostic read specification.
pub const ReadSpec = struct {
    table: []const u8,
    where: ?*const anyopaque = null,
    order_by: []const OrderByColumn = &.{},
    limit: usize = 0,
    offset: usize = 0,
    projection: ProjectionMode = .all,
    record_map: ?*const RecordMap = null,
};
