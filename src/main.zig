const std: type = @import("std");
const vm: type = @import("vm/vm.zig");
const io: type = @import("io.zig");
const VM: type = vm.VM;

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

    var buffer: [65536]u8 = undefined;
    const bytes_read = try file.read(&buffer);
    const bytes = buffer[0..bytes_read];

    var machine: VM = VM.init(allocator);
    defer machine.deinit();

    try machine.execute(bytes);
}
