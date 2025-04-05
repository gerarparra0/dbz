const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    string: [:0]const u8,
    boolean: bool,
    integer: i32,
};

pub const Opt = struct {
    ptr: *anyopaque,

    flag: [:0]const u8,
    short: [:0]const u8,

    parseArgFn: *const fn (*anyopaque, arg: [:0]const u8) anyerror!void,
    getValueFn: *const fn (*anyopaque) Value,

    pub fn parseArg(self: Opt, arg: [:0]const u8) !void {
        return self.parseArgFn(self.ptr, arg);
    }
    pub fn getValue(self: Opt) Value {
        return self.getValueFn(self.ptr);
    }
};

pub const StringOpt = struct {
    value: [:0]const u8,
    flag: [:0]const u8,
    short: [:0]const u8,

    pub fn option(self: *StringOpt) Opt {
        return .{
            .ptr = self,
            .getValueFn = getValue,
            .parseArgFn = parseArg,
            .flag = self.flag,
            .short = self.short,
        };
    }

    fn getValue(ptr: *anyopaque) Value {
        const self = @as(*StringOpt, @ptrCast(@alignCast(ptr)));
        return Value{ .string = self.value };
    }

    fn parseArg(ptr: *anyopaque, arg: [:0]const u8) !void {
        const self = @as(*StringOpt, @ptrCast(@alignCast(ptr)));
        self.value = arg;
    }
};

pub const BooleanOpt = struct {
    value: bool,
    flag: [:0]const u8,
    short: [:0]const u8,

    pub fn option(self: *BooleanOpt) Opt {
        return .{
            .ptr = self,
            .getValueFn = getValue,
            .parseArgFn = parseArg,
            .flag = self.flag,
            .short = self.short,
        };
    }

    fn getValue(ptr: *anyopaque) Value {
        const self = @as(*BooleanOpt, @ptrCast(@alignCast(ptr)));
        return Value{ .boolean = self.value };
    }

    fn parseArg(ptr: *anyopaque, arg: [:0]const u8) !void {
        const self = @as(*BooleanOpt, @ptrCast(@alignCast(ptr)));
        if (std.mem.eql(u8, arg, "true")) self.value = true;
    }
};

pub const IntegerOpt = struct {
    value: i32,
    flag: [:0]const u8,
    short: [:0]const u8,

    pub fn option(self: *IntegerOpt) Opt {
        return .{
            .ptr = self,
            .getValueFn = getValue,
            .parseArgFn = parseArg,
            .flag = self.flag,
            .short = self.short,
        };
    }

    fn getValue(ptr: *anyopaque) Value {
        const self = @as(*IntegerOpt, @ptrCast(@alignCast(ptr)));
        return Value{ .integer = self.value };
    }

    fn parseArg(ptr: *anyopaque, arg: [:0]const u8) !void {
        const self = @as(*IntegerOpt, @ptrCast(@alignCast(ptr)));
        self.value = try std.fmt.parseInt(i32, arg, 10);
    }
};

pub const Parser = struct {
    allocator: Allocator,
    registeredOpts: std.StringHashMap(Opt),
    args: [][:0]const u8,

    pub fn init(allocator: Allocator) !Parser {
        var argIter = try std.process.argsWithAllocator(allocator);
        defer argIter.deinit();

        var argList = std.ArrayList([:0]const u8).init(allocator);
        defer argList.deinit();

        while (argIter.next()) |arg| {
            try argList.append(try allocator.dupeZ(u8, arg));
        }

        const args = try allocator.dupe([:0]const u8, argList.items);

        return Parser{
            .allocator = allocator,
            .registeredOpts = std.StringHashMap(Opt).init(allocator),
            .args = args,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.registeredOpts.deinit();

        for (self.args) |arg| {
            self.allocator.free(arg);
        }

        self.allocator.free(self.args);
    }

    pub fn getCaller(self: *Parser) ![:0]const u8 {
        return if (self.args.len > 0) self.args[0] else error.ArgError;
    }

    pub fn registerOpt(self: *Parser, opt: Opt) !void {
        if (self.registeredOpts.get(opt.flag)) |_| return error.FlagAlreadyRegistered;
        if (self.registeredOpts.get(opt.short)) |_| return error.ShortFlagAlreadyRegistered;

        try self.registeredOpts.put(opt.flag, opt);
        try self.registeredOpts.put(opt.short, opt);
    }

    pub fn registerOpts(self: *Parser, opts: []const Opt) !void {
        for (opts) |opt| {
            try self.registerOpt(opt);
        }
    }

    pub fn parse(self: *Parser) !void {
        const args = self.args[1..];
        if (args.len == 0) return error.NoArgsProvided;

        var fifo = std.fifo.LinearFifo([:0]const u8, .Dynamic).init(self.allocator);
        defer fifo.deinit();

        try fifo.write(args);

        while (fifo.readItem()) |arg| {
            const flag = try getFlag(arg);
            var opt = self.registeredOpts.getPtr(flag) orelse return error.FlagNotRegistered;
            switch (opt.getValue()) {
                .string, .integer => if (fifo.readItem()) |nextArg| try opt.parseArg(nextArg) else return error.ErrorParsingArgument,
                .boolean => try opt.parseArg("true"),
            }
        }
    }
};

fn getFlag(arg: [:0]const u8) ![:0]const u8 {
    if (!std.mem.startsWith(u8, arg, "-")) return arg;
    if (!std.mem.startsWith(u8, arg[1..], "-")) return arg[1..];
    if (!std.mem.startsWith(u8, arg[2..], "-")) return arg[2..];
    return error.InvalidFlag;
}

test "getFlag" {
    try std.testing.expect(std.mem.eql(u8, try getFlag("create"), "create"));
    try std.testing.expect(std.mem.eql(u8, try getFlag("--create"), "create"));
    try std.testing.expect(std.mem.eql(u8, try getFlag("-c"), "c"));
    try std.testing.expect(std.mem.eql(u8, try getFlag("--c"), "c"));
    try std.testing.expect(std.mem.eql(u8, try getFlag("c"), "c"));
}
