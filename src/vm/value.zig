const std: type = @import("std");

pub const Value: type = union(enum) {
    integer: u64,
    string: []const u8,

    pub fn print(self: Value) !void {
        switch (self) {
            .integer => |i| try std.io.getStdOut().writer().print("{d}\n", .{i}),
            .string => |s| try std.io.getStdOut().writer().print("{s}\n", .{s}),
        }
    }
};
