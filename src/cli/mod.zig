const std = @import("std");

pub const OptionKind = enum {
    /// Boolean presence flag (e.g. `--verbose`, `-q`).
    flag,
    /// Single string value option (e.g. `--target x86_64-linux-gnu`, `-C /tmp`).
    value,
    /// Repeatable string value option (e.g. `-x test -x package`).
    multi_value,
};

pub const CliAction = enum {
    run,
    help,
    version,
};

pub const OptionSpec = struct {
    /// Long option name without leading `--` (e.g. "dry-run").
    long: []const u8,
    /// Optional single-character short flag without leading `-` (e.g. 'n').
    short: ?u8 = null,
    /// Value placeholder shown in help output (e.g. "<path>").
    value_name: ?u8_slice = null,
    kind: OptionKind = .flag,
    description: []const u8 = "",

    const u8_slice = []const u8;

    /// Convenience helper to derive `long` from an enum tag name (replacing '_' with '-').
    pub fn fromEnum(
        comptime tag: anytype,
        short: ?u8,
        kind: OptionKind,
        value_name: ?[]const u8,
        description: []const u8,
    ) OptionSpec {
        const raw_name = @tagName(tag);
        const dashed: []const u8 = comptime blk: {
            var buf: [raw_name.len]u8 = undefined;
            for (raw_name, 0..) |ch, i| {
                buf[i] = if (ch == '_') '-' else ch;
            }
            const final = buf;
            break :blk &final;
        };
        return .{
            .long = dashed,
            .short = short,
            .kind = kind,
            .value_name = value_name,
            .description = description,
        };
    }
};

pub const CommandSpec = struct {
    name: []const u8,
    description: []const u8 = "",
    positional_name: ?[]const u8 = null,
    options: []const OptionSpec = &.{},
    allow_unknown_options: bool = false,

    pub fn fromEnum(
        comptime tag: anytype,
        description: []const u8,
        positional_name: ?[]const u8,
        options: []const OptionSpec,
    ) CommandSpec {
        return .{
            .name = @tagName(tag),
            .description = description,
            .positional_name = positional_name,
            .options = options,
        };
    }
};

pub const AppSpec = struct {
    name: []const u8,
    version: []const u8 = "0.1.0",
    description: []const u8 = "",
    global_options: []const OptionSpec = &.{},
    commands: []const CommandSpec = &.{},
    allow_unknown_commands: bool = false,
};

pub const CliBuilder = struct {
    alloc: std.mem.Allocator,
    name: []const u8,
    version: []const u8,
    description: []const u8 = "",
    allow_unknown_commands: bool = false,
    global_options: std.ArrayListUnmanaged(OptionSpec) = .empty,
    commands: std.ArrayListUnmanaged(CommandSpec) = .empty,

    pub fn init(alloc: std.mem.Allocator, name: []const u8, version: []const u8) CliBuilder {
        return .{
            .alloc = alloc,
            .name = name,
            .version = version,
        };
    }

    pub fn deinit(self: *CliBuilder) void {
        self.global_options.deinit(self.alloc);
        self.commands.deinit(self.alloc);
    }

    pub fn withDescription(self: *CliBuilder, desc: []const u8) *CliBuilder {
        self.description = desc;
        return self;
    }

    pub fn allowUnknownCommands(self: *CliBuilder, allow: bool) *CliBuilder {
        self.allow_unknown_commands = allow;
        return self;
    }

    pub fn addGlobalOption(self: *CliBuilder, opt: OptionSpec) !*CliBuilder {
        try self.global_options.append(self.alloc, opt);
        return self;
    }

    pub fn addGlobalOptions(self: *CliBuilder, opts: []const OptionSpec) !*CliBuilder {
        try self.global_options.appendSlice(self.alloc, opts);
        return self;
    }

    pub fn addCommand(self: *CliBuilder, cmd: CommandSpec) !*CliBuilder {
        try self.commands.append(self.alloc, cmd);
        return self;
    }

    pub fn addCommands(self: *CliBuilder, cmds: []const CommandSpec) !*CliBuilder {
        try self.commands.appendSlice(self.alloc, cmds);
        return self;
    }

    pub fn build(self: *CliBuilder) !CliApp {
        const globals = try self.global_options.toOwnedSlice(self.alloc);
        errdefer self.alloc.free(globals);
        const cmds = try self.commands.toOwnedSlice(self.alloc);
        return .{
            .alloc = self.alloc,
            .owns_slices = true,
            .spec = .{
                .name = self.name,
                .version = self.version,
                .description = self.description,
                .global_options = globals,
                .commands = cmds,
                .allow_unknown_commands = self.allow_unknown_commands,
            },
        };
    }
};

