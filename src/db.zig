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

    const metaPtr: []u8 = std.mem.asBytes(metadata);

    const src = try self.allocator.alloc(u8, metaPtr.len);
    defer self.allocator.free(src);

    const read = try db.read(src);

    bytesToNative(src, metaPtr);

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
    newMeta.size = 0;
    newMeta.offset = offset;

    const src: []u8 = std.mem.asBytes(newMeta);

    const dest = try self.allocator.alloc(u8, src.len);
    defer self.allocator.free(dest);

    bytesToBig(src, dest);

    _ = try db.write(dest);
    self.metadata = newMeta;
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
