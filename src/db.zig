const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Self = @This();

const Magic: u64 = 0xf00d;
const Version: u64 = 1;
const MaxStrLen: u64 = 64;

pub const Metadata = extern struct {
    magic: u64,
    version: u64,
    size: u64,
    users: u64,
};

pub const User = extern struct {
    salary: f64,
    name: [MaxStrLen:0]u8,
    address: [MaxStrLen:0]u8,
};

allocator: Allocator,
metadata: ?*Metadata,

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,
        .metadata = null,
    };
}

pub fn deinit(self: *Self) void {
    const meta = self.metadata orelse return;
    self.allocator.destroy(meta);
}

pub fn parseDatabase(self: *Self, dbFile: std.fs.File) !void {
    try parseMetadata(self, dbFile);

    std.debug.print("magic: {d}\nversion: {d}\nsize: {d}\nusers: {d}", .{
        self.metadata.?.magic,
        self.metadata.?.version,
        self.metadata.?.size,
        self.metadata.?.users,
    });
}

pub fn createDatabase(self: *Self, dbFile: std.fs.File) !void {
    try createMetadata(self, dbFile);
}

fn parseMetadata(self: *Self, db: std.fs.File) !void {
    const metadata = try self.allocator.create(Metadata);
    errdefer self.allocator.destroy(metadata);

    const metaPtr: []u8 = std.mem.asBytes(metadata);
    assert(metaPtr.len == @sizeOf(Metadata));
    const read = try self.readBytesFromPosition(db, metaPtr, 0);
    if (read != @sizeOf(Metadata)) return error.CorruptedMetadata;
    if (metadata.magic != Magic) return error.InvalidMetadata;
    const stat = try db.stat();
    if (stat.size != metadata.size) return error.CorruptedDatabaseFile;

    self.metadata = metadata;
}

fn createMetadata(self: *Self, db: std.fs.File) !void {
    const newMeta = try self.allocator.create(Metadata);
    errdefer self.allocator.destroy(newMeta);

    newMeta.magic = Magic;
    newMeta.version = Version;
    newMeta.size = @sizeOf(Metadata);
    newMeta.users = 0;

    const metaBytes: []u8 = std.mem.asBytes(newMeta);
    assert(metaBytes.len == @sizeOf(Metadata));
    const written = try self.writeBytesAtPosition(db, metaBytes, 0);
    if (written != metaBytes.len) return error.WritingMetadata;

    self.metadata = newMeta;
}

pub fn insert(self: *Self, db: std.fs.File, userStr: [:0]const u8) !void {
    var iter = std.mem.splitSequence(u8, userStr, ",");
    const name: []const u8 = iter.next() orelse return error.ParsingName;
    const address: []const u8 = iter.next() orelse return error.ParsingAddress;
    const salaryStr: []const u8 = iter.next() orelse return error.ParsingSalary;
    const salary = std.fmt.parseFloat(f64, salaryStr) catch return error.ParsingSalary;

    const userToInsert = try self.allocator.create(User);
    defer self.allocator.destroy(userToInsert);

    assert(address.len <= userToInsert.address.len);
    assert(name.len <= userToInsert.name.len);
    std.mem.copyForwards(u8, &userToInsert.address, address);
    std.mem.copyForwards(u8, &userToInsert.name, name);
    userToInsert.salary = salary;

    const userBytes: []u8 = std.mem.asBytes(userToInsert);
    var written = try self.writeBytesAtPosition(db, userBytes, @sizeOf(User) * self.metadata.?.users + @sizeOf(Metadata));
    if (written != userBytes.len) return error.WritingUser;

    self.metadata.?.size += @sizeOf(User);
    self.metadata.?.users += 1;

    const metaBytes: []u8 = std.mem.asBytes(self.metadata.?);
    written = try self.writeBytesAtPosition(db, metaBytes, 0);
    if (written != metaBytes.len) return error.WritingMetadata;
}

fn writeBytesAtPosition(self: *Self, db: std.fs.File, bts: []u8, pos: u64) !usize {
    const bytesToWrite = try self.allocator.alloc(u8, bts.len);
    defer self.allocator.free(bytesToWrite);
    bytesToBig(bts, bytesToWrite);

    try db.seekTo(pos);

    return db.write(bytesToWrite);
}

fn readBytesFromPosition(self: *Self, db: std.fs.File, bts: []u8, pos: u64) !usize {
    const bytesToReadBuf = try self.allocator.alloc(u8, bts.len);
    defer self.allocator.free(bytesToReadBuf);

    try db.seekTo(pos);

    const read = try db.read(bytesToReadBuf);
    bytesToNative(bytesToReadBuf, bts);

    return read;
}

fn bytesToBig(src: []u8, dest: []u8) void {
    std.debug.assert(src.len == dest.len);

    for (src, 0..) |byte, i| {
        dest[i] = std.mem.nativeToBig(u8, byte);
    }
}

fn bytesToNative(src: []u8, dest: []u8) void {
    std.debug.assert(src.len == dest.len);

    for (src, 0..) |byte, i| {
        dest[i] = std.mem.bigToNative(u8, byte);
    }
}