pub const ParsedOption = struct {
    name: []const u8,
    values: std.ArrayListUnmanaged([]const u8) = .empty,
    is_flag: bool = false,
};

pub const ParsedCli = struct {
    alloc: std.mem.Allocator,
    action: CliAction = .run,
    help_command: ?[]const u8 = null,
    commands: std.ArrayListUnmanaged([]const u8) = .empty,
    positionals: std.ArrayListUnmanaged([]const u8) = .empty,
    options: std.StringHashMapUnmanaged(ParsedOption) = .empty,
    error_message: ?[]const u8 = null,

    pub fn deinit(self: *ParsedCli) void {
        self.commands.deinit(self.alloc);
        self.positionals.deinit(self.alloc);
        var it = self.options.valueIterator();
        while (it.next()) |opt| {
            opt.values.deinit(self.alloc);
        }
        self.options.deinit(self.alloc);
        if (self.error_message) |msg| self.alloc.free(msg);
    }

    pub fn primaryCommand(self: *const ParsedCli) ?[]const u8 {
        if (self.commands.items.len == 0) return null;
        return self.commands.items[0];
    }

    pub fn hasFlag(self: *const ParsedCli, name: []const u8) bool {
        const opt = self.options.get(name) orelse return false;
        return opt.is_flag or opt.values.items.len > 0;
    }

    pub fn getValue(self: *const ParsedCli, name: []const u8) ?[]const u8 {
        const opt = self.options.get(name) orelse return null;
        if (opt.values.items.len == 0) return null;
        return opt.values.items[opt.values.items.len - 1];
    }

    pub fn getValues(self: *const ParsedCli, name: []const u8) []const []const u8 {
        const opt = self.options.get(name) orelse return &.{};
        return opt.values.items;
    }

    fn setFlag(self: *ParsedCli, name: []const u8) !void {
        const gop = try self.options.getOrPut(self.alloc, name);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .name = name, .is_flag = true };
        } else {
            gop.value_ptr.is_flag = true;
        }
    }

    fn addValue(self: *ParsedCli, name: []const u8, val: []const u8, replace: bool) !void {
        const gop = try self.options.getOrPut(self.alloc, name);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .name = name, .is_flag = false };
        }
        if (replace) {
            gop.value_ptr.values.clearRetainingCapacity();
        }
        try gop.value_ptr.values.append(self.alloc, val);
    }

    /// Serializes parsed command, options, and positionals into a JSON object string.
    pub fn toArgsJson(self: *const ParsedCli, alloc: std.mem.Allocator, is_custom: bool) ![]u8 {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        errdefer out.deinit(alloc);

        try out.appendSlice(alloc, "{\"custom\":");
        try out.appendSlice(alloc, if (is_custom) "true" else "false");

        if (self.primaryCommand()) |cmd| {
            try out.appendSlice(alloc, ",\"command\":");
            try appendJsonString(&out, alloc, cmd);
        }

        try out.appendSlice(alloc, ",\"options\":{");
        var first_opt = true;
        var it = self.options.iterator();
        while (it.next()) |entry| {
            if (!first_opt) try out.append(alloc, ',');
            first_opt = false;
            try appendJsonString(&out, alloc, entry.key_ptr.*);
            try out.append(alloc, ':');
            const opt = entry.value_ptr.*;
            if (opt.is_flag and opt.values.items.len == 0) {
                try out.appendSlice(alloc, "true");
            } else if (opt.values.items.len == 1) {
                try appendJsonString(&out, alloc, opt.values.items[0]);
            } else {
                try out.append(alloc, '[');
                for (opt.values.items, 0..) |v, idx| {
                    if (idx > 0) try out.append(alloc, ',');
                    try appendJsonString(&out, alloc, v);
                }
                try out.append(alloc, ']');
            }
        }
        try out.appendSlice(alloc, "},\"positionals\":[");
        for (self.positionals.items, 0..) |pos, idx| {
            if (idx > 0) try out.append(alloc, ',');
            try appendJsonString(&out, alloc, pos);
        }
        try out.appendSlice(alloc, "]}");

        return try out.toOwnedSlice(alloc);
    }
};

