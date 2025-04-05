const std = @import("std");
const args = @import("args.zig");
const db = @import("db.zig");

pub fn main() !void {
    var dbga = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(dbga.deinit() == .ok);
    const allocator = dbga.allocator();

    var parser = try args.Parser.init(allocator);
    defer parser.deinit();

    var fileOpt = args.StringOpt{ .value = "db.db", .optMeta = .{ .flag = "file", .short = "f" } };
    var createOpt = args.BooleanOpt{ .value = false, .optMeta = .{ .flag = "create", .short = "c" } };

    try parser.registerOpts(&[_]args.Opt{
        fileOpt.option(),
        createOpt.option(),
    });
    try parser.parse();

    var dbFile: std.fs.File = undefined;

    var dbParser = db.init(allocator);
    defer dbParser.deinit();

    if (createOpt.value) {
        dbFile = try std.fs.cwd().createFile(fileOpt.value, .{});
        try dbParser.createMetadata(dbFile);
    } else {
        dbFile = try std.fs.cwd().openFile(fileOpt.value, .{});
        try dbParser.parseMetadata(dbFile);
    }

    defer dbFile.close();
}
