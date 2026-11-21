const common = @import("common.zig");
const driver = @import("driver.zig");

pub const Slice_ABI = common.Slice_ABI;
pub const ConfigParam_ABI = driver.ConfigParam_ABI;

pub const ValidationStatus_ABI = enum(u32) {
    ok = 0,
    invalid = 1,
    unsupported_section = 2,
};

pub const SectionValidationResult_ABI = extern struct {
    status: ValidationStatus_ABI = .ok,
    message: Slice_ABI = Slice_ABI.empty,

    pub fn ok() SectionValidationResult_ABI {
        return .{ .status = .ok, .message = Slice_ABI.empty };
    }

    pub fn invalid(msg: []const u8) SectionValidationResult_ABI {
        return .{ .status = .invalid, .message = Slice_ABI.from(msg) };
    }

    pub fn unsupported() SectionValidationResult_ABI {
        return .{ .status = .unsupported_section, .message = Slice_ABI.empty };
    }
};

/// C-ABI callback so plugins, drivers, and extensions can validate their own config sections.
pub const SectionValidatorFn_ABI = *const fn (
    ctx: ?*anyopaque,
    section_name: Slice_ABI,
    params_ptr: [*]const ConfigParam_ABI,
    params_len: usize,
) callconv(.c) SectionValidationResult_ABI;

pub const ConfigFormat_ABI = enum(u32) {
    yaml = 0,
    json = 1,
    custom = 2,
};

/// C-ABI callback so apps/extensions can pass raw config (e.g. YAML) to the engine for validation.
pub const ConfigValidateFn_ABI = *const fn (
    ctx: ?*anyopaque,
    format: ConfigFormat_ABI,
    raw_config: Slice_ABI,
) callconv(.c) SectionValidationResult_ABI;
