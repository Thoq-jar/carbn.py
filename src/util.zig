const std: type = @import("std");

pub fn print(message: []const u8, format: anytype) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}", .{message});
    try stdout.print("{}", .{format});
    try stdout.print("\n", .{});
}
