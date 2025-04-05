const std = @import("std");
const Allocator = std.mem.Allocator;
const Self = @This();

const Magic: u64 = 0xf00d;

allocator: Allocator,
metadata: ?*Metadata,

pub fn init(allocator: Allocator) Self {
    return Self{ .allocator = allocator, .metadata = null };
}

pub fn deinit(self: *Self) void {
    const meta = self.metadata orelse return;
    self.allocator.destroy(meta);
}

pub const Metadata = packed struct {
    magic: u64,
    size: u64,
    offset: u64,
};

pub fn parseMetadata(self: *Self, db: std.fs.File) !void {
    try db.seekTo(0);

    const metadata = try self.allocator.create(Metadata);
    errdefer self.allocator.destroy(metadata);

    const buf: []u8 = std.mem.asBytes(metadata);

    const read = try db.read(buf);
    if (read != @sizeOf(Metadata)) return error.CorruptedMetadata;

    if (metadata.magic != Magic) return error.InvalidMetadata;

    self.metadata = metadata;
}

pub fn createMetadata(self: *Self, db: std.fs.File) !void {
    try db.seekTo(0);

    const offset = @sizeOf(Metadata);

    const newMeta = try self.allocator.create(Metadata);
    errdefer self.allocator.destroy(newMeta);

    newMeta.magic = Magic;
    newMeta.size = offset;
    newMeta.offset = offset;
    _ = try db.write(std.mem.asBytes(newMeta));
    self.metadata = newMeta;
}