fn appendJsonString(out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, s: []const u8) !void {
    try out.append(alloc, '"');
    for (s) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(alloc, "\\\""),
            '\\' => try out.appendSlice(alloc, "\\\\"),
            '\n' => try out.appendSlice(alloc, "\\n"),
            '\r' => try out.appendSlice(alloc, "\\r"),
            '\t' => try out.appendSlice(alloc, "\\t"),
            else => try out.append(alloc, ch),
        }
    }
    try out.append(alloc, '"');
}

pub const ParseError = error{
    UnknownOption,
    MissingOptionValue,
    UnknownCommand,
    OutOfMemory,
};

pub const CliApp = struct {
    alloc: ?std.mem.Allocator = null,
    owns_slices: bool = false,
    spec: AppSpec,

    pub fn fromSpec(spec: AppSpec) CliApp {
        return .{
            .alloc = null,
            .owns_slices = false,
            .spec = spec,
        };
    }

    pub fn deinit(self: *CliApp) void {
        if (self.owns_slices) {
            if (self.alloc) |a| {
                a.free(self.spec.global_options);
                a.free(self.spec.commands);
            }
        }
    }

    pub fn findCommand(self: *const CliApp, name: []const u8) ?CommandSpec {
        for (self.spec.commands) |cmd| {
            if (std.mem.eql(u8, cmd.name, name)) return cmd;
        }
        return null;
    }

    fn findOption(
        self: *const CliApp,
        active_cmd: ?CommandSpec,
        matched_cmds: []const []const u8,
        long_name: []const u8,
    ) ?OptionSpec {
        // Command-specific options take precedence over global options (e.g. `add --version`).
        if (active_cmd) |cmd| {
            for (cmd.options) |opt| {
                if (std.mem.eql(u8, opt.long, long_name)) return opt;
            }
        }
        for (matched_cmds) |cname| {
            if (self.findCommand(cname)) |cmd| {
                for (cmd.options) |opt| {
                    if (std.mem.eql(u8, opt.long, long_name)) return opt;
                }
            }
        }
        for (self.spec.global_options) |opt| {
            if (std.mem.eql(u8, opt.long, long_name)) return opt;
        }
        return null;
    }

    fn findShortOption(
        self: *const CliApp,
        active_cmd: ?CommandSpec,
        matched_cmds: []const []const u8,
        short_ch: u8,
    ) ?OptionSpec {
        if (active_cmd) |cmd| {
            for (cmd.options) |opt| {
                if (opt.short == short_ch) return opt;
            }
        }
        for (matched_cmds) |cname| {
            if (self.findCommand(cname)) |cmd| {
                for (cmd.options) |opt| {
                    if (opt.short == short_ch) return opt;
                }
            }
        }
        for (self.spec.global_options) |opt| {
            if (opt.short == short_ch) return opt;
        }
        return null;
    }

    pub fn parse(self: *const CliApp, alloc: std.mem.Allocator, argv: []const []const u8) ParseError!ParsedCli {
        var parsed = ParsedCli{ .alloc = alloc };
        errdefer parsed.deinit();

        if (argv.len <= 1) {
            parsed.action = .help;
            return parsed;
        }

        var active_cmd: ?CommandSpec = null;
        var passthrough = false;

        var i: usize = 1;
        while (i < argv.len) : (i += 1) {
            const arg = argv[i];
            if (passthrough) {
                try parsed.positionals.append(alloc, arg);
                continue;
            }
            if (std.mem.eql(u8, arg, "--")) {
                passthrough = true;
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--")) {
                const body = arg[2..];
                const eq_idx = std.mem.indexOfScalar(u8, body, '=');
                const opt_name = if (eq_idx) |idx| body[0..idx] else body;
                const inline_val = if (eq_idx) |idx| body[idx + 1 ..] else null;

                if (std.mem.eql(u8, opt_name, "help")) {
                    parsed.action = .help;
                    if (active_cmd) |cmd| parsed.help_command = cmd.name;
                    continue;
                }
                if (std.mem.eql(u8, opt_name, "version") and self.findOption(active_cmd, parsed.commands.items, "version") == null) {
                    if (active_cmd == null) {
                        parsed.action = .version;
                        continue;
                    }
                }

                const opt = self.findOption(active_cmd, parsed.commands.items, opt_name) orelse {
                    // Top-level --version fallback if not overridden
                    if (std.mem.eql(u8, opt_name, "version") and active_cmd == null) {
                        parsed.action = .version;
                        continue;
                    }
                    if (active_cmd) |cmd| {
                        if (cmd.allow_unknown_options) {
                            try parsed.positionals.append(alloc, arg);
                            continue;
                        }
                    }
                    parsed.error_message = try std.fmt.allocPrint(alloc, "Unknown option '--{s}'", .{opt_name});
                    return error.UnknownOption;
                };

                // Top-level --version when defined as a global option and no command is active yet.
                if (std.mem.eql(u8, opt.long, "version") and active_cmd == null and opt.kind == .flag) {
                    parsed.action = .version;
                    continue;
                }

                switch (opt.kind) {
                    .flag => try parsed.setFlag(opt.long),
                    .value, .multi_value => {
                        const val = inline_val orelse blk: {
                            if (i + 1 >= argv.len) {
                                parsed.error_message = try std.fmt.allocPrint(alloc, "Option '--{s}' requires a value", .{opt.long});
                                return error.MissingOptionValue;
                            }
                            i += 1;
                            break :blk argv[i];
                        };
                        try parsed.addValue(opt.long, val, opt.kind == .value);
                    },
                }
                continue;
            }

            if (arg.len > 1 and arg[0] == '-') {
                const short_ch = arg[1];
                if (short_ch == 'h') {
                    parsed.action = .help;
                    if (active_cmd) |cmd| parsed.help_command = cmd.name;
                    continue;
                }
                if (short_ch == 'v' and active_cmd == null) {
                    if (self.findShortOption(null, &.{}, 'v')) |v_opt| {
                        if (std.mem.eql(u8, v_opt.long, "version") and v_opt.kind == .flag) {
                            parsed.action = .version;
                            continue;
                        }
                    } else {
                        parsed.action = .version;
                        continue;
                    }
                }

                const opt = self.findShortOption(active_cmd, parsed.commands.items, short_ch) orelse {
                    if (active_cmd) |cmd| {
                        if (cmd.allow_unknown_options) {
                            try parsed.positionals.append(alloc, arg);
                            continue;
                        }
                    }
                    parsed.error_message = try std.fmt.allocPrint(alloc, "Unknown option '-{c}'", .{short_ch});
                    return error.UnknownOption;
                };

                switch (opt.kind) {
                    .flag => try parsed.setFlag(opt.long),
                    .value, .multi_value => {
                        const val = if (arg.len > 2) arg[2..] else blk: {
                            if (i + 1 >= argv.len) {
                                parsed.error_message = try std.fmt.allocPrint(alloc, "Option '-{c}' requires a value", .{short_ch});
                                return error.MissingOptionValue;
                            }
                            i += 1;
                            break :blk argv[i];
                        };
                        try parsed.addValue(opt.long, val, opt.kind == .value);
                    },
                }
                continue;
            }

            // Positional or command token
            if (std.mem.eql(u8, arg, "help") and active_cmd == null) {
                parsed.action = .help;
                if (i + 1 < argv.len) {
                    const next_arg = argv[i + 1];
                    if (self.findCommand(next_arg) != null) {
                        parsed.help_command = next_arg;
                        i += 1;
                    }
                }
                continue;
            }

            if (self.findCommand(arg)) |cmd| {
                try parsed.commands.append(alloc, cmd.name);
                active_cmd = cmd;
                continue;
            }

            if (active_cmd == null) {
                if (self.spec.allow_unknown_commands) {
                    try parsed.commands.append(alloc, arg);
                    active_cmd = .{ .name = arg, .allow_unknown_options = true };
                    continue;
                }
                parsed.error_message = try std.fmt.allocPrint(alloc, "Unknown command '{s}'", .{arg});
                return error.UnknownCommand;
            }

            try parsed.positionals.append(alloc, arg);
        }

        if (parsed.commands.items.len == 0 and parsed.action == .run) {
            parsed.action = .help;
        }
        return parsed;
    }

    pub fn formatHelp(self: *const CliApp, alloc: std.mem.Allocator, command_name: ?[]const u8) ![]u8 {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        errdefer out.deinit(alloc);

        if (command_name) |cname| {
            if (self.findCommand(cname)) |cmd| {
                try appendFmt(&out, alloc, "{s} {s}", .{ self.spec.name, cmd.name });
                if (cmd.description.len > 0) {
                    try appendFmt(&out, alloc, " - {s}", .{cmd.description});
                }
                try out.appendSlice(alloc, "\n\nUsage:\n");
                if (cmd.positional_name) |pos| {
                    try appendFmt(&out, alloc, "  {s} {s} [{s}] [options]\n", .{ self.spec.name, cmd.name, pos });
                } else {
                    try appendFmt(&out, alloc, "  {s} {s} [options]\n", .{ self.spec.name, cmd.name });
                }
                if (cmd.options.len > 0) {
                    try out.appendSlice(alloc, "\nOptions:\n");
                    try appendOptions(&out, alloc, cmd.options);
                }
                if (self.spec.global_options.len > 0) {
                    try out.appendSlice(alloc, "\nGlobal options:\n");
                    try appendOptions(&out, alloc, self.spec.global_options);
                }
                return try out.toOwnedSlice(alloc);
            }
        }

        try appendFmt(&out, alloc, "{s}", .{self.spec.name});
        if (self.spec.description.len > 0) {
            try appendFmt(&out, alloc, " - {s}", .{self.spec.description});
        }
        try out.appendSlice(alloc, "\n\nUsage:\n");
        try appendFmt(&out, alloc, "  {s} <command> [options]\n", .{self.spec.name});

        if (self.spec.commands.len > 0) {
            try out.appendSlice(alloc, "\nCommands:\n");
            for (self.spec.commands) |cmd| {
                try appendFmt(&out, alloc, "  {s:<12} {s}\n", .{ cmd.name, cmd.description });
            }
        }

        if (self.spec.global_options.len > 0) {
            try out.appendSlice(alloc, "\nGlobal options:\n");
            try appendOptions(&out, alloc, self.spec.global_options);
        }

        return try out.toOwnedSlice(alloc);
    }
};

