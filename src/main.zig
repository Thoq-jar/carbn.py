const std = @import("std");
const vm = @import("vm.zig");
const io = @import("io.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();

    const bytecode_path = args.next() orelse {
        try io.print("Usage: zig build run -- <bytecode_file.crbn>\n", .{});
        return error.InvalidArguments;
    };

    var file = std.fs.cwd().openFile(bytecode_path, .{}) catch |err| {
        return err;
    };
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(bytes);

    var machine = vm.VM.init(allocator);
    defer machine.deinit();

    try machine.execute(bytes);
}
