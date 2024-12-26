const std = @import("std");
const Allocator = std.mem.Allocator;

const OpCode = enum(u8) {
    PRINT = 1,
    LOAD_CONST = 2,
    LOAD_INT = 3,
    LOOP_START = 4,
    LOOP_END = 5,
    LOAD_VAR = 6,
    STDIN = 7,
    STORE = 8,
};

const Value = union(enum) {
    integer: i64,
    string: []const u8,

    pub fn print(self: Value) !void {
        switch (self) {
            .integer => |i| try std.io.getStdOut().writer().print("{d}\n", .{i}),
            .string => |s| try std.io.getStdOut().writer().print("{s}\n", .{s}),
        }
    }
};

pub const VM = struct {
    allocator: Allocator,
    stack: std.ArrayList(Value),
    current_loop_index: u64,
    loop_end: u64,
    variables: std.StringHashMap(Value),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .stack = std.ArrayList(Value).init(allocator),
            .current_loop_index = 0,
            .loop_end = 0,
            .variables = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
        self.variables.deinit();
    }

    pub fn execute(self: *Self, code: []const u8) !void {
        var ip: usize = 0;
        while (ip < code.len) {
            const op = @as(OpCode, @enumFromInt(code[ip]));
            ip += 1;

            switch (op) {
                .PRINT => {
                    const value = self.stack.items[self.stack.items.len - 1];
                    try value.print();
                    _ = self.stack.pop();
                },
                .LOAD_CONST => {
                    const len = code[ip];
                    ip += 1;
                    const str = code[ip .. ip + len];
                    ip += len;
                    try self.stack.append(.{ .string = str });
                },
                .LOAD_INT => {
                    const val = @as(u64, code[ip]) << 56 |
                        @as(u64, code[ip + 1]) << 48 |
                        @as(u64, code[ip + 2]) << 40 |
                        @as(u64, code[ip + 3]) << 32 |
                        @as(u64, code[ip + 4]) << 24 |
                        @as(u64, code[ip + 5]) << 16 |
                        @as(u64, code[ip + 6]) << 8 |
                        @as(u64, code[ip + 7]);
                    ip += 8;
                    try self.stack.append(.{ .integer = @intCast(val) });
                },
                .LOAD_VAR => {
                    try self.stack.append(.{ .integer = @intCast(self.current_loop_index) });
                },
                .LOOP_START => {
                    const start = @as(u64, code[ip]) << 56 |
                        @as(u64, code[ip + 1]) << 48 |
                        @as(u64, code[ip + 2]) << 40 |
                        @as(u64, code[ip + 3]) << 32 |
                        @as(u64, code[ip + 4]) << 24 |
                        @as(u64, code[ip + 5]) << 16 |
                        @as(u64, code[ip + 6]) << 8 |
                        @as(u64, code[ip + 7]);
                    ip += 8;
                    const end = @as(u64, code[ip]) << 56 |
                        @as(u64, code[ip + 1]) << 48 |
                        @as(u64, code[ip + 2]) << 40 |
                        @as(u64, code[ip + 3]) << 32 |
                        @as(u64, code[ip + 4]) << 24 |
                        @as(u64, code[ip + 5]) << 16 |
                        @as(u64, code[ip + 6]) << 8 |
                        @as(u64, code[ip + 7]);
                    ip += 8;
                    const loop_body_start = ip;

                    var nested: u32 = 0;
                    var loop_end_ip = ip;
                    while (loop_end_ip < code.len) : (loop_end_ip += 1) {
                        if (code[loop_end_ip] == @intFromEnum(OpCode.LOOP_START)) nested += 1;
                        if (code[loop_end_ip] == @intFromEnum(OpCode.LOOP_END)) {
                            if (nested == 0) break;
                            nested -= 1;
                        }
                    }

                    self.current_loop_index = start;
                    self.loop_end = end;

                    while (self.current_loop_index < self.loop_end) : (self.current_loop_index += 1) {
                        try self.execute(code[loop_body_start..loop_end_ip]);
                    }

                    ip = loop_end_ip + 1;
                },
                .LOOP_END => return,
                .STDIN => {
                    var buf: [1024]u8 = undefined;
                    const input = try std.io.getStdIn().reader().readUntilDelimiter(&buf, '\n');
                    const str = try self.allocator.dupe(u8, input);
                    try self.stack.append(.{ .string = str });
                },
                .STORE => {
                    const name_len = code[ip];
                    ip += 1;
                    const name = code[ip .. ip + name_len];
                    ip += name_len;
                    const value = self.stack.pop();
                    const key = try self.allocator.dupe(u8, name);
                    try self.variables.put(key, value);
                },
            }
        }
    }
};