fn appendFmt(out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(alloc, fmt, args);
    defer alloc.free(s);
    try out.appendSlice(alloc, s);
}

fn appendOptions(out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, opts: []const OptionSpec) !void {
    for (opts) |opt| {
        var left_buf: [64]u8 = undefined;
        var pos: usize = 0;
        if (opt.short) |s| {
            const part = std.fmt.bufPrint(left_buf[pos..], "-{c}, ", .{s}) catch "";
            pos += part.len;
        } else {
            const part = std.fmt.bufPrint(left_buf[pos..], "    ", .{}) catch "";
            pos += part.len;
        }
        const long_part = std.fmt.bufPrint(left_buf[pos..], "--{s}", .{opt.long}) catch "";
        pos += long_part.len;
        if (opt.value_name) |vn| {
            const val_part = std.fmt.bufPrint(left_buf[pos..], " {s}", .{vn}) catch "";
            pos += val_part.len;
        }
        const left = left_buf[0..pos];
        try appendFmt(out, alloc, "  {s:<28} {s}\n", .{ left, opt.description });
    }
}

test "CliBuilder parses commands, chained goals, global and command flags" {
    const alloc = std.testing.allocator;
    const Goal = enum { clean, fetch, install };
    const Flag = enum { dry_run, exclude, verbose };

    var builder = CliBuilder.init(alloc, "hive", "0.1.0");
    _ = builder.withDescription("native build tool");
    _ = try builder.addGlobalOption(OptionSpec.fromEnum(Flag.verbose, null, .flag, null, "Verbose output"));
    _ = try builder.addGlobalOption(OptionSpec.fromEnum(Flag.exclude, 'x', .multi_value, "<goal>", "Exclude goal"));
    _ = try builder.addCommand(CommandSpec.fromEnum(Goal.clean, "Clean caches", "target", &.{
        OptionSpec.fromEnum(Flag.dry_run, 'n', .flag, null, "Dry run"),
    }));
    _ = try builder.addCommand(CommandSpec.fromEnum(Goal.fetch, "Fetch deps", null, &.{}));
    _ = try builder.addCommand(CommandSpec.fromEnum(Goal.install, "Install artifacts", null, &.{}));

    var app = try builder.build();
    defer app.deinit();

    const argv = [_][]const u8{ "hive", "clean", "install", "-n", "-x", "test", "-x", "package", "--verbose" };
    var parsed = try app.parse(alloc, &argv);
    defer parsed.deinit();

    try std.testing.expectEqual(CliAction.run, parsed.action);
    try std.testing.expectEqual(@as(usize, 2), parsed.commands.items.len);
    try std.testing.expectEqualStrings("clean", parsed.commands.items[0]);
    try std.testing.expectEqualStrings("install", parsed.commands.items[1]);
    try std.testing.expect(parsed.hasFlag("dry-run"));
    try std.testing.expect(parsed.hasFlag("verbose"));
    const excluded = parsed.getValues("exclude");
    try std.testing.expectEqual(@as(usize, 2), excluded.len);
    try std.testing.expectEqualStrings("test", excluded[0]);
    try std.testing.expectEqualStrings("package", excluded[1]);

    const json = try parsed.toArgsJson(alloc, false);
    defer alloc.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":\"clean\"") != null);
}
