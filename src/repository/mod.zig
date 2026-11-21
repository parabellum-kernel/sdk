const std = @import("std");

pub const specs = @import("specs.zig");
pub const capabilities = @import("capabilities.zig");
pub const row_iterator = @import("row_iterator.zig");
pub const repository = @import("repository.zig");

pub const StorageCapabilities = capabilities.StorageCapabilities;

pub const Repository = repository.Repository;
pub const RepositoryVTable = repository.RepositoryVTable;
pub const StorageRepository = repository.StorageRepository;
pub const StorageRepositoryVTable = repository.StorageRepositoryVTable;

pub const WriteMode = specs.WriteMode;
pub const WriteSpec = specs.WriteSpec;
pub const ReadSpec = specs.ReadSpec;
pub const RecordMap = specs.RecordMap;
pub const OrderByColumn = specs.OrderByColumn;
pub const SortOrder = specs.SortOrder;
pub const ProjectionMode = specs.ProjectionMode;
pub const RowIterator = row_iterator.RowIterator;

test {
    _ = std.testing.refAllDecls(@This());
}
