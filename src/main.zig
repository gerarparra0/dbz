const std = @import("std");
const args = @import("args.zig");
pub fn main() !void {
    var dbga = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(dbga.deinit() == .ok);
    const allocator = dbga.allocator();

    var parser = try args.Parser.init(allocator);
    defer parser.deinit();

    var strOpt = args.StringOpt{ .value = "defaultValue", .optMeta = .{ .flag = "file", .short = "f" } };
    var boolOpt = args.BooleanOpt{ .value = false, .optMeta = .{ .flag = "create", .short = "c" } };
    var intOpt = args.IntegerOpt{ .value = 0, .optMeta = .{ .flag = "count", .short = "t" } };

    try parser.registerOpts(&[_]args.Opt{ strOpt.option(), boolOpt.option(), intOpt.option() });
    try parser.parse();

    std.debug.print("{s}: {s}\n", .{ strOpt.optMeta.flag, strOpt.value });
    std.debug.print("{s}: {any}\n", .{ boolOpt.optMeta.flag, boolOpt.value });
    std.debug.print("{s}: {d}", .{ intOpt.optMeta.flag, intOpt.value });
}
